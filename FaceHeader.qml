import QtQuick
import qs.Commons

// The stock panel header, as the battery/power panel composes it: icon,
// bold title over a small-caps status line, and a display-sized value on
// the right. Every linecast face leads with one so the plugin reads as a
// native Omarchy panel.
Item {
  id: header

  property string icon: ""
  property Component iconComponent: null
  property string title: ""
  property string subtitle: ""
  property string bigValue: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // When set, the title block is a control (the weather face's location
  // menu): hand cursor, hover accent, and a clicked() signal.
  property bool interactive: false

  signal clicked()

  readonly property color titleColor: interactive && headerMouse.containsMouse
    ? Style.hoverStateColor(foreground, Color.accent)
    : foreground

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(leftRow.implicitHeight, bigText.implicitHeight)

  MouseArea {
    id: headerMouse
    x: leftRow.x
    y: leftRow.y
    width: leftRow.width
    height: leftRow.height
    enabled: header.interactive
    hoverEnabled: enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: header.clicked()
  }

  Row {
    id: leftRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(12)
    width: parent.width - (bigText.visible ? bigText.implicitWidth + Style.space(12) : 0)

    Loader {
      anchors.verticalCenter: parent.verticalCenter
      sourceComponent: header.iconComponent
      visible: header.iconComponent !== null
    }

    Text {
      textFormat: Text.PlainText
      visible: header.iconComponent === null && header.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: header.icon
      color: header.foreground
      font.family: header.fontFamily
      font.pixelSize: Style.font.display
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - x)

      Text {
        textFormat: Text.PlainText
        text: header.title + (header.interactive ? "  ▾" : "")
        color: header.titleColor
        font.family: header.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        text: header.subtitle.toUpperCase()
        color: Qt.darker(header.foreground, 1.4)
        font.family: header.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    id: bigText
    visible: text !== ""
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: header.bigValue
    color: header.foreground
    font.family: header.fontFamily
    font.pixelSize: Style.font.displayLarge
    font.bold: true
  }
}
