import QtQuick
import qs.Commons

// One label/value line of the stock two-column info grid (battery panel's
// "Battery size   51Wh" rows): dim label left, value pushed right.
Row {
  id: pair

  property string label: ""
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)
  visible: value !== ""

  Text {
    textFormat: Text.PlainText
    id: labelText
    text: pair.label
    color: pair.foreground
    opacity: 0.6
    font.family: pair.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Item {
    width: Math.max(0, pair.width - labelText.implicitWidth - valueText.implicitWidth - pair.spacing * 2)
    height: 1
  }

  Text {
    textFormat: Text.PlainText
    id: valueText
    text: pair.value
    color: pair.foreground
    font.family: pair.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
