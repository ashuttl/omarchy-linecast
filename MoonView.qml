import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Moon face: a drawn phase disc — correct terminator, waxing lights the
// proper limb, mirrored for the southern hemisphere — beside the phase
// name and illumination, with rise/set (the part Andrew actually checks)
// and the next full/new dates. Fed by `linecast moon --json`.
Item {
  id: view

  property var bar
  property bool shown: false

  readonly property int panelWidth: Style.space(320)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)

  readonly property var payload: feed.payload
  readonly property var events: payload && payload.events ? payload.events : []

  function refresh() { feed.refresh() }

  onShownChanged: if (shown) feed.refreshIfStale()

  implicitHeight: column.implicitHeight

  JsonFeed {
    id: feed
    command: "linecast moon --json"
    staleAfterMs: 30 * 60 * 1000
    onPayloadChanged: disc.requestPaint()
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
      text: feed.fetching ? "Finding the moon…" : "No moon data — is linecast ≥ 1.9 installed?"
      wrapMode: Text.WordWrap
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }

    // ---- Hero: the disc, with phase and illumination beside it.
    Row {
      visible: !!view.payload
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(20)

      Canvas {
        id: disc
        width: Style.space(88)
        height: Style.space(88)
        anchors.verticalCenter: parent.verticalCenter

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          if (!view.payload) return

          var cx = width / 2
          var cy = height / 2
          var R = Math.min(cx, cy) - 2
          var f = Math.max(0, Math.min(1, Model.num(view.payload.illumination, 0) / 100))
          var litRight = view.payload.waxing === true
          if (view.payload.southern === true) litRight = !litRight

          var lit = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 1)
          var shadow = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.14)

          // Shadow disc first; the lit region paints over it.
          ctx.beginPath()
          ctx.arc(cx, cy, R, 0, 2 * Math.PI)
          ctx.fillStyle = shadow
          ctx.fill()

          if (f > 0.005) {
            // Lit region = outer semicircle on the lit limb plus the
            // terminator, a half-ellipse whose width tracks the phase:
            // full at the limbs, a straight line at the quarters. Past
            // half it bulges into the dark side (gibbous), before half
            // into the lit side (crescent). The half-ellipse is drawn
            // parametrically — Qt's Canvas ellipse() is a nonstandard
            // full-ellipse helper that would break the path.
            var rx = R * Math.abs(2 * f - 1)
            var side = ((f >= 0.5) ? !litRight : litRight) ? 1 : -1

            ctx.beginPath()
            // Outer semicircle, top to bottom along the lit limb. Canvas
            // angles run clockwise (y down): -π/2 → π/2 clockwise passes
            // the right limb; counterclockwise passes the left.
            ctx.arc(cx, cy, R, -Math.PI / 2, Math.PI / 2, !litRight)
            // Terminator, bottom back to top.
            var steps = 40
            for (var i = 1; i <= steps; i++) {
              var th = Math.PI / 2 - Math.PI * i / steps
              ctx.lineTo(cx + side * rx * Math.cos(th), cy + R * Math.sin(th))
            }
            ctx.closePath()
            ctx.fillStyle = lit
            ctx.fill()
          }
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          text: view.payload ? (view.payload.phase || "") : ""
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          text: view.payload && Model.num(view.payload.illumination, -1) >= 0
            ? Math.round(view.payload.illumination) + "% illuminated" : ""
          color: view.muted
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: !!(view.payload && view.payload.up_now === true)
          topPadding: Style.space(4)
          text: {
            var line = "up right now"
            var alt = view.payload ? Model.num(view.payload.altitude_deg, NaN) : NaN
            if (!isNaN(alt)) line += " · " + Math.round(alt) + "° up"
            return line
          }
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
          font.italic: true
        }

        Text {
          topPadding: Style.space(6)
          text: view.payload ? (view.payload.location || "") : ""
          color: view.muted
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    PanelSeparator { visible: view.events.length > 0; foreground: view.foreground }

    // ---- Rise and set: the next events in order, the thing worth
    //      glancing for ("it's up right now").
    Row {
      visible: view.events.length > 0
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(24)

      Repeater {
        model: view.events

        Column {
          required property var modelData
          spacing: 0

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (modelData.kind === "rise" ? "↑ " : "↓ ") + Model.clockLabel(modelData.time)
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.kind === "rise" ? "moonrise" : "moonset"
            color: view.muted
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    PanelSeparator { visible: !!view.payload; foreground: view.foreground }

    // ---- Footer: where the cycle goes next.
    Row {
      visible: !!view.payload
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(20)
      bottomPadding: Style.space(4)

      GlanceStat {
        glyph: "󰽢"
        value: view.payload && view.payload.next_full
          ? "full " + Model.shortDate(view.payload.next_full) : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }

      GlanceStat {
        glyph: "󰽤"
        value: view.payload && view.payload.next_new
          ? "new " + Model.shortDate(view.payload.next_new) : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }

      GlanceStat {
        glyph: "󰥔"
        value: view.payload && Model.num(view.payload.age_days, -1) >= 0
          ? Math.round(view.payload.age_days) + "d old" : ""
        glyphColor: view.muted
        valueColor: view.foreground
        fontFamily: view.fontFamily
      }
    }
  }
}
