import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Sunshine face: countdown to the next sunrise/sunset over the TUI's
// solar arc — the day as a sine wave over a horizon line, the sky above
// it colored for the sun's elevation right now, warm near the sun and
// cool away from it, the sun glowing at its position — with sunrise, day
// length, and sunset beneath. Fed by `linecast sunshine --json`.
Item {
  id: view

  property var bar
  property bool shown: false
  property int locationEpoch: 0
  // ThemePalette from the panel; null falls back to fixed colors.
  property var palette: null

  readonly property int panelWidth: Style.space(340)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property var themeColors: palette ? palette.colors : null
  readonly property var sky: Model.buildSkyStops(themeColors, Color.background)

  readonly property var payload: feed.payload

  // Ticks while shown so the countdown and sun position stay honest.
  property double nowMs: Date.now()

  readonly property var nextEvent: payload ? payload.next_event : null
  readonly property real riseMs: payload ? Model.parseIsoLocal(payload.sunrise) : NaN
  readonly property real setMs: payload ? Model.parseIsoLocal(payload.sunset) : NaN
  readonly property real elevNow: payload ? Model.num(payload.elevation_deg, NaN) : NaN
  readonly property bool sunUp: !isNaN(elevNow) && elevNow > -0.833

  // Scrubbing: hovering the arc moves the sun and repaints the sky for
  // that moment. NaN means now.
  property real scrubMs: NaN
  readonly property bool scrubbing: !isNaN(scrubMs)
  readonly property real focusMs: scrubbing ? scrubMs : nowMs
  readonly property real focusElev: scrubbing ? elevationAt(scrubMs) : elevNow
  onScrubMsChanged: arc.requestPaint()

  // ---- A solar model for any moment of the day. Latitude isn't in the
  //      payload, so it's recovered from the day's length and the date
  //      (day length at a given declination pins the latitude, sign
  //      included), and elevation follows from the hour angle around
  //      solar noon.
  readonly property real solarNoonMs: payload ? Model.parseIsoLocal(payload.solar_noon) : NaN
  readonly property real declinationDeg: {
    if (isNaN(view.solarNoonMs)) return 0
    var d = new Date(view.solarNoonMs)
    var start = new Date(d.getFullYear(), 0, 0)
    var doy = Math.floor((d.getTime() - start.getTime()) / 86400000)
    return 23.44 * Math.sin(2 * Math.PI * (doy - 81) / 365)
  }
  readonly property real latitudeDeg: {
    if (!view.payload || view.payload.day_length_seconds === null) return 45
    var hours = Model.num(view.payload.day_length_seconds, NaN) / 3600
    if (isNaN(hours)) return 45
    var rad = Math.PI / 180
    var dec = view.declinationDeg * rad
    var h0 = Math.sin(-0.833 * rad)
    if (Math.abs(view.declinationDeg) < 0.4 || Math.abs(hours - 12) < 0.05) return 45
    // Day longer than 12h under a northern-summer sun means north, and
    // so on; then bisect |lat| until the modeled day matches.
    var north = (hours > 12) === (view.declinationDeg > 0)
    function dayLength(latAbs) {
      var lat = (north ? latAbs : -latAbs) * rad
      var c = (h0 - Math.sin(lat) * Math.sin(dec)) / (Math.cos(lat) * Math.cos(dec))
      if (c <= -1) return 24
      if (c >= 1) return 0
      return 2 * Math.acos(c) / rad / 15
    }
    var lo = 0, hi = 89.5
    var grows = dayLength(hi) > dayLength(lo)
    for (var i = 0; i < 40; i++) {
      var mid = (lo + hi) / 2
      if ((dayLength(mid) < hours) === grows) lo = mid
      else hi = mid
    }
    var latAbs = (lo + hi) / 2
    return north ? latAbs : -latAbs
  }
  function elevationAt(ms) {
    if (isNaN(view.solarNoonMs)) return NaN
    var rad = Math.PI / 180
    var lat = view.latitudeDeg * rad
    var dec = view.declinationDeg * rad
    var hourAngle = 15 * (ms - view.solarNoonMs) / 3600000 * rad
    var sinAlt = Math.sin(lat) * Math.sin(dec) + Math.cos(lat) * Math.cos(dec) * Math.cos(hourAngle)
    return Math.asin(Math.max(-1, Math.min(1, sinAlt))) / rad
  }
  function twilightWord(elev) {
    if (isNaN(elev)) return ""
    if (elev > -0.833) return "sun up"
    if (elev > -6) return "civil twilight"
    if (elev > -12) return "nautical twilight"
    if (elev > -18) return "astronomical twilight"
    return "night"
  }

  function refresh() { feed.refresh() }

  function startOfDay() {
    var d = new Date(isNaN(view.riseMs) ? view.nowMs : view.riseMs)
    d.setHours(0, 0, 0, 0)
    return d.getTime()
  }

  onShownChanged: if (shown) { view.nowMs = Date.now(); feed.refreshIfStale() }
  // The canvas reads its colors imperatively in onPaint; a theme swap
  // needs an explicit repaint.
  onForegroundChanged: arc.requestPaint()
  onSkyChanged: arc.requestPaint()
  onLocationEpochChanged: {
    feed.payload = null
    feed.fetchedAtMs = 0
    if (shown) feed.refresh()
  }

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

    // ---- Header, battery-panel style: the next event as the status
    //      line, the countdown as the reading.
    FaceHeader {
      visible: !!view.nextEvent
      icon: view.nextEvent && view.nextEvent.kind === "sunrise" ? "󰖜" : "󰖛"
      title: "Sunshine"
      subtitle: view.nextEvent
        ? ("until " + view.nextEvent.kind + " at " + Model.clockLabel(view.nextEvent.time))
        : ""
      bigValue: {
        if (!view.nextEvent) return ""
        var secs = Model.secondsUntil(view.nextEvent.time, view.nowMs)
        return isNaN(secs) ? "" : Model.fmtDuration(Math.max(0, secs))
      }
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    // ---- The arc: today from midnight to midnight, elevation as a sine
    //      bulge between rise and set and a shallower dip at night, under
    //      a sky painted for the sun's elevation right now.
    Canvas {
      id: arc
      visible: !!(view.payload && !isNaN(view.riseMs) && !isNaN(view.setMs))
      width: parent.width
      height: Style.space(132)

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!view.payload || isNaN(view.riseMs) || isNaN(view.setMs)) return

        var w = width
        var h = height
        var horizonY = Math.round(h * 0.64)
        var dayAmp = h * 0.52
        var nightAmp = h * 0.26

        var rise = view.riseMs
        var set = view.setMs
        var t0 = view.startOfDay()
        var t1 = t0 + 24 * 3600 * 1000
        var now = view.nowMs

        function elev(t) {
          if (t >= rise && t <= set)
            return Math.sin(Math.PI * (t - rise) / (set - rise)) * dayAmp
          var night = (rise - t0) + (t1 - set)
          if (t < rise) return -Math.sin(Math.PI * (rise - t) / night) * nightAmp
          return -Math.sin(Math.PI * (t - set) / night) * nightAmp
        }
        function xFor(t) { return (t - t0) / (t1 - t0) * w }
        function yFor(t) { return horizonY - elev(t) }

        var focus = Math.max(t0, Math.min(t1, view.focusMs))
        var sunX = xFor(focus)
        var sunY = yFor(focus)
        var e = isNaN(view.focusElev) ? -18 : view.focusElev

        // The sky, column by column: warm toward the sun, cool away from
        // it, zenith color fading to the horizon color.
        var zenith = Model.skyColorAt(view.sky.zenith, e)
        var near = Model.skyColorAt(view.sky.near, e)
        var far = Model.skyColorAt(view.sky.far, e)
        var step = 3
        for (var x = 0; x < w; x += step) {
          var prox = 1 - Math.min(1, Math.abs(x + step / 2 - sunX) / (w * 0.55))
          var horizonC = Model.lerpRgb(far, near, prox * prox)
          var g = ctx.createLinearGradient(0, 0, 0, horizonY)
          g.addColorStop(0, Model.cssRgba(zenith, 1))
          g.addColorStop(1, Model.cssRgba(horizonC, 1))
          ctx.fillStyle = g
          ctx.fillRect(x, 0, Math.min(step, w - x), horizonY)
        }

        // Glow around the sun, reaching a little below the horizon at
        // dusk and dawn; nothing once it's properly night.
        if (e > -12) {
          var sunC = e > -0.833 ? view.sky.sun : view.sky.sunTwilight
          var strength = Math.max(0, Math.min(1, (e + 12) / 14))
          var glow = ctx.createRadialGradient(sunX, sunY, 0, sunX, sunY, h * 0.55)
          glow.addColorStop(0, Model.cssRgba(sunC, 0.55 * strength))
          glow.addColorStop(0.35, Model.cssRgba(sunC, 0.18 * strength))
          glow.addColorStop(1, Model.cssRgba(sunC, 0))
          ctx.save()
          ctx.beginPath()
          ctx.rect(0, 0, w, horizonY)
          ctx.clip()
          ctx.fillStyle = glow
          ctx.fillRect(0, 0, w, horizonY)
          ctx.restore()
        }

        // The horizon.
        ctx.strokeStyle = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.22)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(0, horizonY + 0.5)
        ctx.lineTo(w, horizonY + 0.5)
        ctx.stroke()

        // The arc, dotted like the braille one: dim below the horizon,
        // brighter across the sky.
        function dottedSpan(from, to, color) {
          ctx.strokeStyle = color
          ctx.lineWidth = 2
          ctx.lineCap = "round"
          ctx.setLineDash([0.5, 4])
          ctx.beginPath()
          var steps = 80
          for (var i = 0; i <= steps; i++) {
            var t = from + (to - from) * i / steps
            if (i === 0) ctx.moveTo(xFor(t), yFor(t))
            else ctx.lineTo(xFor(t), yFor(t))
          }
          ctx.stroke()
          ctx.setLineDash([])
        }
        dottedSpan(t0, rise, Qt.rgba(view.muted.r, view.muted.g, view.muted.b, 0.9))
        dottedSpan(set, t1, Qt.rgba(view.muted.r, view.muted.g, view.muted.b, 0.9))
        dottedSpan(rise, set, Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.75))

        // While scrubbing, a small mark keeps now on the arc.
        if (view.scrubbing && now >= t0 && now <= t1) {
          ctx.fillStyle = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.6)
          ctx.beginPath()
          ctx.arc(xFor(now), yFor(now), 2.5, 0, 2 * Math.PI)
          ctx.fill()
        }

        // The sun itself: a soft disc by day, a small mark for where it
        // sits under the horizon by night.
        if (focus >= t0 && focus <= t1) {
          if (e > -0.833) {
            var disc = ctx.createRadialGradient(sunX, sunY, 0, sunX, sunY, 9)
            disc.addColorStop(0, Model.cssRgba(view.sky.sun, 1))
            disc.addColorStop(0.55, Model.cssRgba(view.sky.sun, 0.9))
            disc.addColorStop(1, Model.cssRgba(view.sky.sun, 0))
            ctx.fillStyle = disc
            ctx.beginPath()
            ctx.arc(sunX, sunY, 9, 0, 2 * Math.PI)
            ctx.fill()
          } else {
            ctx.fillStyle = view.foreground
            ctx.beginPath()
            ctx.arc(sunX, sunY, 3.5, 0, 2 * Math.PI)
            ctx.fill()
          }
        }
      }

      // Hover scrubs the day; leaving snaps back to now.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
          var t0 = view.startOfDay()
          view.scrubMs = t0 + Math.max(0, Math.min(1, mouse.x / width)) * 86400000
        }
        onExited: view.scrubMs = NaN
      }

      // The chip: the moment, the sun's altitude, and the light.
      Rectangle {
        visible: view.scrubbing
        x: {
          var sx = (view.focusMs - view.startOfDay()) / 86400000 * parent.width
          return sx < parent.width / 2 ? Math.min(parent.width - width - 4, sx + Style.space(14))
                                        : Math.max(4, sx - width - Style.space(14))
        }
        y: Style.space(6)
        width: scrubColumn.implicitWidth + Style.space(16)
        height: scrubColumn.implicitHeight + Style.space(12)
        color: Color.tooltip.background
        border.color: Color.tooltip.border
        border.width: 1

        Column {
          id: scrubColumn
          anchors.centerIn: parent
          spacing: Style.space(1)

          Text {
            text: Model.clockLabelMs(view.focusMs)
            color: Color.tooltip.text
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            text: isNaN(view.focusElev) ? ""
              : (view.focusElev >= 0 ? Math.round(view.focusElev) + "° above the horizon"
                                     : Math.round(-view.focusElev) + "° below the horizon")
            color: Color.tooltip.text
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            text: view.twilightWord(view.focusElev)
            color: Qt.darker(Color.tooltip.text, 1.3)
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    // Sunrise, the day's length, and sunset — the TUI's bottom line.
    Item {
      visible: arc.visible
      width: parent.width
      height: dayLength.implicitHeight

      Text {
        anchors.left: parent.left
        text: "󰖜 " + Model.clockLabel(view.payload ? view.payload.sunrise : "")
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Row {
        id: dayLength
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Text {
          text: view.payload && view.payload.day_length_seconds !== null
            ? Model.fmtDuration(view.payload.day_length_seconds) : ""
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          text: view.payload ? "(" + Model.fmtDeltaDuration(view.payload.day_length_delta_seconds) + ")" : ""
          visible: text !== "()"
          color: view.muted
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Text {
        anchors.right: parent.right
        text: Model.clockLabel(view.payload ? view.payload.sunset : "") + " 󰖛"
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    PanelSeparator { visible: !!view.payload; foreground: view.foreground }

    // ---- Info grid, battery-panel style: where the sun is and what
    //      tomorrow brings.
    Row {
      visible: !!view.payload
      width: parent.width
      spacing: Style.space(16)

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(4)

        InfoPair {
          label: "Sun now"
          value: isNaN(view.elevNow) ? ""
            : (view.elevNow >= 0 ? Math.round(view.elevNow) + "° up" : Math.round(-view.elevNow) + "° down")
          foreground: view.foreground
          fontFamily: view.fontFamily
        }

        InfoPair {
          label: "Solar noon"
          value: view.payload ? Model.clockLabel(view.payload.solar_noon) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(4)

        InfoPair {
          label: "Sunrise tmrw"
          value: view.payload ? Model.clockLabel(view.payload.tomorrow_sunrise) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }

        InfoPair {
          label: "Sunset tmrw"
          value: view.payload ? Model.clockLabel(view.payload.tomorrow_sunset) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }
    }
  }
}
