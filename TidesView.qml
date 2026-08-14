import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Tides face: countdown to the next high/low over the tide curve — past
// water dimmed, future in accent, a dot at now, markers at the extremes —
// with the upcoming events beneath. Fed by `linecast tides --json`.
Item {
  id: view

  property var bar
  property bool shown: false
  property int locationEpoch: 0

  readonly property int panelWidth: Style.space(360)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color waterColor: Color.accent

  readonly property var payload: feed.payload
  readonly property var events: payload && payload.events ? payload.events : []
  readonly property var series: payload && payload.series ? payload.series : []
  readonly property string heightUnit: payload && payload.units ? (payload.units.height || "") : ""
  readonly property var nextEvent: events.length > 0 ? events[0] : null

  property double nowMs: Date.now()

  function refresh() { feed.refresh() }

  function fmtHeight(v) {
    var n = Model.num(v, NaN)
    if (isNaN(n)) return ""
    return (Math.round(n * 10) / 10) + (view.heightUnit === "ft" ? "′" : " " + view.heightUnit)
  }

  onShownChanged: if (shown) { view.nowMs = Date.now(); feed.refreshIfStale() }
  onLocationEpochChanged: {
    feed.payload = null
    feed.fetchedAtMs = 0
    if (shown) feed.refresh()
  }

  implicitHeight: column.implicitHeight

  JsonFeed {
    id: feed
    command: "linecast tides --json"
    staleAfterMs: 30 * 60 * 1000
    onPayloadChanged: chart.requestPaint()
  }

  Timer {
    interval: 60 * 1000
    running: view.shown
    repeat: true
    onTriggered: {
      view.nowMs = Date.now()
      chart.requestPaint()
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    Text {
      visible: !view.payload || !view.payload.station
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      topPadding: Style.space(24)
      bottomPadding: Style.space(24)
      text: feed.fetching ? "Reading the water…"
        : (view.payload ? "No tide station in range here."
                        : "No tide data — is linecast ≥ 1.9 installed?")
      wrapMode: Text.WordWrap
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }

    // ---- Header, battery-panel style: the next turn as the status line,
    //      the countdown as the reading.
    FaceHeader {
      visible: !!view.nextEvent
      icon: view.nextEvent && view.nextEvent.kind === "high" ? "▲" : "▼"
      title: "Tides"
      subtitle: {
        if (!view.nextEvent) return ""
        var kind = view.nextEvent.kind === "high" ? "high" : "low"
        var line = "until " + kind + " at " + Model.clockLabel(view.nextEvent.time)
        var h = view.fmtHeight(view.nextEvent.height)
        if (h !== "") line += " · " + h
        return line
      }
      bigValue: {
        if (!view.nextEvent) return ""
        var secs = Model.secondsUntil(view.nextEvent.time, view.nowMs)
        return isNaN(secs) ? "" : Model.fmtDuration(Math.max(0, secs))
      }
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    // ---- The curve: series from a few hours back to tomorrow, extremes
    //      marked, now dotted.
    Canvas {
      id: chart
      visible: view.series.length > 2
      width: parent.width
      height: Style.space(104)

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var pts = view.series
        if (!pts || pts.length < 3) return

        var padTop = 14
        var padBottom = 6
        var t0 = Model.parseIsoLocal(pts[0].time)
        var t1 = Model.parseIsoLocal(pts[pts.length - 1].time)
        if (isNaN(t0) || isNaN(t1) || t1 <= t0) return

        var min = NaN, max = NaN
        for (var i = 0; i < pts.length; i++) {
          var h = Model.num(pts[i].height, NaN)
          if (isNaN(h)) continue
          if (isNaN(min) || h < min) min = h
          if (isNaN(max) || h > max) max = h
        }
        if (isNaN(min) || isNaN(max) || max - min <= 0) return

        function xFor(t) { return (t - t0) / (t1 - t0) * width }
        function yFor(h) {
          return padTop + (1 - (h - min) / (max - min)) * (height - padTop - padBottom)
        }

        var now = view.nowMs
        var nowX = Math.max(0, Math.min(width, xFor(now)))

        // Filled water area, then the line — split at now so the past
        // reads as gone-by.
        function drawSpan(fromX, toX, lineColor, fillAlpha) {
          if (toX <= fromX) return
          ctx.save()
          ctx.beginPath()
          ctx.rect(fromX, 0, toX - fromX, height)
          ctx.clip()

          ctx.beginPath()
          for (var i = 0; i < pts.length; i++) {
            var x = xFor(Model.parseIsoLocal(pts[i].time))
            var y = yFor(Model.num(pts[i].height, min))
            if (i === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
          }
          ctx.strokeStyle = lineColor
          ctx.lineWidth = 2
          ctx.stroke()
          ctx.lineTo(width, height)
          ctx.lineTo(0, height)
          ctx.closePath()
          ctx.fillStyle = Qt.rgba(view.waterColor.r, view.waterColor.g, view.waterColor.b, fillAlpha)
          ctx.fill()
          ctx.restore()
        }

        var dimLine = Qt.rgba(view.muted.r, view.muted.g, view.muted.b, 0.9)
        drawSpan(0, nowX, dimLine, 0.08)
        drawSpan(nowX, width, view.waterColor, 0.16)

        // Extremes get a dot and a time label.
        ctx.font = "10px " + view.fontFamily
        for (var e = 0; e < view.events.length; e++) {
          var ev = view.events[e]
          var et = Model.parseIsoLocal(ev.time)
          if (isNaN(et) || et < t0 || et > t1) continue
          var ex = xFor(et)
          var ey = yFor(Model.num(ev.height, min))
          ctx.fillStyle = view.foreground
          ctx.beginPath()
          ctx.arc(ex, ey, 2.5, 0, 2 * Math.PI)
          ctx.fill()
          var label = Model.clockLabel(ev.time)
          var lw = ctx.measureText(label).width
          ctx.fillStyle = view.muted
          ctx.fillText(label, Math.max(2, Math.min(width - lw - 2, ex - lw / 2)),
                       ev.kind === "high" ? Math.max(10, ey - 8) : Math.min(height - 3, ey + 16))
        }

        // Now.
        if (now >= t0 && now <= t1) {
          var curH = NaN
          for (var j = 1; j < pts.length; j++) {
            var ta = Model.parseIsoLocal(pts[j - 1].time)
            var tb = Model.parseIsoLocal(pts[j].time)
            if (now >= ta && now <= tb) {
              var ha = Model.num(pts[j - 1].height, NaN)
              var hb = Model.num(pts[j].height, NaN)
              curH = ha + (hb - ha) * (now - ta) / (tb - ta)
              break
            }
          }
          if (!isNaN(curH)) {
            ctx.fillStyle = view.foreground
            ctx.beginPath()
            ctx.arc(nowX, yFor(curH), 4, 0, 2 * Math.PI)
            ctx.fill()
          }
        }
      }
    }

    PanelSeparator { visible: view.events.length > 0; foreground: view.foreground }

    // ---- Upcoming turns, in order.
    Row {
      visible: view.events.length > 0
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(22)

      Repeater {
        model: view.events.slice(0, 4)

        Column {
          required property var modelData
          spacing: 0

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (modelData.kind === "high" ? "▲ " : "▼ ") + Model.clockLabel(modelData.time)
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (modelData.kind === "high" ? "high" : "low")
              + (view.fmtHeight(modelData.height) !== "" ? " · " + view.fmtHeight(modelData.height) : "")
            color: view.muted
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    PanelSeparator { visible: !!(view.payload && view.payload.station); foreground: view.foreground }

    // ---- Info grid: which water this is, and where it stands.
    Row {
      visible: !!(view.payload && view.payload.station)
      width: parent.width
      spacing: Style.space(16)

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(4)

        InfoPair {
          label: "Station"
          value: view.payload ? (view.payload.station || "") : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(4)

        InfoPair {
          label: "Now"
          value: view.payload ? view.fmtHeight(view.payload.now_height) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }
    }
  }
}
