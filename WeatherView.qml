import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Weather face of the linecast panel, composed the way the stock panels
// are: header with a small-caps status line and a display-sized reading,
// two-column info grid, section headers between rules. The body is the
// TUI's hourly chart translated to pixels — a scrollable temperature line
// with labels at the extrema, precipitation bars, day shading, and UV /
// wind annotations where they matter — over the week's range bars.
// Fed by `linecast weather --json`.
Item {
  id: view

  property var bar
  property bool shown: false
  property var host: null
  property int locationEpoch: 0

  signal locationChangedByUser()

  readonly property int panelWidth: Style.space(400)
  readonly property bool editingText: searchField.activeFocus

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)

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

  readonly property var recentLocations: host ? host.setting("recentLocations", []) : []

  function refresh() { feed.refresh() }

  onShownChanged: if (shown) feed.refreshIfStale()
  onLocationEpochChanged: {
    feed.payload = null
    feed.fetchedAtMs = 0
    if (shown) feed.refresh()
  }

  implicitHeight: column.implicitHeight

  JsonFeed {
    id: feed
    command: "linecast weather --json"
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

  function rememberLocation(entry) {
    var next = [entry]
    for (var i = 0; i < view.recentLocations.length && next.length < 10; i++) {
      var r = view.recentLocations[i]
      if (r && r.label !== entry.label) next.push(r)
    }
    if (view.host && typeof view.host.persistSettings === "function")
      view.host.persistSettings({ recentLocations: next })
  }

  function applyLocation(entry) {
    runLoc("linecast location set " + shq(entry.query) + " >/dev/null 2>&1; echo done", function() {
      rememberLocation(entry)
      view.searchResults = []
      searchField.text = ""
      view.locationChangedByUser()
    })
  }

  function applyAutoLocation() {
    runLoc("linecast location auto >/dev/null 2>&1; echo done", function() {
      view.searchResults = []
      view.locationChangedByUser()
    })
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

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

    // ---- Header, battery-panel style: condition as the status line, the
    //      temperature as the reading.
    FaceHeader {
      visible: !!view.current
      icon: view.current ? (view.current.icon || "") : ""
      title: "Weather"
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
    }

    Text {
      visible: !!(view.payload && view.payload.summary)
      width: parent.width
      wrapMode: Text.WordWrap
      text: view.payload ? (view.payload.summary || "") : ""
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
      font.italic: true
    }

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

    PanelSeparator { visible: view.hourly.length > 2; foreground: view.foreground }

    PanelSectionHeader {
      visible: view.hourly.length > 2
      text: "HOURLY"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    // ---- The hourly chart: 24 hours in view, the whole forecast on
    //      scroll. Line plot over day-shaded bands with precip bars
    //      beneath the curve and UV / wind rows under the axis.
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

        readonly property real hourW: column.width / 24
        readonly property real plotTop: 18
        readonly property real plotBottom: 96
        readonly property real axisY: 112
        readonly property real annoY1: 128
        readonly property real annoY2: 142

        width: Math.max(column.width, view.hourly.length * hourW)
        height: 148

        onWidthChanged: requestPaint()

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
          var yPad = 10
          function xAt(i) { return (i + 0.5) * hourW }
          function yAt(t) {
            return (plotBottom - yPad)
              - (Math.min(1, Math.max(0, (t - ext.min) / ext.span))) * (plotBottom - plotTop - 2 * yPad)
          }

          // Day/night bands + midnight rules, from the daily sunrise/sunset
          // pairs. Sun-up hours get a faint lift, midnights a rule and the
          // day's name.
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

          ctx.font = "9px " + view.fontFamily
          for (var m2 = 1; m2 < n; m2++) {
            var hh = String(hours[m2].time || "").slice(11, 13)
            if (hh === "00") {
              ctx.strokeStyle = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.14)
              ctx.lineWidth = 1
              ctx.beginPath()
              ctx.moveTo(m2 * hourW, plotTop - 12)
              ctx.lineTo(m2 * hourW, plotBottom + 4)
              ctx.stroke()
              ctx.fillStyle = view.foreground
              ctx.fillText(Model.dayLabel(String(hours[m2].time).slice(0, 10), 1, Qt.locale()),
                           m2 * hourW + 3, 10)
            }
          }

          // Precipitation bars behind the curve, probability-scaled and
          // colored by type (rain blue, snow white, storms yellow).
          for (var p = 0; p < n; p++) {
            var prob = Model.num(hours[p].precipitation_probability, 0)
            if (prob < 15) continue
            var pc = Model.precipColorFor(hours[p].weather_code, view.foreground)
            ctx.fillStyle = Qt.rgba(pc.r, pc.g, pc.b, 0.4)
            var ph = prob / 100 * 26
            ctx.fillRect(p * hourW + hourW * 0.2, plotBottom - ph, hourW * 0.6, ph)
          }

          // The temperature line, stroked per segment so it wears the ramp.
          ctx.lineWidth = 2
          ctx.lineCap = "round"
          for (var s = 1; s < n; s++) {
            if (isNaN(temps[s - 1]) || isNaN(temps[s])) continue
            ctx.strokeStyle = Model.tempColor((temps[s - 1] + temps[s]) / 2, view.tempUnit)
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
          ctx.font = "bold 10px " + view.fontFamily
          var extrema = Model.findExtrema(temps, 5, 6)
          for (var e = 0; e < extrema.length; e++) {
            var ex = extrema[e]
            var label = Math.round(ex.value) + "°"
            var lw = ctx.measureText(label).width
            var lx = Math.max(2, Math.min(width - lw - 2, xAt(ex.index) - lw / 2))
            var ly = ex.kind === "max" ? yAt(ex.value) - 6 : yAt(ex.value) + 13
            ctx.fillStyle = Model.tempColor(ex.value, view.tempUnit)
            ctx.fillText(label, lx, ly)
          }

          // Hour axis, every three hours.
          ctx.font = "9px " + view.fontFamily
          ctx.fillStyle = view.muted
          for (var a = 0; a < n; a += 1) {
            var ah = Number(String(hours[a].time || "").slice(11, 13))
            if (a !== 0 && (ah % 3 !== 0 || a < 2)) continue
            var atext = a === 0 ? "now" : Model.hourLabel(hours[a].time)
            ctx.fillText(atext, xAt(a) - ctx.measureText(atext).width / 2, axisY)
          }

          // UV row: label the peak of each remarkable (>= 6) stretch.
          ctx.font = "bold 9px " + view.fontFamily
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
            ctx.fillStyle = Model.tempColor(88, "°F")
            ctx.fillText(utext, Math.max(2, xAt(peakI) - ctx.measureText(utext).width / 2), annoY1)
            u = v
          }

          // Wind row: arrow and speed where it blows hard enough to matter,
          // at most one label per three hours.
          ctx.font = "9px " + view.fontFamily
          ctx.fillStyle = view.muted
          for (var w2 = 0; w2 < n; w2 += 3) {
            var ws = Model.num(hours[w2].wind_speed, 0)
            if (!Model.windSignificant(ws, view.windUnit)) continue
            var wtext = Model.windArrow(hours[w2].wind_direction) + Math.round(ws)
            ctx.fillText(wtext, Math.max(2, xAt(w2) - ctx.measureText(wtext).width / 2), annoY2)
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

    // ---- Daily rows: day, glyph, low, range bar, high, and the TUI's
    //      right-hand annotations — rain chance and amount when present,
    //      wind when it matters.
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
            font.pixelSize: Style.font.body
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
            font.pixelSize: Style.font.body
          }

          Text {
            id: dayLow
            anchors.verticalCenter: parent.verticalCenter
            x: dayIcon.x + dayIcon.width
            width: Style.space(30)
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
              // endpoint colors straight across RGB space.
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
            x: annoCol.x - width - Style.space(4)
            width: Style.space(30)
            horizontalAlignment: Text.AlignRight
            text: Model.roundTemp(modelData.high)
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }

          Row {
            id: annoCol
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - Style.space(64)
            spacing: Style.space(6)

            Text {
              text: dayRow.precipLabel
              visible: text !== ""
              color: {
                var pc = Model.precipColorFor(dayRow.modelData.weather_code, view.foreground)
                return Qt.rgba(pc.r, pc.g, pc.b, 1)
              }
              font.family: view.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              text: dayRow.windLabel
              visible: text !== ""
              color: view.muted
              font.family: view.fontFamily
              font.pixelSize: Style.font.caption
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

    PanelSeparator { foreground: view.foreground }

    PanelSectionHeader {
      text: "LOCATION"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    // ---- Location picker, power-profile style: recents as bordered
    //      cells, auto-location beside them, a search field to add more.
    Grid {
      id: locationGrid
      width: parent.width
      columns: 2
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(8)

      readonly property real cellWidth: (width - columnSpacing) / 2

      Repeater {
        model: view.recentLocations

        Button {
          required property var modelData
          width: locationGrid.cellWidth
          text: String(modelData.label || "").split(",").slice(0, 2).join(",")
          fontSize: Style.font.bodySmall
          bordered: true
          leftAlign: true
          selected: view.payload && view.payload.location === modelData.label
          foreground: view.foreground
          fontFamily: view.fontFamily
          onClicked: view.applyLocation(modelData)
        }
      }

      Button {
        width: locationGrid.cellWidth
        iconText: "󰆤"
        text: "Auto (IP)"
        fontSize: Style.font.bodySmall
        bordered: true
        leftAlign: true
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.applyAutoLocation()
      }
    }

    TextField {
      id: searchField
      width: parent.width
      foreground: view.foreground
      placeholderText: "Add location… (Enter to search)"
      onAccepted: view.searchLocations(text)
    }

    Text {
      visible: view.locBusy
      text: "Looking…"
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }

    Column {
      visible: view.searchResults.length > 0
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: view.searchResults

        Button {
          required property var modelData
          width: column.width
          text: modelData.label
          fontSize: Style.font.bodySmall
          leftAlign: true
          foreground: view.foreground
          fontFamily: view.fontFamily
          onClicked: view.applyLocation(modelData)
        }
      }
    }

    Text {
      bottomPadding: Style.space(2)
      text: view.payload ? (view.payload.location || "") : ""
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
