import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Weather face of the linecast panel. The header leads with the place —
// clicking it reveals the location menu (recents, auto, search) — over
// the TUI's hourly chart translated to pixels: a scrollable, hoverable
// temperature line with labels at the extrema, precipitation bars, day
// shading, and UV / wind annotations where they matter. Alerts wear the
// TUI's severity badges and expand to their full text on click.
// Fed by `linecast weather --json`.
Item {
  id: view

  property var bar
  property bool shown: false
  property var host: null
  property int locationEpoch: 0
  // ThemePalette from the panel; null falls back to the fixed ramp.
  property var palette: null

  readonly property var tempStops: palette ? palette.tempStops : null
  readonly property var themeColors: palette ? palette.colors : null

  signal locationChangedByUser()

  readonly property int panelWidth: Style.space(400)
  readonly property bool editingText: searchField.activeFocus

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent

  readonly property var payload: feed.payload
  readonly property var current: payload ? payload.current : null
  readonly property var today: payload ? payload.today : null
  readonly property var units: payload ? payload.units : null
  readonly property var alerts: payload && payload.alerts ? payload.alerts : []
  readonly property var hourly: payload && payload.hourly ? payload.hourly : []
  readonly property var dailyRows: payload && payload.daily ? payload.daily : []
  readonly property var weekExtent: Model.tempExtent(dailyRows, "low", "high")
  readonly property string tempUnit: units ? units.temperature : ""
  readonly property string windUnit: units ? units.wind : ""
  readonly property string precipUnit: units ? units.precipitation : ""

  readonly property var recentLocations: recents.entries

  // Whether `linecast` is on PATH; checked each time the panel opens
  // without data, so an install shows up without a restart.
  property bool linecastMissing: false

  Process {
    id: whichProc
    command: ["bash", "-lc", "command -v linecast >/dev/null 2>&1 && echo yes || echo no"]
    stdout: StdioCollector {
      onStreamFinished: view.linecastMissing = text.trim() === "no"
    }
  }

  Process {
    id: installProc
    command: ["bash", (view.host ? view.host.pluginDir : "") + "scripts/linecast-install.sh"]
    onExited: {
      whichProc.running = true
      feed.refresh()
      if (view.host && view.host.hostWidget && typeof view.host.hostWidget.refresh === "function")
        view.host.hostWidget.refresh()
    }
  }

  // ---- Which pills ride in the bar. Weather stays; the rest are the
  //      user's call, in the canonical order.
  readonly property var pillChoices: [
    { name: "weather", label: "Weather", icon: "󰖐" },
    { name: "sunshine", label: "Sunshine", icon: "󰖜" },
    { name: "moon", label: "Moon", icon: "󰽥" },
    { name: "tides", label: "Tides", icon: "󰔍" }
  ]
  readonly property var pillsShown: view.host && view.host.hostWidget ? view.host.hostWidget.pillOrder : []
  readonly property bool pillsAlwaysOut: !!(view.host && view.host.settings && view.host.settings.alwaysShow === true)

  function pillShown(name) { return view.pillsShown.indexOf(name) !== -1 }

  property bool unitsBusy: false
  Process {
    id: unitsProc
    onExited: {
      view.unitsBusy = false
      // Same fan-out as a location change: every face refetches and the
      // pills rerun now rather than on their own schedule.
      view.locationChangedByUser()
    }
  }

  function setTemperature(key) {
    if (!view.host) return
    view.host.persistSettings({ temperature: key })
    // The flag changed under every feed and pill: same fan-out as a
    // location change.
    view.locationChangedByUser()
  }

  function setUnits(key) {
    if (view.unitsBusy) return
    view.unitsBusy = true
    unitsProc.command = ["bash", "-lc", "linecast units " + key + " >/dev/null 2>&1"]
    unitsProc.running = true
  }

  function togglePill(name) {
    if (!view.host || name === "weather") return
    var next = []
    for (var i = 0; i < view.pillChoices.length; i++) {
      var n = view.pillChoices[i].name
      var on = view.pillShown(n)
      if (n === name) on = !on
      if (on) next.push(n)
    }
    view.host.persistSettings({ pills: next })
  }

  property bool locMenuOpen: false

  function refresh() { feed.refresh() }

  onShownChanged: {
    if (shown) {
      feed.refreshIfStale()
      if (!feed.payload) whichProc.running = true
    } else view.locMenuOpen = false
  }
  // A theme swap flows into the declarative bindings on its own, but the
  // canvas reads its colors and font imperatively in onPaint — nudge it.
  onForegroundChanged: hourlyChart.requestPaint()
  onFontFamilyChanged: hourlyChart.requestPaint()
  onTempStopsChanged: hourlyChart.requestPaint()
  onLocationEpochChanged: {
    feed.payload = null
    feed.fetchedAtMs = 0
    if (shown) feed.refresh()
  }

  implicitHeight: column.implicitHeight

  JsonFeed {
    id: feed
    command: "linecast weather --json" + (view.host ? view.host.tempFlag : "")
    onPayloadChanged: hourlyChart.requestPaint()
  }

  Timer {
    interval: feed.staleAfterMs
    running: view.shown
    repeat: true
    onTriggered: feed.refresh()
  }

  // ---- Location plumbing: one process, reused for search and set.
  property var searchResults: []
  property bool locBusy: false

  Process {
    id: locProc
    property var onDone: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        view.locBusy = false
        if (locProc.onDone) locProc.onDone(text)
      }
    }
  }

  function runLoc(cmd, cb) {
    if (locProc.running) return
    view.locBusy = true
    locProc.onDone = cb
    locProc.command = ["bash", "-lc", cmd]
    locProc.running = true
  }

  function shq(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function searchLocations(query) {
    if (String(query).trim() === "") return
    runLoc("linecast location search " + shq(query) + " 2>/dev/null", function(out) {
      var rows = []
      var lines = String(out).split("\n")
      for (var i = 0; i < lines.length && rows.length < 5; i++) {
        var m = /(-?\d+\.\d+),(-?\d+\.\d+)\s+(.+)/.exec(lines[i])
        if (m) rows.push({ query: m[1] + "," + m[2], label: m[3].trim() })
      }
      view.searchResults = rows
    })
  }

  // Shared across every Linecast widget on the bar, and across restarts.
  RecentLocations {
    id: recents
    legacyEntries: view.host ? view.host.setting("recentLocations", []) : []
  }

  function rememberLocation(entry) {
    recents.remember(entry)
  }

  function applyLocation(entry) {
    runLoc("linecast location set " + shq(entry.query) + " >/dev/null 2>&1; echo done", function() {
      rememberLocation(entry)
      view.searchResults = []
      searchField.text = ""
      view.locMenuOpen = false
      view.locationChangedByUser()
    })
  }

  function applyAutoLocation() {
    runLoc("linecast location auto >/dev/null 2>&1; echo done", function() {
      view.searchResults = []
      view.locMenuOpen = false
      view.locationChangedByUser()
    })
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- Nothing yet: fetching, or no linecast to fetch with.
    Column {
      visible: !view.payload
      width: parent.width
      spacing: Style.space(12)
      topPadding: Style.space(16)
      bottomPadding: Style.space(8)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: view.linecastMissing
          ? "This widget draws on linecast, the terminal weather, sun, moon, tide, radar, and map suite. It isn't installed yet."
          : (feed.fetching ? "Fetching weather…" : "No weather data yet — try r to refetch.")
        wrapMode: Text.WordWrap
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Button {
        visible: view.linecastMissing
        anchors.horizontalCenter: parent.horizontalCenter
        iconText: "󰏔"
        text: installProc.running ? "Installing…" : "Install linecast"
        tooltipText: "From the AUR with yay, or with uv"
        bordered: true
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: if (!installProc.running) installProc.running = true
      }
    }

    // ---- Header: the place leads, and is the location menu's trigger.
    FaceHeader {
      visible: !!view.current
      icon: view.current ? (view.current.icon || "") : ""
      title: view.payload && view.payload.location !== ""
        ? Model.shortLocation(view.payload.location) : "Weather"
      subtitle: {
        if (!view.current) return ""
        var line = view.current.condition || ""
        var feels = Model.num(view.current.feels_like, NaN)
        var actual = Model.num(view.current.temperature, NaN)
        if (!isNaN(feels) && !isNaN(actual) && Math.abs(feels - actual) >= 3)
          line += " · feels " + Model.roundTemp(feels)
        return line
      }
      bigValue: view.current ? Model.roundTemp(view.current.temperature) : ""
      foreground: view.foreground
      fontFamily: view.fontFamily
      interactive: true
      onClicked: view.locMenuOpen = !view.locMenuOpen
    }

    // ---- The location menu: revealed under the header, list-style like
    //      the shell's device lists. Recents, auto, and a search field.
    Column {
      visible: view.locMenuOpen
      width: parent.width

      Repeater {
        model: view.recentLocations

        Button {
          required property var modelData
          width: column.width
          text: Model.shortLocation(modelData.label)
          iconText: view.payload && view.payload.location === modelData.label ? "󰄬" : "󰍎"
          fontSize: Style.font.body
          leftAlign: true
          foreground: view.foreground
          fontFamily: view.fontFamily
          onClicked: view.applyLocation(modelData)
        }
      }

      Button {
        width: column.width
        text: "Auto (IP geolocation)"
        iconText: "󰆤"
        fontSize: Style.font.body
        leftAlign: true
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.applyAutoLocation()
      }

      Item { width: 1; height: Style.space(6) }

      TextField {
        id: searchField
        width: parent.width
        foreground: view.foreground
        placeholderText: "Add location… (Enter to search)"
        onAccepted: view.searchLocations(text)
      }

      Text {
        visible: view.locBusy
        topPadding: Style.space(4)
        text: "Looking…"
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: view.searchResults

        Button {
          required property var modelData
          width: column.width
          text: modelData.label
          iconText: "󰍎"
          fontSize: Style.font.body
          leftAlign: true
          foreground: view.foreground
          fontFamily: view.fontFamily
          onClicked: view.applyLocation(modelData)
        }
      }
    }

    Text {
      visible: !!(view.payload && view.payload.summary) && !view.locMenuOpen
      width: parent.width
      wrapMode: Text.WordWrap
      text: view.payload ? (view.payload.summary || "") : ""
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
      font.italic: true
    }

    // ---- Alerts, TUI style: a severity badge with the timeframe and a
    //      taste of the text; the full text on click.
    Repeater {
      model: view.alerts

      Column {
        id: alertItem

        required property var modelData
        property bool expanded: false

        readonly property string tone: Model.severityTone(modelData.severity)
        readonly property color toneColor: tone === "severe" ? view.urgent
          : tone === "moderate" ? Model.tempColor(74, "°F", view.tempStops)
          : view.muted

        width: column.width
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: badge.height

          Rectangle {
            id: badge
            color: alertItem.toneColor
            width: badgeText.implicitWidth + Style.space(12)
            height: badgeText.implicitHeight + Style.space(4)

            Text {
              id: badgeText
              anchors.centerIn: parent
              text: "󰀦 " + (alertItem.modelData.event || alertItem.modelData.headline || "Alert")
              color: Color.background
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          Text {
            id: alertWhen
            anchors.verticalCenter: parent.verticalCenter
            x: badge.width + Style.space(8)
            text: Model.alertTimeframe(alertItem.modelData.effective, alertItem.modelData.expires, Qt.locale())
            color: view.muted
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            x: alertWhen.x + alertWhen.implicitWidth + (alertWhen.text !== "" ? Style.space(8) : 0)
            width: Math.max(0, parent.width - x)
            visible: !alertItem.expanded
            text: String(alertItem.modelData.description || "").replace(/\s+/g, " ")
            elide: Text.ElideRight
            color: view.muted
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: alertItem.expanded = !alertItem.expanded
          }
        }

        Text {
          visible: alertItem.expanded
          width: parent.width
          text: String(alertItem.modelData.description || "")
          wrapMode: Text.WordWrap
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: alertItem.expanded && !!alertItem.modelData.url
          text: String(alertItem.modelData.url || "")
          elide: Text.ElideMiddle
          width: parent.width
          color: Color.accent
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(alertItem.modelData.url)
          }
        }
      }
    }

    PanelSeparator { visible: view.hourly.length > 2; foreground: view.foreground }

    // ---- The hourly chart: 48 hours in view, the whole forecast on
    //      scroll, a chip on hover. Type sits on the body scale so the
    //      chart reads as part of the panel, not a miniature of it.
    Flickable {
      id: hourlyFlick
      visible: view.hourly.length > 2
      width: parent.width
      height: hourlyChart.height
      contentWidth: hourlyChart.width
      clip: true
      flickableDirection: Flickable.HorizontalFlick
      boundsBehavior: Flickable.StopAtBounds

      Canvas {
        id: hourlyChart

        // One type size across the panel: chart labels match the daily
        // rows and the info grid below.
        readonly property real capF: Style.font.bodySmall
        readonly property real hourW: column.width / 48
        readonly property real plotTop: capF + 12
        readonly property real plotBottom: plotTop + 148
        readonly property real axisY: plotBottom + capF + 6
        // The UV and wind rows only reserve height when they'll draw
        // something, so a quiet forecast doesn't leave a blank band
        // between the chart and the daily table.
        readonly property bool hasUv: view.hourly.some(function(h) {
          return Model.num(h.uv_index, 0) >= 6
        })
        readonly property bool hasWind: view.hourly.some(function(h, i) {
          return i % 3 === 0 && Model.windSignificant(Model.num(h.wind_speed, 0), view.windUnit)
        })
        readonly property real annoY1: axisY + (hasUv ? capF + 5 : 0)
        readonly property real annoY2: annoY1 + (hasWind ? capF + 4 : 0)

        readonly property int hoverIndex: chartMouse.containsMouse
          ? Math.max(0, Math.min(view.hourly.length - 1, Math.floor(chartMouse.mouseX / hourW)))
          : -1
        readonly property var hoverHour: hoverIndex >= 0 ? view.hourly[hoverIndex] : null

        width: Math.max(column.width, view.hourly.length * hourW)
        height: annoY2 + 4

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var hours = view.hourly
          if (!hours || hours.length < 3) return

          var n = hours.length
          var temps = []
          var times = []
          for (var i = 0; i < n; i++) {
            temps.push(Model.num(hours[i].temperature, NaN))
            times.push(Model.parseIsoLocal(hours[i].time))
          }

          var ext = Model.tempExtent(hours, "temperature")
          // The curve keeps clear of the plot edges so extrema labels have
          // room above the peaks and below the troughs.
          var yPad = capF + 2
          function xAt(i) { return (i + 0.5) * hourW }
          function yAt(t) {
            return (plotBottom - yPad)
              - (Math.min(1, Math.max(0, (t - ext.min) / ext.span))) * (plotBottom - plotTop - 2 * yPad)
          }

          // Day/night bands + midnight rules, from the daily sunrise/sunset
          // pairs.
          var dayMap = {}
          for (var d = 0; d < view.dailyRows.length; d++) {
            var day = view.dailyRows[d]
            dayMap[day.date] = {
              rise: Model.parseIsoLocal(day.sunrise),
              set: Model.parseIsoLocal(day.sunset)
            }
          }
          ctx.fillStyle = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.05)
          for (var b = 0; b < n; b++) {
            var dateKey = String(hours[b].time || "").slice(0, 10)
            var span = dayMap[dateKey]
            if (span && !isNaN(span.rise) && !isNaN(span.set)
                && times[b] >= span.rise && times[b] < span.set)
              ctx.fillRect(b * hourW, plotTop - 6, hourW + 0.5, plotBottom - plotTop + 6)
          }

          ctx.font = capF + "px " + view.fontFamily
          for (var m2 = 1; m2 < n; m2++) {
            var hh = String(hours[m2].time || "").slice(11, 13)
            if (hh === "00") {
              ctx.strokeStyle = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.14)
              ctx.lineWidth = 1
              ctx.beginPath()
              ctx.moveTo(m2 * hourW, plotTop - capF - 4)
              ctx.lineTo(m2 * hourW, plotBottom + 4)
              ctx.stroke()
              ctx.fillStyle = view.foreground
              ctx.fillText(Model.dayLabel(String(hours[m2].time).slice(0, 10), 1, Qt.locale()),
                           m2 * hourW + 4, capF)
            }
          }

          // Precipitation bars behind the curve, probability-scaled and
          // colored by type (rain blue, snow white, storms yellow).
          for (var p = 0; p < n; p++) {
            var prob = Model.num(hours[p].precipitation_probability, 0)
            if (prob < 15) continue
            var pc = Model.precipColorFor(hours[p].weather_code, view.foreground, view.themeColors)
            ctx.fillStyle = Qt.rgba(pc.r, pc.g, pc.b, 0.4)
            var ph = prob / 100 * 50
            ctx.fillRect(p * hourW + hourW * 0.2, plotBottom - ph, hourW * 0.6, ph)
          }

          // The temperature line, stroked per segment so it wears the ramp.
          ctx.lineWidth = 2
          ctx.lineCap = "round"
          for (var s = 1; s < n; s++) {
            if (isNaN(temps[s - 1]) || isNaN(temps[s])) continue
            ctx.strokeStyle = Model.tempColor((temps[s - 1] + temps[s]) / 2, view.tempUnit, view.tempStops)
            ctx.beginPath()
            ctx.moveTo(xAt(s - 1), yAt(temps[s - 1]))
            ctx.lineTo(xAt(s), yAt(temps[s]))
            ctx.stroke()
          }

          // Now.
          if (!isNaN(temps[0])) {
            ctx.fillStyle = view.foreground
            ctx.beginPath()
            ctx.arc(xAt(0), yAt(temps[0]), 3.5, 0, 2 * Math.PI)
            ctx.fill()
          }

          // Extrema labels, one per swing like the TUI.
          ctx.font = "bold " + capF + "px " + view.fontFamily
          var extrema = Model.findExtrema(temps, 5, 6)
          for (var e = 0; e < extrema.length; e++) {
            var ex = extrema[e]
            var label = Math.round(ex.value) + "°"
            var lw = ctx.measureText(label).width
            var lx = Math.max(2, Math.min(width - lw - 2, xAt(ex.index) - lw / 2))
            var ly = ex.kind === "max" ? yAt(ex.value) - 6 : yAt(ex.value) + capF + 4
            ctx.fillStyle = Model.tempColor(ex.value, view.tempUnit, view.tempStops)
            ctx.fillText(label, lx, ly)
          }

          // Hour axis, every three hours.
          ctx.font = capF + "px " + view.fontFamily
          ctx.fillStyle = view.muted
          for (var a = 0; a < n; a += 1) {
            var ah = Number(String(hours[a].time || "").slice(11, 13))
            if (a !== 0 && (ah % 3 !== 0 || a < 2)) continue
            var atext = a === 0 ? "now" : Model.hourLabel(hours[a].time)
            ctx.fillText(atext, Math.max(2, xAt(a) - ctx.measureText(atext).width / 2), axisY)
          }

          // UV row: label the peak of each remarkable (>= 6) stretch.
          ctx.font = "bold " + capF + "px " + view.fontFamily
          var u = 0
          while (u < n) {
            var uv = Model.num(hours[u].uv_index, 0)
            if (uv < 6) { u++; continue }
            var peakI = u, peakV = uv
            var v = u
            while (v < n && Model.num(hours[v].uv_index, 0) >= 6) {
              if (Model.num(hours[v].uv_index, 0) > peakV) { peakV = Model.num(hours[v].uv_index, 0); peakI = v }
              v++
            }
            var utext = "UV" + Math.round(peakV)
            ctx.fillStyle = Model.tempColor(88, "°F", view.tempStops)
            ctx.fillText(utext, Math.max(2, xAt(peakI) - ctx.measureText(utext).width / 2), annoY1)
            u = v
          }

          // Wind row: arrow and speed where it blows hard enough to matter,
          // at most one label per three hours.
          ctx.font = capF + "px " + view.fontFamily
          ctx.fillStyle = view.muted
          for (var w2 = 0; w2 < n; w2 += 3) {
            var ws = Model.num(hours[w2].wind_speed, 0)
            if (!Model.windSignificant(ws, view.windUnit)) continue
            var wtext = Model.windArrow(hours[w2].wind_direction) + Math.round(ws)
            ctx.fillText(wtext, Math.max(2, xAt(w2) - ctx.measureText(wtext).width / 2), annoY2)
          }
        }

        // Hover only — no buttons accepted, so horizontal flicks still
        // reach the Flickable underneath.
        MouseArea {
          id: chartMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }

        Rectangle {
          visible: hourlyChart.hoverIndex >= 0
          x: (hourlyChart.hoverIndex + 0.5) * hourlyChart.hourW
          y: hourlyChart.plotTop - 4
          width: 1
          height: hourlyChart.plotBottom - hourlyChart.plotTop + 8
          color: Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.3)
        }

        // The chip, TUI style: time, temperature (feels), condition. It
        // anchors to the hovered hour's column — data is hourly, so the
        // chip steps hour to hour rather than trailing the pointer.
        Rectangle {
          id: hoverChip
          visible: hourlyChart.hoverHour !== null
          x: Math.max(hourlyFlick.contentX + 4,
             Math.min(hourlyFlick.contentX + hourlyFlick.width - width - 4,
                      (hourlyChart.hoverIndex + 0.5) * hourlyChart.hourW + Style.space(14)))
          // Rides with the pointer like the TUI's chip: above it when
          // there's room, below it near the top.
          y: {
            var above = chartMouse.mouseY - height - Style.space(10)
            return above >= 0 ? above : Math.min(hourlyChart.height - height, chartMouse.mouseY + Style.space(14))
          }
          width: chipColumn.implicitWidth + Style.space(16)
          height: chipColumn.implicitHeight + Style.space(12)
          color: Color.tooltip.background
          border.color: Color.tooltip.border
          border.width: 1

          Column {
            id: chipColumn
            anchors.centerIn: parent
            spacing: Style.space(1)

            Text {
              text: hourlyChart.hoverHour ? Model.clockLabel(hourlyChart.hoverHour.time) : ""
              color: Color.tooltip.text
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              spacing: Style.space(5)

              Text {
                text: hourlyChart.hoverHour ? Model.roundTemp(hourlyChart.hoverHour.temperature) : ""
                color: hourlyChart.hoverHour
                  ? Model.tempColor(hourlyChart.hoverHour.temperature, view.tempUnit, view.tempStops)
                  : Color.tooltip.text
                font.family: view.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                visible: hourlyChart.hoverHour && Model.num(hourlyChart.hoverHour.feels_like, NaN) === Model.num(hourlyChart.hoverHour.feels_like, NaN)
                text: hourlyChart.hoverHour ? "feels " + Model.roundTemp(hourlyChart.hoverHour.feels_like) : ""
                color: Qt.darker(Color.tooltip.text, 1.3)
                font.family: view.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Text {
              text: hourlyChart.hoverHour ? (hourlyChart.hoverHour.condition || "") : ""
              color: Color.tooltip.text
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              visible: hourlyChart.hoverHour && Model.num(hourlyChart.hoverHour.precipitation_probability, 0) >= 15
              text: hourlyChart.hoverHour ? Math.round(Model.num(hourlyChart.hoverHour.precipitation_probability, 0)) + "% precip" : ""
              color: {
                var pc = Model.precipColorFor(hourlyChart.hoverHour ? hourlyChart.hoverHour.weather_code : 0,
                                              Color.tooltip.text, view.themeColors)
                return Qt.rgba(pc.r, pc.g, pc.b, 1)
              }
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }

    PanelSeparator { visible: view.dailyRows.length > 0; foreground: view.foreground }

    // ---- Daily rows: day, glyph, low, range bar, high, and the TUI's
    //      right-hand annotations.
    Column {
      visible: view.dailyRows.length > 0
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: view.dailyRows

        Item {
          id: dayRow

          required property var modelData
          required property int index

          readonly property real prob: Model.num(modelData.precipitation_probability, 0)
          readonly property string amountLabel: Model.precipAmountLabel(modelData.precipitation, view.precipUnit)
          readonly property string precipLabel: {
            var parts = []
            if (prob > 25) parts.push(Math.round(prob) + "%")
            if (amountLabel !== "") parts.push(amountLabel)
            return parts.join(" ")
          }
          readonly property string windLabel: Model.windSignificant(modelData.wind_speed, view.windUnit)
            ? "󰖝" + Math.round(modelData.wind_speed) : ""

          width: column.width
          height: Math.max(dayName.implicitHeight, Style.space(16))

          Text {
            id: dayName
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(52)
            text: Model.dayLabel(modelData.date, index, Qt.locale())
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: index === 0
          }

          Text {
            id: dayIcon
            anchors.verticalCenter: parent.verticalCenter
            x: dayName.width
            width: Style.space(24)
            text: modelData.icon || ""
            color: dayRow.prob >= 40 ? view.foreground : view.muted
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Item {
            id: rangeArea
            anchors.verticalCenter: parent.verticalCenter
            x: dayIcon.x + dayIcon.width
            // The right edge is fixed across rows so every bar shares the
            // week axis; only the annotations vary in width.
            width: parent.width - Style.space(72) - x
            height: parent.height

            // Low/high ride the ends of each day's bar like the TUI, so
            // the numbers trace the week's shape instead of sitting in
            // columns. The insets keep a label's worth of room beyond the
            // week's extremes.
            readonly property real inset: Style.space(34)
            readonly property real fillX: inset
              + Model.extentPos(dayRow.modelData.low, view.weekExtent) * (width - 2 * inset)
            readonly property real fillW: Math.max(Style.space(6),
              (Model.extentPos(dayRow.modelData.high, view.weekExtent)
               - Model.extentPos(dayRow.modelData.low, view.weekExtent)) * (width - 2 * inset))

            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: rangeArea.fillX - width - Style.space(6)
              text: Model.roundTemp(dayRow.modelData.low)
              color: view.muted
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              id: rangeFill
              anchors.verticalCenter: parent.verticalCenter
              x: rangeArea.fillX
              width: rangeArea.fillW
              height: Style.space(6)
              radius: height / 2

              readonly property real lowT: Model.num(dayRow.modelData.low, 60)
              readonly property real highT: Model.num(dayRow.modelData.high, 60)

              // Stops sample the ramp along the way rather than lerping
              // endpoint colors straight across RGB space.
              function rampAt(f) {
                return Model.tempColor(rangeFill.lowT + (rangeFill.highT - rangeFill.lowT) * f,
                                       view.tempUnit, view.tempStops)
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

            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: rangeArea.fillX + rangeArea.fillW + Style.space(6)
              text: Model.roundTemp(dayRow.modelData.high)
              color: view.foreground
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            id: annoCol
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            spacing: Style.space(6)

            Text {
              text: dayRow.precipLabel
              visible: text !== ""
              color: {
                var pc = Model.precipColorFor(dayRow.modelData.weather_code, view.foreground, view.themeColors)
                return Qt.rgba(pc.r, pc.g, pc.b, 1)
              }
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              text: dayRow.windLabel
              visible: text !== ""
              color: view.muted
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }

    PanelSeparator { visible: !!view.current; foreground: view.foreground }

    // ---- Info grid, battery-panel style.
    Row {
      visible: !!view.current
      width: parent.width
      spacing: Style.space(16)

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(4)

        InfoPair {
          label: "Wind"
          value: Model.windLine(view.current, view.units)
          foreground: view.foreground
          fontFamily: view.fontFamily
        }

        InfoPair {
          label: "Humidity"
          value: view.current && Model.num(view.current.humidity, -1) >= 0
            ? Math.round(view.current.humidity) + "%" : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }

        InfoPair {
          label: "Air quality"
          value: view.payload && view.payload.aqi && Model.num(view.payload.aqi.us_aqi, -1) >= 0
            ? "AQI " + Math.round(view.payload.aqi.us_aqi) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(4)

        InfoPair {
          label: "Sunrise"
          value: view.today ? Model.clockLabel(view.today.sunrise) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }

        InfoPair {
          label: "Sunset"
          value: view.today ? Model.clockLabel(view.today.sunset) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }

        InfoPair {
          label: "UV now"
          value: view.hourly.length > 0 && Model.num(view.hourly[0].uv_index, -1) >= 0
            ? String(Math.round(view.hourly[0].uv_index)) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }
    }

    PanelSeparator { visible: !!view.current; foreground: view.foreground }

    // ---- The bar: which of linecast's pills ride in it.
    Column {
      visible: !!view.current
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: "PILLS IN THE BAR"
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: view.pillChoices

          Button {
            required property var modelData
            width: (parent.width - Style.space(6) * 3) / 4
            iconText: modelData.icon
            text: modelData.label
            fontSize: Style.font.bodySmall
            bordered: true
            selected: view.pillShown(modelData.name)
            tooltipText: modelData.name === "weather" ? "Always in the bar" : (view.pillShown(modelData.name) ? "Take it off the bar" : "Put it on the bar")
            foreground: view.foreground
            fontFamily: view.fontFamily
            onClicked: view.togglePill(modelData.name)
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        ToggleSwitch {
          id: alwaysOutSwitch
          anchors.verticalCenter: parent.verticalCenter
          checked: view.pillsAlwaysOut
          foreground: view.foreground
          onToggled: if (view.host) view.host.persistSettings({ alwaysShow: !view.pillsAlwaysOut })
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: view.pillsAlwaysOut ? "Every pill stays out" : "Extra pills slide out on hover"
          color: view.muted
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    // ---- Temperature, measures, and the clock. Temperature is the
    //      widget's own setting (a flag on every linecast call); measures
    //      are linecast's units switch, so the terminal views agree.
    Row {
      visible: !!view.current
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: [
          { key: "fahrenheit", label: "°F", tip: "Fahrenheit" },
          { key: "celsius", label: "°C", tip: "Celsius" }
        ]

        Button {
          required property var modelData
          width: (parent.width - Style.space(6) * 3) / 4
          text: modelData.label
          tooltipText: modelData.tip
          fontSize: Style.font.bodySmall
          bordered: true
          selected: (view.tempUnit === "°C") === (modelData.key === "celsius")
          foreground: view.foreground
          fontFamily: view.fontFamily
          onClicked: view.setTemperature(modelData.key)
        }
      }

      Repeater {
        model: [
          { key: "24h", label: "24h" },
          { key: "12h", label: "12h" }
        ]

        Button {
          required property var modelData
          width: (parent.width - Style.space(6) * 3) / 4
          text: modelData.label
          fontSize: Style.font.bodySmall
          bordered: true
          selected: (view.host && view.host.settings && view.host.settings.clock === "12h") === (modelData.key === "12h")
          foreground: view.foreground
          fontFamily: view.fontFamily
          onClicked: if (view.host) { view.host.persistSettings({ clock: modelData.key }); hourlyChart.requestPaint() }
        }
      }
    }

    Row {
      visible: !!view.current
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: [
          { key: "imperial", label: "mph · in · ft", tip: "Wind in mph, rain in inches, tides in feet" },
          { key: "metric", label: "km/h · mm · m", tip: "Wind in km/h, rain in mm, tides in metres" }
        ]

        Button {
          required property var modelData
          width: (parent.width - Style.space(6)) / 2
          text: modelData.label
          tooltipText: modelData.tip
          fontSize: Style.font.bodySmall
          bordered: true
          selected: (view.windUnit === "km/h") === (modelData.key === "metric")
          foreground: view.foreground
          fontFamily: view.fontFamily
          onClicked: view.setUnits(modelData.key)
        }
      }
    }

    PanelSeparator { visible: !!view.current; foreground: view.foreground }

    // ---- linecast itself, in a terminal.
    Column {
      visible: !!view.current
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: "IN THE TERMINAL"
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: [
            { name: "radar", label: "Radar", icon: "󰼯", tip: "Live precipitation radar, animated" },
            { name: "maps", label: "Maps", icon: "󰍎", tip: "Terrain, streets, and the globe" },
            { name: "weather", label: "Weather", icon: "󰆍", tip: "The full forecast, live" }
          ]

          Button {
            required property var modelData
            width: (parent.width - Style.space(6) * 2) / 3
            iconText: modelData.icon
            text: modelData.label
            tooltipText: modelData.tip
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: view.foreground
            fontFamily: view.fontFamily
            onClicked: if (view.host) view.host.launch(modelData.name)
          }
        }
      }
    }
  }
}
