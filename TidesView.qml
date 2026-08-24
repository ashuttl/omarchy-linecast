import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Tides face: the station leads, with the water's height right now as
// the reading and the next turn in the status line, over the TUI's tide
// chart — a dotted curve through the day, the past dimmed, a line at now
// tagged with the time and height, the turns labeled at their peaks and
// troughs, hours along the bottom and heights up the side — with the
// upcoming turns listed beneath. Fed by `linecast tides --json`.
Item {
  id: view

  property var bar
  property bool shown: false
  property int locationEpoch: 0

  readonly property int panelWidth: Style.space(380)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color waterColor: Color.accent

  readonly property var payload: feed.payload
  readonly property var events: payload && payload.events ? payload.events : []
  readonly property var series: payload && payload.series ? payload.series : []
  readonly property string heightUnit: payload && payload.units ? (payload.units.height || "") : ""
  readonly property var nextEvent: events.length > 0 ? events[0] : null
  readonly property bool rising: !!nextEvent && nextEvent.kind === "high"

  property double nowMs: Date.now()

  // The chart's time span and plot width, shared by the painter and the
  // hover math.
  readonly property real t0: series.length > 0 ? Model.parseIsoLocal(series[0].time) : NaN
  readonly property real t1: series.length > 0 ? Model.parseIsoLocal(series[series.length - 1].time) : NaN
  readonly property int chartPadRight: 30

  // Hovering the curve reads the water at that moment. NaN means none.
  property real hoverMs: NaN
  readonly property bool hovering: !isNaN(hoverMs)
  readonly property real hoverHeight: hovering ? heightAt(hoverMs) : NaN
  readonly property bool hoverRising: hovering && heightAt(hoverMs + 15 * 60 * 1000) > hoverHeight
  onHoverMsChanged: chart.requestPaint()

  function refresh() { feed.refresh() }

  function fmtHeight(v) {
    var n = Model.num(v, NaN)
    if (isNaN(n)) return ""
    return (Math.round(n * 10) / 10) + (view.heightUnit === "ft" ? "′" : " " + view.heightUnit)
  }

  // The water right now, read off the curve so it moves between fetches.
  function heightAt(ms) {
    var pts = view.series
    for (var j = 1; j < pts.length; j++) {
      var ta = Model.parseIsoLocal(pts[j - 1].time)
      var tb = Model.parseIsoLocal(pts[j].time)
      if (ms >= ta && ms <= tb) {
        var ha = Model.num(pts[j - 1].height, NaN)
        var hb = Model.num(pts[j].height, NaN)
        return ha + (hb - ha) * (ms - ta) / (tb - ta)
      }
    }
    return payload ? Model.num(payload.now_height, NaN) : NaN
  }

  onShownChanged: if (shown) { view.nowMs = Date.now(); feed.refreshIfStale() }
  // The canvas reads foreground, accent, and the font imperatively in
  // onPaint; a theme swap needs an explicit repaint.
  onForegroundChanged: chart.requestPaint()
  onWaterColorChanged: chart.requestPaint()
  onFontFamilyChanged: chart.requestPaint()
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

    // ---- Header: the station leads, the water's height now is the
    //      reading, and the next turn is the status line.
    FaceHeader {
      visible: !!view.nextEvent
      icon: view.rising ? "▲" : "▼"
      title: view.payload && view.payload.station ? view.payload.station : "Tides"
      subtitle: {
        if (!view.nextEvent) return ""
        var line = (view.rising ? "rising · high " : "falling · low ") + Model.clockLabel(view.nextEvent.time)
        var secs = Model.secondsUntil(view.nextEvent.time, view.nowMs)
        if (!isNaN(secs) && secs > 0) line += " · in " + Model.fmtDuration(secs)
        return line
      }
      bigValue: view.fmtHeight(view.heightAt(view.nowMs))
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    // ---- The chart.
    Canvas {
      id: chart
      visible: view.series.length > 2
      width: parent.width
      height: Style.space(170)

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var pts = view.series
        if (!pts || pts.length < 3) return

        var padTop = 28
        var padBottom = 18
        var padRight = view.chartPadRight
        var plotW = width - padRight
        var t0 = Model.parseIsoLocal(pts[0].time)
        var t1 = Model.parseIsoLocal(pts[pts.length - 1].time)
        if (isNaN(t0) || isNaN(t1) || t1 <= t0) return

        var min = NaN, max = NaN
        for (var i = 0; i < pts.length; i++) {
          var hh = Model.num(pts[i].height, NaN)
          if (isNaN(hh)) continue
          if (isNaN(min) || hh < min) min = hh
          if (isNaN(max) || hh > max) max = hh
        }
        if (isNaN(min) || isNaN(max) || max - min <= 0) return
        // Room under the troughs and over the peaks for their labels.
        var span = max - min
        var lo = min - span * 0.18
        var hi = max + span * 0.30

        function xFor(t) { return (t - t0) / (t1 - t0) * plotW }
        function yFor(h) { return padTop + (1 - (h - lo) / (hi - lo)) * (height - padTop - padBottom) }

        var now = view.nowMs
        var nowX = Math.max(0, Math.min(plotW, xFor(now)))
        var axisY = height - padBottom

        var fg = view.foreground
        var dim = Qt.rgba(view.muted.r, view.muted.g, view.muted.b, 0.85)
        var caption = Style.font.caption + "px " + view.fontFamily

        // A wash of water under the curve, the past fainter.
        function fillSpan(fromX, toX, alpha) {
          if (toX <= fromX) return
          ctx.save()
          ctx.beginPath()
          ctx.rect(fromX, 0, toX - fromX, axisY)
          ctx.clip()
          ctx.beginPath()
          for (var i = 0; i < pts.length; i++) {
            var x = xFor(Model.parseIsoLocal(pts[i].time))
            var y = yFor(Model.num(pts[i].height, min))
            if (i === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
          }
          ctx.lineTo(plotW, axisY)
          ctx.lineTo(0, axisY)
          ctx.closePath()
          ctx.fillStyle = Qt.rgba(view.waterColor.r, view.waterColor.g, view.waterColor.b, alpha)
          ctx.fill()
          ctx.restore()
        }
        fillSpan(0, nowX, 0.05)
        fillSpan(nowX, plotW, 0.13)

        // The curve, dotted like the braille one; the past dimmed.
        function dottedSpan(fromX, toX, color) {
          if (toX <= fromX) return
          ctx.save()
          ctx.beginPath()
          ctx.rect(fromX, 0, toX - fromX, axisY)
          ctx.clip()
          ctx.strokeStyle = color
          ctx.lineWidth = 2
          ctx.lineCap = "round"
          ctx.setLineDash([0.5, 4])
          ctx.beginPath()
          for (var i = 0; i < pts.length; i++) {
            var x = xFor(Model.parseIsoLocal(pts[i].time))
            var y = yFor(Model.num(pts[i].height, min))
            if (i === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
          }
          ctx.stroke()
          ctx.setLineDash([])
          ctx.restore()
        }
        dottedSpan(0, nowX, dim)
        dottedSpan(nowX, plotW, fg)

        // Hours along the bottom.
        ctx.font = caption
        ctx.fillStyle = dim
        ctx.strokeStyle = dim
        ctx.lineWidth = 1
        var ticks = Model.hourTicks(t0, t1, 3)
        for (var k = 0; k < ticks.length; k++) {
          var tx = Math.round(xFor(ticks[k].ms)) + 0.5
          ctx.beginPath()
          ctx.moveTo(tx, axisY)
          ctx.lineTo(tx, axisY + 4)
          ctx.stroke()
          ctx.fillText(ticks[k].label, tx + 3, axisY + 13)
        }

        // Heights up the right side.
        var stepH = Model.niceStep(max - min)
        ctx.textAlign = "right"
        for (var lv = Math.ceil(lo / stepH) * stepH; lv <= hi + 1e-9; lv += stepH) {
          var ly = yFor(lv)
          if (ly < padTop - 2 || ly > axisY) continue
          ctx.fillStyle = dim
          ctx.fillText(view.fmtHeight(lv), width, ly + 4)
        }
        ctx.textAlign = "left"

        // The turns: highs labeled above (time, then height), lows below
        // (height, then time), as the TUI does.
        for (var e = 0; e < view.events.length; e++) {
          var ev = view.events[e]
          var et = Model.parseIsoLocal(ev.time)
          if (isNaN(et) || et < t0 || et > t1) continue
          var ex = xFor(et)
          var ey = yFor(Model.num(ev.height, min))
          var past = et < now
          ctx.fillStyle = past ? dim : fg
          ctx.beginPath()
          ctx.arc(ex, ey, 2.5, 0, 2 * Math.PI)
          ctx.fill()
          var time = Model.clockLabel(ev.time)
          var hgt = view.fmtHeight(ev.height)
          var lw = Math.max(ctx.measureText(time).width, ctx.measureText(hgt).width)
          var lx = Math.max(2, Math.min(plotW - lw - 2, ex - lw / 2))
          if (ev.kind === "high") {
            ctx.fillStyle = dim
            ctx.fillText(time, lx, ey - 18)
            ctx.fillStyle = past ? dim : fg
            ctx.fillText(hgt, lx, ey - 7)
          } else {
            ctx.fillStyle = past ? dim : fg
            ctx.fillText(hgt, lx, ey + 14)
            ctx.fillStyle = dim
            ctx.fillText(time, lx, ey + 25)
          }
        }

        // The hovered moment: a faint line and a dot on the water.
        if (view.hovering) {
          var hx = Math.round(xFor(view.hoverMs)) + 0.5
          ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.3)
          ctx.lineWidth = 1
          ctx.beginPath()
          ctx.moveTo(hx, padTop - 4)
          ctx.lineTo(hx, axisY)
          ctx.stroke()
          if (!isNaN(view.hoverHeight)) {
            ctx.fillStyle = fg
            ctx.beginPath()
            ctx.arc(hx, yFor(view.hoverHeight), 3, 0, 2 * Math.PI)
            ctx.fill()
          }
        }

        // Now: a line the height of the chart, tagged with the time and
        // the water at the top.
        if (now >= t0 && now <= t1) {
          ctx.strokeStyle = view.waterColor
          ctx.lineWidth = 1.5
          ctx.beginPath()
          ctx.moveTo(Math.round(nowX) + 0.5, 2)
          ctx.lineTo(Math.round(nowX) + 0.5, axisY)
          ctx.stroke()

          var curH = view.heightAt(now)
          if (!isNaN(curH)) {
            ctx.fillStyle = fg
            ctx.beginPath()
            ctx.arc(nowX, yFor(curH), 3.5, 0, 2 * Math.PI)
            ctx.fill()

            var tagTime = Model.clockLabelMs(now)
            var tagH = view.fmtHeight(curH)
            var tagW = Math.max(ctx.measureText(tagTime).width, ctx.measureText(tagH).width)
            var onRight = nowX + 6 + tagW <= plotW
            var tagX = onRight ? nowX + 6 : nowX - 6 - tagW
            ctx.fillStyle = fg
            ctx.fillText(tagTime, tagX, 11)
            ctx.fillText(tagH, tagX, 22)
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
          if (isNaN(view.t0) || isNaN(view.t1)) return
          var plotW = width - view.chartPadRight
          var f = Math.max(0, Math.min(1, mouse.x / plotW))
          view.hoverMs = view.t0 + f * (view.t1 - view.t0)
        }
        onExited: view.hoverMs = NaN
      }

      // The chip, weather-chart style: time, height, which way the water
      // is going.
      Rectangle {
        visible: view.hovering
        x: {
          var plotW = parent.width - view.chartPadRight
          var hx = (view.hoverMs - view.t0) / (view.t1 - view.t0) * plotW
          return hx < plotW / 2 ? Math.min(plotW - width - 4, hx + Style.space(14))
                                : Math.max(4, hx - width - Style.space(14))
        }
        y: Style.space(30)
        width: hoverColumn.implicitWidth + Style.space(16)
        height: hoverColumn.implicitHeight + Style.space(12)
        color: Color.tooltip.background
        border.color: Color.tooltip.border
        border.width: 1

        Column {
          id: hoverColumn
          anchors.centerIn: parent
          spacing: Style.space(1)

          Text {
            text: {
              var tag = Model.dayTag(new Date(view.hoverMs).toISOString(), view.nowMs)
              var d = new Date(view.hoverMs)
              var local = d.getFullYear() + "-" + (d.getMonth() < 9 ? "0" : "") + (d.getMonth() + 1) + "-" + (d.getDate() < 10 ? "0" : "") + d.getDate() + "T00:00"
              tag = Model.dayTag(local, view.nowMs)
              return Model.clockLabelMs(view.hoverMs) + (tag !== "" ? " " + tag : "")
            }
            color: Color.tooltip.text
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            text: view.fmtHeight(view.hoverHeight)
            color: Color.tooltip.text
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            text: view.hovering ? (view.hoverRising ? "rising" : "falling") : ""
            color: Qt.darker(Color.tooltip.text, 1.3)
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    PanelSeparator { visible: view.events.length > 0; foreground: view.foreground }

    // ---- The turns to come, in order.
    Column {
      visible: view.events.length > 0
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: view.events.slice(0, 4)

        Item {
          required property var modelData
          width: parent.width
          height: kindText.implicitHeight

          Text {
            id: kindText
            text: (modelData.kind === "high" ? "▲ High" : "▼ Low")
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Model.clockLabel(modelData.time) + (Model.dayTag(modelData.time, view.nowMs) !== "" ? " " + Model.dayTag(modelData.time, view.nowMs) : "")
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.right: parent.right
            text: view.fmtHeight(modelData.height)
            color: view.muted
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
