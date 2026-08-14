import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The weather pill's popup: current conditions over an hourly strip and a
// week of Apple-style temperature range bars, all fed by
// `linecast weather --json`. Follows the clock plugin's panel composition —
// hero over detail, small-caps section labels, the shared spacing scale.
//
// BarWidget.qml owns the pills and hands this panel the weather pill to
// anchor against.
Panel {
  id: root
  moduleName: "ashuttl.linecast"
  ipcTarget: "ashuttl.linecast"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by must be that
  // widget (popout coordinator, switchPanelFrom).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Data. The payload is refetched on open when stale and on a timer
  //      while the panel is up; the last good payload survives a failed
  //      fetch so reopening offline still shows something.
  property var payload: null
  property bool fetching: false
  property double fetchedAtMs: 0
  readonly property int staleAfterMs: 10 * 60 * 1000

  readonly property var current: payload ? payload.current : null
  readonly property var today: payload ? payload.today : null
  readonly property var units: payload ? payload.units : null
  readonly property var alerts: payload && payload.alerts ? payload.alerts : []
  readonly property var hourColumns: payload ? Model.sampleHours(payload.hourly, 2, 12) : []
  readonly property var dailyRows: payload && payload.daily ? payload.daily : []
  readonly property var hourExtent: Model.tempExtent(hourColumns, "temperature")
  readonly property var weekExtent: Model.tempExtent(dailyRows, "low", "high")

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color mutedForeground: Qt.darker(contentForeground, 1.4)

  readonly property int panelWidth: Style.space(380)

  function refresh() {
    if (fetchProc.running) return
    root.fetching = true
    fetchProc.running = true
  }

  function refreshIfStale() {
    if (!payload || Date.now() - fetchedAtMs > staleAfterMs) refresh()
  }

  function open() {
    refreshIfStale()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears
    // the shared flag (same dance as the clock panel).
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  Process {
    id: fetchProc
    command: ["bash", "-lc", "linecast weather --json 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.fetching = false
        var parsed = Model.parsePayload(text)
        if (parsed) {
          root.payload = parsed
          root.fetchedAtMs = Date.now()
        }
      }
    }
  }

  Timer {
    interval: root.staleAfterMs
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(weatherColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

      Column {
        id: weatherColumn
        width: parent.width
        spacing: Style.space(10)

        // ---- Empty state: first open before linecast answers, or a
        //      linecast build without --json yet.
        Text {
          visible: !root.payload
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(24)
          bottomPadding: Style.space(24)
          text: root.fetching ? "Fetching weather…" : "No weather data — is linecast ≥ 1.9 installed?"
          wrapMode: Text.WordWrap
          color: root.mutedForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        // ---- Hero: glyph and temperature, condition and place beneath.
        Column {
          visible: !!root.current
          width: parent.width
          spacing: Style.space(2)

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(18)

            Text {
              anchors.baseline: heroTemp.baseline
              text: root.current ? (root.current.icon || "") : ""
              color: root.contentForeground
              font.family: root.contentFontFamily
              // Decorative, deliberately outside the Style.font.* scale —
              // sized to the cap height of the temperature beside it.
              font.pixelSize: 44
            }

            Text {
              id: heroTemp
              text: root.current ? Model.roundTemp(root.current.temperature) : ""
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: 52
              font.bold: true
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
              if (!root.current) return ""
              var line = root.current.condition || ""
              var feels = Model.num(root.current.feels_like, NaN)
              var actual = Model.num(root.current.temperature, NaN)
              if (!isNaN(feels) && !isNaN(actual) && Math.abs(feels - actual) >= 3)
                line += "  ·  feels " + Model.roundTemp(feels)
              return line
            }
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
              var line = root.payload ? (root.payload.location || "") : ""
              if (root.today) {
                var hi = Model.roundTemp(root.today.high)
                var lo = Model.roundTemp(root.today.low)
                if (hi !== "–" && lo !== "–") line += "  ·  " + lo + " / " + hi
              }
              return line
            }
            color: root.mutedForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---- Alerts, when the region has any: urgent-tinted, above the
        //      forecast so a warning is never below the fold.
        Repeater {
          model: root.alerts

          Row {
            required property var modelData
            width: weatherColumn.width
            spacing: Style.space(8)

            Text {
              text: ""
              color: Model.severityIsUrgent(modelData.severity) ? (root.bar ? root.bar.urgent : Color.urgent) : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width - x
              text: modelData.event || modelData.headline || ""
              elide: Text.ElideRight
              color: Model.severityIsUrgent(modelData.severity) ? (root.bar ? root.bar.urgent : Color.urgent) : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        PanelSeparator { visible: !!root.payload; foreground: root.contentForeground }

        PanelSectionHeader {
          visible: root.hourColumns.length > 0
          text: "NEXT 24 HOURS"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        // ---- Hourly strip: one column per sampled hour, temperature over
        //      a bar scaled within the strip's own min/max.
        Row {
          visible: root.hourColumns.length > 0
          width: parent.width

          Repeater {
            model: root.hourColumns

            Column {
              required property var modelData
              required property int index
              width: weatherColumn.width / Math.max(1, root.hourColumns.length)
              spacing: Style.space(4)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Model.roundTemp(modelData.temperature)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(8)
                height: Style.space(44)

                Rectangle {
                  anchors.bottom: parent.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width
                  radius: width / 2
                  height: Style.space(8)
                    + Model.extentPos(modelData.temperature, root.hourExtent) * (parent.height - Style.space(8))
                  color: Model.num(modelData.precipitation_probability, 0) >= 40
                    ? root.mutedForeground
                    : Color.accent
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: index === 0 ? "now" : Model.hourLabel(modelData.time)
                color: root.mutedForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        PanelSeparator { visible: root.dailyRows.length > 0; foreground: root.contentForeground }

        PanelSectionHeader {
          visible: root.dailyRows.length > 0
          text: "THIS WEEK"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        // ---- Daily rows: day, glyph, low, range bar, high. The bar is
        //      positioned within the whole week's extent so warm and cold
        //      days read against each other, not just against themselves.
        Column {
          visible: root.dailyRows.length > 0
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.dailyRows

            Item {
              required property var modelData
              required property int index
              width: weatherColumn.width
              height: Math.max(dayName.implicitHeight, Style.space(16))

              Text {
                id: dayName
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(58)
                text: Model.dayLabel(modelData.date, index, Qt.locale())
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: index === 0
              }

              Text {
                id: dayIcon
                anchors.verticalCenter: parent.verticalCenter
                x: dayName.width
                width: Style.space(26)
                text: modelData.icon || ""
                color: Model.num(modelData.precipitation_probability, 0) >= 40
                  ? root.contentForeground : root.mutedForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: dayLow
                anchors.verticalCenter: parent.verticalCenter
                x: dayIcon.x + dayIcon.width
                width: Style.space(34)
                horizontalAlignment: Text.AlignRight
                text: Model.roundTemp(modelData.low)
                color: root.mutedForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Item {
                id: rangeTrack
                anchors.verticalCenter: parent.verticalCenter
                x: dayLow.x + dayLow.width + Style.space(10)
                width: dayHigh.x - Style.space(10) - x
                height: Style.space(6)

                Rectangle {
                  anchors.fill: parent
                  radius: height / 2
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.15)
                }

                Rectangle {
                  x: Model.extentPos(modelData.low, root.weekExtent) * parent.width
                  width: Math.max(height, (Model.extentPos(modelData.high, root.weekExtent)
                    - Model.extentPos(modelData.low, root.weekExtent)) * parent.width)
                  height: parent.height
                  radius: height / 2
                  color: Color.accent
                }
              }

              Text {
                id: dayHigh
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - width
                width: Style.space(34)
                horizontalAlignment: Text.AlignRight
                text: Model.roundTemp(modelData.high)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        PanelSeparator { visible: !!root.current; foreground: root.contentForeground }

        // ---- Footer stats: the numbers worth a glance but not a section.
        Row {
          visible: !!root.current
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(20)
          bottomPadding: Style.space(4)

          FooterStat {
            glyph: "󰖝"
            value: Model.windLine(root.current, root.units)
          }

          FooterStat {
            glyph: ""
            value: root.current && Model.num(root.current.humidity, -1) >= 0
              ? Math.round(root.current.humidity) + "%" : ""
          }

          FooterStat {
            glyph: "󰖜"
            value: root.today ? Model.clockLabel(root.today.sunrise) : ""
          }

          FooterStat {
            glyph: "󰖛"
            value: root.today ? Model.clockLabel(root.today.sunset) : ""
          }

          FooterStat {
            glyph: "AQI"
            value: root.payload && root.payload.aqi && Model.num(root.payload.aqi.us_aqi, -1) >= 0
              ? String(Math.round(root.payload.aqi.us_aqi)) : ""
          }
        }
      }
    }
  }

  component FooterStat: Row {
    property string glyph: ""
    property string value: ""

    visible: value !== ""
    spacing: Style.space(5)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: glyph
      color: root.mutedForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: value
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
