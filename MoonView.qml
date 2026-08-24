import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Moon face, in the stock panel style: the drawn phase disc is the header
// icon (correct terminator, waxing lights the proper limb, mirrored for
// the southern hemisphere), phase and "up now" as the status line,
// illumination as the reading. Rise/set below — the part actually worth
// glancing for — then the cycle numbers. Fed by `linecast moon --json`.
Item {
  id: view

  property var bar
  property bool shown: false
  property var host: null
  property int locationEpoch: 0

  readonly property int panelWidth: Style.space(320)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)

  readonly property var payload: feed.payload
  readonly property var events: payload && payload.events ? payload.events : []

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
    command: (view.host ? view.host.linecastBin : "linecast") + " moon --json"
    staleAfterMs: 30 * 60 * 1000
  }

  component MoonDisc: Canvas {
    id: disc

    property real discSize: Style.space(40)

    width: discSize
    height: discSize

    Connections {
      target: feed
      function onPayloadChanged() { disc.requestPaint() }
    }

    // The disc reads foreground imperatively in onPaint; a theme swap
    // needs an explicit repaint.
    Connections {
      target: view
      function onForegroundChanged() { disc.requestPaint() }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!view.payload) return

      var cx = width / 2
      var cy = height / 2
      var R = Math.min(cx, cy) - 1
      var f = Math.max(0, Math.min(1, Model.num(view.payload.illumination, 0) / 100))
      var litRight = view.payload.waxing === true
      if (view.payload.southern === true) litRight = !litRight

      // Shadow disc first; the lit region paints over it.
      ctx.beginPath()
      ctx.arc(cx, cy, R, 0, 2 * Math.PI)
      ctx.fillStyle = Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.14)
      ctx.fill()

      if (f > 0.005) {
        // Lit region = outer semicircle on the lit limb plus the
        // terminator, a half-ellipse whose width tracks the phase: full at
        // the limbs, a straight line at the quarters. Past half it bulges
        // into the dark side (gibbous), before half into the lit side
        // (crescent). Drawn parametrically — Qt's Canvas ellipse() is a
        // nonstandard full-ellipse helper that would break the path.
        var rx = R * Math.abs(2 * f - 1)
        var side = ((f >= 0.5) ? !litRight : litRight) ? 1 : -1

        ctx.beginPath()
        // Outer semicircle, top to bottom along the lit limb. Canvas
        // angles run clockwise (y down): -π/2 → π/2 clockwise passes the
        // right limb; counterclockwise passes the left.
        ctx.arc(cx, cy, R, -Math.PI / 2, Math.PI / 2, !litRight)
        var steps = 40
        for (var i = 1; i <= steps; i++) {
          var th = Math.PI / 2 - Math.PI * i / steps
          ctx.lineTo(cx + side * rx * Math.cos(th), cy + R * Math.sin(th))
        }
        ctx.closePath()
        ctx.fillStyle = view.foreground
        ctx.fill()
      }
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
      text: feed.fetching ? "Finding the moon…" : "No moon data — is linecast ≥ 1.9 installed?"
      wrapMode: Text.WordWrap
      color: view.muted
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }

    FaceHeader {
      visible: !!view.payload
      iconComponent: Component { MoonDisc {} }
      title: "Moon"
      subtitle: {
        if (!view.payload) return ""
        var line = view.payload.phase || ""
        if (view.payload.up_now === true) {
          line += " · up now"
          var alt = Model.num(view.payload.altitude_deg, NaN)
          if (!isNaN(alt)) line += " " + Math.round(alt) + "°"
        }
        return line
      }
      bigValue: view.payload && Model.num(view.payload.illumination, -1) >= 0
        ? Math.round(view.payload.illumination) + "%" : ""
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    PanelSeparator { visible: view.events.length > 0; foreground: view.foreground }

    // ---- Rise and set: the next events in order.
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
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: (modelData.kind === "rise" ? "↑ " : "↓ ") + Model.clockLabel(modelData.time)
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            textFormat: Text.PlainText
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

    // ---- Info grid: where the cycle goes next.
    Row {
      visible: !!view.payload
      width: parent.width
      spacing: Style.space(16)

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(4)

        InfoPair {
          label: "Next full"
          value: view.payload && view.payload.next_full ? Model.shortDate(view.payload.next_full) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }

        InfoPair {
          label: "Next new"
          value: view.payload && view.payload.next_new ? Model.shortDate(view.payload.next_new) : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(4)

        InfoPair {
          label: "Age"
          value: view.payload && Model.num(view.payload.age_days, -1) >= 0
            ? Math.round(view.payload.age_days) + " days" : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }

        InfoPair {
          label: "Altitude"
          value: view.payload && Model.num(view.payload.altitude_deg, NaN) === Model.num(view.payload.altitude_deg, NaN)
            ? Math.round(view.payload.altitude_deg) + "°" : ""
          foreground: view.foreground
          fontFamily: view.fontFamily
        }
      }
    }
  }
}
