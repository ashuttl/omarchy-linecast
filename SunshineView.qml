import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Sunshine face: countdown to the next sunrise/sunset over the TUI's
// solar arc — the sun's height through the day against a horizon line,
// on a scale the year fits in, so the arc rides high in summer and low
// in winter; the sky above the horizon colored for the sun's elevation
// right now, warm near the sun and cool away from it, the sun glowing at
// its position — with sunrise, day length, and sunset beneath, and the
// day's hours in a tradition's reckoning when linecast is set to one.
// Fed by `linecast sunshine --json`.
Item {
  id: view

  property var bar
  property bool shown: false
  property var host: null
  property int locationEpoch: 0
  // ThemePalette from the panel; null falls back to fixed colors.
  property var palette: null

  readonly property int panelWidth: Style.space(340)

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property var themeColors: palette ? palette.colors : null
  readonly property var sky: Model.buildSkyStops(themeColors, Commons.Color.background)

  readonly property var payload: feed.payload

  // The payload's times are local to the place and carry no zone, so
  // "now" is kept on the place's clock too: this machine's, moved by
  // however far the place's wall clock stood from it at the fetch (zones
  // sit on quarter hours). Ticks while shown so the countdown and sun
  // position stay honest.
  readonly property double placeShiftMs: {
    var fetched = payload ? Model.parseIsoLocal(payload.fetched_at) : NaN
    if (isNaN(fetched) || !feed.fetchedAtMs) return 0
    return Math.round((fetched - feed.fetchedAtMs) / 900000) * 900000
  }
  property double clockMs: Date.now()
  readonly property double nowMs: clockMs + placeShiftMs
  function tick() { view.clockMs = Date.now() }

  readonly property var nextEvent: payload ? payload.next_event : null
  readonly property real riseMs: payload ? Model.parseIsoLocal(payload.sunrise) : NaN
  readonly property real setMs: payload ? Model.parseIsoLocal(payload.sunset) : NaN
  // The payload's reading is as old as the fetch; the model's moves
  // with the clock.
  readonly property real elevNow: {
    if (!payload) return NaN
    var modeled = elevationAt(nowMs)
    return isNaN(modeled) ? Model.num(payload.elevation_deg, NaN) : modeled
  }
  readonly property string polar: payload && payload.polar ? String(payload.polar) : ""
  // The day in a tradition's hours (`linecast hours`): prayer times,
  // zmanim, the Roman or Japanese hours. Null with none set.
  readonly property var hours: payload && payload.hours ? payload.hours : null
  readonly property var hourMarks: hours && hours.marks ? hours.marks : []
  readonly property int nextMarkIndex: {
    for (var i = 0; i < hourMarks.length; i++)
      if (Model.parseIsoLocal(hourMarks[i].time) > nowMs) return i
    return -1
  }
  readonly property bool sunUp: !isNaN(elevNow) && elevNow > -0.833

  // Scrubbing: hovering the arc moves the sun and repaints the sky for
  // that moment. NaN means now.
  property real scrubMs: NaN
  readonly property bool scrubbing: !isNaN(scrubMs)
  readonly property real focusMs: scrubbing ? scrubMs : nowMs
  readonly property real focusElev: scrubbing ? elevationAt(scrubMs) : elevNow
  onScrubMsChanged: arc.requestPaint()

  // ---- A solar model for any moment of the day (Model.js): the place
  //      isn't in the payload, so its latitude is recovered from the
  //      day's length and the sun's height at the fetch, and elevation
  //      follows from the hour angle around solar noon.
  readonly property real solarNoonMs: payload ? Model.parseIsoLocal(payload.solar_noon) : NaN
  readonly property real declinationDeg: isNaN(solarNoonMs) ? 0 : Model.solarDeclination(solarNoonMs)
  readonly property real latitudeDeg: {
    if (!view.payload || isNaN(view.solarNoonMs)) return 45
    return Model.solarLatitude(view.declinationDeg,
                               Model.num(view.payload.day_length_seconds, NaN) / 3600,
                               view.solarNoonMs,
                               Model.parseIsoLocal(view.payload.fetched_at),
                               Model.num(view.payload.elevation_deg, NaN))
  }
  function elevationAt(ms) {
    if (isNaN(view.solarNoonMs)) return NaN
    return Model.solarElevation(view.latitudeDeg, view.declinationDeg, view.solarNoonMs, ms)
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
    var d = new Date(isNaN(view.solarNoonMs) ? view.nowMs : view.solarNoonMs)
    d.setHours(0, 0, 0, 0)
    return d.getTime()
  }

  onShownChanged: if (shown) { view.tick(); feed.refreshIfStale() }
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
    command: (view.host ? view.host.linecastBin : "linecast") + " sunshine --json"
    staleAfterMs: 30 * 60 * 1000
    onPayloadChanged: arc.requestPaint()
  }

  Timer {
    interval: 30 * 1000
    running: view.shown
    repeat: true
    onTriggered: {
      view.tick()
      arc.requestPaint()
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      visible: !view.payload
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      topPadding: Style.space(24)
      bottomPadding: Style.space(24)
      text: feed.fetching ? "Reading the sky…" : "No solar data — linecast couldn't be read."
      wrapMode: Text.WordWrap
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }

    // ---- Header, battery-panel style: the next event as the status
    //      line, the countdown as the reading.
    //      Past the polar circles there may be no event to count to.
    FaceHeader {
      visible: !!view.payload
      icon: view.nextEvent ? (view.nextEvent.kind === "sunrise" ? "󰖜" : "󰖛")
        : view.polar === "night" ? "󰖔" : "󰖙"
      title: "Sunshine"
      subtitle: view.nextEvent
        ? ("until " + view.nextEvent.kind + " at " + Model.clockLabel(view.nextEvent.time)
           + (Model.dayTag(view.nextEvent.time, view.nowMs) === "" ? "" : " " + Model.dayTag(view.nextEvent.time, view.nowMs)))
        : view.polar === "day" ? "polar day — the sun stays up"
        : view.polar === "night" ? "polar night — the sun stays down" : ""
      bigValue: {
        if (!view.nextEvent) return ""
        var secs = Model.secondsUntil(view.nextEvent.time, view.nowMs)
        return isNaN(secs) ? "" : Model.fmtDuration(Math.max(0, secs))
      }
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    // ---- The arc: today from midnight to midnight, the sun's height
    //      above and below the horizon on the TUI's seasonal scale (the
    //      summer solstice's noon at the top, the winter solstice's
    //      midnight at the bottom), under a sky painted for the sun's
    //      elevation right now.
    Canvas {
      id: arc
      visible: !!view.payload && !isNaN(view.solarNoonMs)
      width: parent.width
      height: Style.space(148)

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!view.payload || isNaN(view.solarNoonMs)) return

        var w = width
        var h = height
        var t0 = view.startOfDay()
        var t1 = t0 + 24 * 3600 * 1000
        var now = view.nowMs

        // One scale above and below, so the curve crosses the horizon
        // without a bend; the margin keeps the solstice sun inside.
        var horizonY = Math.round(h / 2)
        var margin = 11
        var perDegree = (horizonY - margin) / Model.solarAnnualPeak(view.latitudeDeg)

        function xFor(t) { return (t - t0) / (t1 - t0) * w }
        function yFor(t) { return horizonY - view.elevationAt(t) * perDegree }

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

        // Glow around the sun; below the horizon it stays on the
        // horizon, where the light is. Nothing once it's properly night.
        if (e > -12) {
          var sunC = e > -0.833 ? view.sky.sun : view.sky.sunTwilight
          var strength = Math.max(0, Math.min(1, (e + 12) / 14))
          var glowY = Math.min(sunY, horizonY)
          var glow = ctx.createRadialGradient(sunX, glowY, 0, sunX, glowY, h * 0.5)
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

        // The horizon, ticked where the tradition's hours fall.
        var ink = view.foreground
        ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.22)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(0, horizonY + 0.5)
        ctx.lineTo(w, horizonY + 0.5)
        ctx.stroke()
        ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.5)
        for (var m = 0; m < view.hourMarks.length; m++) {
          var markMs = Model.parseIsoLocal(view.hourMarks[m].time)
          if (isNaN(markMs) || markMs < t0 || markMs > t1) continue
          var markX = Math.round(xFor(markMs)) + 0.5
          ctx.beginPath()
          ctx.moveTo(markX, horizonY + 1)
          ctx.lineTo(markX, horizonY + 6)
          ctx.stroke()
        }

        // The arc, one line through the whole day: brighter across the
        // sky, dim below the horizon.
        function strokeArc(top, bottom, color) {
          ctx.save()
          ctx.beginPath()
          ctx.rect(0, top, w, bottom - top)
          ctx.clip()
          ctx.strokeStyle = color
          ctx.lineWidth = 2
          ctx.lineJoin = "round"
          ctx.beginPath()
          var steps = Math.max(48, Math.round(w / 2))
          for (var i = 0; i <= steps; i++) {
            var t = t0 + (t1 - t0) * i / steps
            if (i === 0) ctx.moveTo(xFor(t), yFor(t))
            else ctx.lineTo(xFor(t), yFor(t))
          }
          ctx.stroke()
          ctx.restore()
        }
        strokeArc(horizonY, h, Qt.rgba(view.muted.r, view.muted.g, view.muted.b, 0.9))
        strokeArc(0, horizonY, Qt.rgba(ink.r, ink.g, ink.b, 0.75))

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
        id: scrubMouse
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
        y: {
          var above = scrubMouse.mouseY - height - Style.space(10)
          return above >= 0 ? above : Math.min(parent.height - height, scrubMouse.mouseY + Style.space(14))
        }
        width: scrubColumn.implicitWidth + Style.space(16)
        height: scrubColumn.implicitHeight + Style.space(12)
        color: Commons.Color.tooltip.background
        border.color: Commons.Color.tooltip.border
        border.width: 1

        Column {
          id: scrubColumn
          anchors.centerIn: parent
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            text: Model.clockLabelMs(view.focusMs)
            color: Commons.Color.tooltip.text
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: isNaN(view.focusElev) ? ""
              : (view.focusElev >= 0 ? Math.round(view.focusElev) + "° above the horizon"
                                     : Math.round(-view.focusElev) + "° below the horizon")
            color: Commons.Color.tooltip.text
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            text: view.twilightWord(view.focusElev)
            color: Qt.darker(Commons.Color.tooltip.text, 1.3)
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
        textFormat: Text.PlainText
        anchors.left: parent.left
        visible: !!(view.payload && view.payload.sunrise)
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
          textFormat: Text.PlainText
          text: view.polar === "night" ? "no daylight"
            : view.polar === "day" ? "24h of daylight"
            : view.payload && view.payload.day_length_seconds !== null
            ? Model.fmtDuration(view.payload.day_length_seconds) : ""
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          text: view.payload ? "(" + Model.fmtDeltaDuration(view.payload.day_length_delta_seconds) + ")" : ""
          visible: text !== "()"
          color: view.muted
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        visible: !!(view.payload && view.payload.sunset)
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

    // ---- The day in a tradition's hours, when `linecast hours` names
    //      one: what the hour is now, the next mark, then every mark.
    PanelSeparator { visible: view.hourMarks.length > 0; foreground: view.foreground }

    Item {
      visible: view.hourMarks.length > 0
      width: parent.width
      height: hoursTitle.implicitHeight

      Text {
        id: hoursTitle
        textFormat: Text.PlainText
        anchors.left: parent.left
        width: parent.width - hoursNext.implicitWidth - Style.space(12)
        elide: Text.ElideRight
        text: {
          if (!view.hours) return ""
          if (view.hours.now && view.hours.now.label) return String(view.hours.now.label)
          var name = String(view.hours.system || "")
          name = name.charAt(0).toUpperCase() + name.slice(1) + " hours"
          return view.hours.variant_name ? name + " · " + view.hours.variant_name : name
        }
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: hoursNext
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.baseline: hoursTitle.baseline
        text: {
          var next = view.nextMarkIndex >= 0 ? view.hourMarks[view.nextMarkIndex] : null
          if (!next) return ""
          var secs = Model.secondsUntil(next.time, view.nowMs)
          return isNaN(secs) ? "" : next.name + " in " + Model.fmtDuration(Math.max(0, secs))
        }
        color: view.muted
        font.family: view.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Grid {
      visible: view.hourMarks.length > 0
      width: parent.width
      columns: 2
      columnSpacing: Style.space(16)
      rowSpacing: Style.space(4)

      Repeater {
        model: view.hourMarks

        InfoPair {
          width: (parent.width - Style.space(16)) / 2
          label: (index === view.nextMarkIndex ? "▸ " : "") + String(modelData.name || modelData.key || "")
          value: Model.clockLabel(modelData.time)
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }
    }
  }
}
