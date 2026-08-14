import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Weather face of the linecast panel: current conditions and the
// comparative summary over an hourly strip, a week of range bars, and
// glance stats. Fed by `linecast weather --json`.
Item {
  id: view

  property var bar
  property bool shown: false

  readonly property int panelWidth: Style.space(380)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)

  readonly property var payload: feed.payload
  readonly property var current: payload ? payload.current : null
  readonly property var today: payload ? payload.today : null
  readonly property var units: payload ? payload.units : null
  readonly property var alerts: payload && payload.alerts ? payload.alerts : []
  readonly property var hourColumns: payload ? Model.sampleHours(payload.hourly, 2, 12) : []
  readonly property var dailyRows: payload && payload.daily ? payload.daily : []
  readonly property var hourExtent: Model.tempExtent(hourColumns, "temperature")
  readonly property var weekExtent: Model.tempExtent(dailyRows, "low", "high")
  readonly property string tempUnit: units ? units.temperature : ""

  function refresh() { feed.refresh() }

  onShownChanged: if (shown) feed.refreshIfStale()

  implicitHeight: column.implicitHeight

  JsonFeed {
    id: feed
    command: "linecast weather --json"
  }

  Timer {
    interval: feed.staleAfterMs
    running: view.shown
    repeat: true
    onTriggered: feed.refresh()
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- Empty state: first open before linecast answers, or a linecast
    //      build without --json yet.
    Text {
      visible: !view.payload
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      topPadding: Style.space(24)
      bottomPadding: Style.space(24)
      text: feed.fetching ? "Fetching weather…" : "No weather data — is linecast ≥ 1.9 installed?"
      wrapMode: Text.WordWrap
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }

    // ---- Hero: glyph and temperature, condition and place beneath.
    Column {
      visible: !!view.current
      width: parent.width
      spacing: Style.space(2)

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(18)

        Text {
          anchors.baseline: heroTemp.baseline
          text: view.current ? (view.current.icon || "") : ""
          color: view.foreground
          font.family: view.fontFamily
          // Decorative, deliberately outside the Style.font.* scale —
          // sized to the cap height of the temperature beside it.
          font.pixelSize: 44
        }

        Text {
          id: heroTemp
          text: view.current ? Model.roundTemp(view.current.temperature) : ""
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: 52
          font.bold: true
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: {
          if (!view.current) return ""
          var line = view.current.condition || ""
          var feels = Model.num(view.current.feels_like, NaN)
          var actual = Model.num(view.current.temperature, NaN)
          if (!isNaN(feels) && !isNaN(actual) && Math.abs(feels - actual) >= 3)
            line += "  ·  feels " + Model.roundTemp(feels)
          return line
        }
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: {
          var line = view.payload ? (view.payload.location || "") : ""
          if (view.today) {
            var hi = Model.roundTemp(view.today.high)
            var lo = Model.roundTemp(view.today.low)
            if (hi !== "–" && lo !== "–") line += "  ·  " + lo + " / " + hi
          }
          return line
        }
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: !!(view.payload && view.payload.summary)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, column.width)
        topPadding: Style.space(4)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: view.payload ? (view.payload.summary || "") : ""
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        font.italic: true
      }
    }

    // ---- Alerts, when the region has any: urgent-tinted, above the
    //      forecast so a warning is never below the fold.
    Repeater {
      model: view.alerts

      Row {
        required property var modelData
        width: column.width
        spacing: Style.space(8)

        Text {
          text: ""
          color: Model.severityIsUrgent(modelData.severity) ? (view.bar ? view.bar.urgent : Color.urgent) : view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width - x
          text: modelData.event || modelData.headline || ""
          elide: Text.ElideRight
          color: Model.severityIsUrgent(modelData.severity) ? (view.bar ? view.bar.urgent : Color.urgent) : view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    PanelSeparator { visible: !!view.payload; foreground: view.foreground }

    PanelSectionHeader {
      visible: view.hourColumns.length > 0
      text: "NEXT 24 HOURS"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    // ---- Hourly strip: one column per sampled hour, temperature over a
    //      bar scaled within the strip's own min/max.
    Row {
      visible: view.hourColumns.length > 0
      width: parent.width

      Repeater {
        model: view.hourColumns

        Column {
          required property var modelData
          required property int index
          width: column.width / Math.max(1, view.hourColumns.length)
          spacing: Style.space(4)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Model.roundTemp(modelData.temperature)
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(8)
            height: Style.space(44)

            // The bar spans the strip's own extent, so its gradient runs
            // from the color of the strip minimum at the base up to this
            // hour's own temperature color at the tip.
            Rectangle {
              id: hourBar
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width
              radius: width / 2
              height: Style.space(8)
                + Model.extentPos(modelData.temperature, view.hourExtent) * (parent.height - Style.space(8))

              readonly property real tipT: Model.num(modelData.temperature, 60)
              readonly property real baseT: view.hourExtent.min

              gradient: Gradient {
                GradientStop { position: 0.0; color: Model.tempColor(hourBar.tipT, view.tempUnit) }
                GradientStop { position: 0.5; color: Model.tempColor(hourBar.baseT + (hourBar.tipT - hourBar.baseT) * 0.5, view.tempUnit) }
                GradientStop { position: 1.0; color: Model.tempColor(hourBar.baseT, view.tempUnit) }
              }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: index === 0 ? "now" : Model.hourLabel(modelData.time)
            color: view.muted
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    PanelSeparator { visible: view.dailyRows.length > 0; foreground: view.foreground }

    PanelSectionHeader {
      visible: view.dailyRows.length > 0
      text: "THIS WEEK"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    // ---- Daily rows: day, glyph, low, range bar, high. The bar is
    //      positioned within the whole week's extent so warm and cold days
    //      read against each other, not just against themselves.
    Column {
      visible: view.dailyRows.length > 0
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: view.dailyRows

        Item {
          required property var modelData
          required property int index
          width: column.width
          height: Math.max(dayName.implicitHeight, Style.space(16))

          Text {
            id: dayName
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(58)
            text: Model.dayLabel(modelData.date, index, Qt.locale())
            color: view.foreground
            font.family: view.fontFamily
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
              ? view.foreground : view.muted
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: dayLow
            anchors.verticalCenter: parent.verticalCenter
            x: dayIcon.x + dayIcon.width
            width: Style.space(34)
            horizontalAlignment: Text.AlignRight
            text: Model.roundTemp(modelData.low)
            color: view.muted
            font.family: view.fontFamily
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
              color: Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.15)
            }

            Rectangle {
              id: rangeFill
              x: Model.extentPos(modelData.low, view.weekExtent) * parent.width
              width: Math.max(height, (Model.extentPos(modelData.high, view.weekExtent)
                - Model.extentPos(modelData.low, view.weekExtent)) * parent.width)
              height: parent.height
              radius: height / 2

              readonly property real lowT: Model.num(modelData.low, 60)
              readonly property real highT: Model.num(modelData.high, 60)

              // Stops sample the ramp along the way rather than lerping
              // straight from low color to high color — a 51°–78° day
              // passes through green and yellow like the TUI, instead of
              // a teal-to-orange shortcut across RGB space.
              function rampAt(f) {
                return Model.tempColor(rangeFill.lowT + (rangeFill.highT - rangeFill.lowT) * f, view.tempUnit)
              }

              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: rangeFill.rampAt(0.00) }
                GradientStop { position: 0.25; color: rangeFill.rampAt(0.25) }
                GradientStop { position: 0.50; color: rangeFill.rampAt(0.50) }
                GradientStop { position: 0.75; color: rangeFill.rampAt(0.75) }
                GradientStop { position: 1.00; color: rangeFill.rampAt(1.00) }
              }
            }
          }

          Text {
            id: dayHigh
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - width
            width: Style.space(34)
            horizontalAlignment: Text.AlignRight
            text: Model.roundTemp(modelData.high)
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }

    PanelSeparator { visible: !!view.current; foreground: view.foreground }

    // ---- Footer stats: the numbers worth a glance but not a section.
    Row {
      visible: !!view.current
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(20)
      bottomPadding: Style.space(4)

      GlanceStat {
        glyph: "󰖝"
        value: Model.windLine(view.current, view.units)
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }

      GlanceStat {
        glyph: ""
        value: view.current && Model.num(view.current.humidity, -1) >= 0
          ? Math.round(view.current.humidity) + "%" : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }

      GlanceStat {
        glyph: "󰖜"
        value: view.today ? Model.clockLabel(view.today.sunrise) : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }

      GlanceStat {
        glyph: "󰖛"
        value: view.today ? Model.clockLabel(view.today.sunset) : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }

      GlanceStat {
        glyph: "AQI"
        value: view.payload && view.payload.aqi && Model.num(view.payload.aqi.us_aqi, -1) >= 0
          ? String(Math.round(view.payload.aqi.us_aqi)) : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }
    }
  }

}
