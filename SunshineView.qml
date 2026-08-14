import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Sunshine face: countdown to the next sunrise/sunset over a stylized
// solar arc — the day as a sine wave over a horizon line, sun dot at now —
// with day length and its drift underneath. Fed by `linecast sunshine
// --json`.
Item {
  id: view

  property var bar
  property bool shown: false

  readonly property int panelWidth: Style.space(340)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)
  // The sun keeps the ramp's warm anchor rather than the theme accent, so
  // the arc reads "sun" in any theme.
  readonly property color sunColor: Model.tempColor(78, "°F")

  readonly property var payload: feed.payload

  // Ticks while shown so the countdown and sun position stay honest.
  property double nowMs: Date.now()

  readonly property var nextEvent: payload ? payload.next_event : null
  readonly property real riseMs: payload ? Model.parseIsoLocal(payload.sunrise) : NaN
  readonly property real setMs: payload ? Model.parseIsoLocal(payload.sunset) : NaN
  readonly property real tomorrowRiseMs: payload ? Model.parseIsoLocal(payload.tomorrow_sunrise) : NaN

  function refresh() { feed.refresh() }

  onShownChanged: if (shown) { view.nowMs = Date.now(); feed.refreshIfStale() }

  implicitHeight: column.implicitHeight

  JsonFeed {
    id: feed
    command: "linecast sunshine --json"
    staleAfterMs: 30 * 60 * 1000
    onPayloadChanged: arc.requestPaint()
  }

  Timer {
    interval: 30 * 1000
    running: view.shown
    repeat: true
    onTriggered: {
      view.nowMs = Date.now()
      arc.requestPaint()
    }
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
      text: feed.fetching ? "Reading the sky…" : "No solar data — is linecast ≥ 1.9 installed?"
      wrapMode: Text.WordWrap
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }

    // ---- Hero: the next event and how far away it is.
    Column {
      visible: !!view.nextEvent
      width: parent.width
      spacing: Style.space(2)

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(14)

        Text {
          anchors.baseline: heroCountdown.baseline
          text: view.nextEvent && view.nextEvent.kind === "sunrise" ? "󰖜" : "󰖛"
          color: view.sunColor
          font.family: view.fontFamily
          font.pixelSize: 38
        }

        Text {
          id: heroCountdown
          text: {
            if (!view.nextEvent) return ""
            var secs = Model.secondsUntil(view.nextEvent.time, view.nowMs)
            return isNaN(secs) ? "" : Model.fmtDuration(Math.max(0, secs))
          }
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: 44
          font.bold: true
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: {
          if (!view.nextEvent) return ""
          var kind = view.nextEvent.kind === "sunrise" ? "until sunrise" : "until sunset"
          return kind + " at " + Model.clockLabel(view.nextEvent.time)
        }
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: view.payload ? (view.payload.location || "") : ""
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // ---- The arc: today from midnight to midnight, elevation as a sine
    //      bulge between rise and set and a shallower dip at night, drawn
    //      over the horizon line. A dot marks now.
    Canvas {
      id: arc
      visible: !!(view.payload && !isNaN(view.riseMs) && !isNaN(view.setMs))
      width: parent.width
      height: Style.space(96)

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!view.payload || isNaN(view.riseMs) || isNaN(view.setMs)) return

        var w = width
        var h = height
        var horizonY = h * 0.62
        var dayAmp = h * 0.44
        var nightAmp = h * 0.26

        var rise = view.riseMs
        var set = view.setMs
        var dayStart = new Date(rise)
        dayStart.setHours(0, 0, 0, 0)
        var t0 = dayStart.getTime()
        var t1 = t0 + 24 * 3600 * 1000

        function elev(t) {
          if (t >= rise && t <= set)
            return Math.sin(Math.PI * (t - rise) / (set - rise)) * dayAmp
          // Night halves: dip below the horizon, mirrored around the
          // nearest rise/set so the curve stays continuous.
          if (t < rise)
            return -Math.sin(Math.PI * (rise - t) / (rise - t0 + (t1 - set))) * nightAmp
          return -Math.sin(Math.PI * (t - set) / (rise - t0 + (t1 - set))) * nightAmp
        }

        function xFor(t) { return (t - t0) / (t1 - t0) * w }
        function yFor(t) { return horizonY - elev(t) }

        var fgDim = Qt.rgba(view.muted.r, view.muted.g, view.muted.b, 0.9)

        // Horizon.
        ctx.strokeStyle = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.18)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(0, horizonY)
        ctx.lineTo(w, horizonY)
        ctx.stroke()

        // The curve, night muted and day warm; drawn in small steps so the
        // two styles can hand off exactly at rise and set.
        function strokeSpan(from, to, color, lw) {
          ctx.strokeStyle = color
          ctx.lineWidth = lw
          ctx.beginPath()
          var steps = 60
          for (var i = 0; i <= steps; i++) {
            var t = from + (to - from) * i / steps
            var x = xFor(t)
            var y = yFor(t)
            if (i === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
          }
          ctx.stroke()
        }

        strokeSpan(t0, rise, fgDim, 1.5)
        strokeSpan(set, t1, fgDim, 1.5)
        strokeSpan(rise, set, view.sunColor, 2.5)

        // Now.
        var now = view.nowMs
        if (now >= t0 && now <= t1) {
          var isUp = now >= rise && now <= set
          ctx.fillStyle = isUp ? view.sunColor : view.foreground
          ctx.beginPath()
          ctx.arc(xFor(now), yFor(now), isUp ? 5 : 3.5, 0, 2 * Math.PI)
          ctx.fill()
          if (isUp) {
            ctx.strokeStyle = Qt.rgba(view.sunColor.r, view.sunColor.g, view.sunColor.b, 0.35)
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.arc(xFor(now), yFor(now), 8, 0, 2 * Math.PI)
            ctx.stroke()
          }
        }
      }
    }

    // Rise and set times sit under their ends of the arc.
    Item {
      visible: arc.visible
      width: parent.width
      height: riseLabel.implicitHeight

      Text {
        id: riseLabel
        x: Math.max(0, Math.min(parent.width - width,
          (view.riseMs - startOfDay()) / 86400000 * parent.width - width / 2))
        text: "󰖜 " + Model.clockLabel(view.payload ? view.payload.sunrise : "")
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption

        function startOfDay() {
          var d = new Date(view.riseMs)
          d.setHours(0, 0, 0, 0)
          return d.getTime()
        }
      }

      Text {
        x: Math.max(0, Math.min(parent.width - width,
          (view.setMs - riseLabel.startOfDay()) / 86400000 * parent.width - width / 2))
        text: "󰖛 " + Model.clockLabel(view.payload ? view.payload.sunset : "")
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    PanelSeparator { visible: !!view.payload; foreground: view.foreground }

    // ---- Footer: day length and its drift, tomorrow's sunrise, solar noon.
    Row {
      visible: !!view.payload
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(20)
      bottomPadding: Style.space(4)

      GlanceStat {
        glyph: "󰖨"
        value: view.payload && view.payload.day_length_seconds !== null
          ? Model.fmtDuration(view.payload.day_length_seconds)
            + (Model.fmtDeltaDuration(view.payload.day_length_delta_seconds) !== ""
               ? " (" + Model.fmtDeltaDuration(view.payload.day_length_delta_seconds) + ")" : "")
          : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }

      GlanceStat {
        glyph: "󰇥"
        value: view.payload ? Model.clockLabel(view.payload.solar_noon) : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }

      GlanceStat {
        glyph: "󰖜"
        value: view.payload && view.payload.tomorrow_sunrise
          ? "tmrw " + Model.clockLabel(view.payload.tomorrow_sunrise) : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }
    }
  }
}
