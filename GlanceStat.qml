import QtQuick
import qs.Commons

// One glyph + value pair for a panel's footer row. Hidden when empty so
// rows collapse cleanly around missing data.
Row {
  id: stat

  property string glyph: ""
  property string value: ""
  property color glyphColor: Color.foreground
  property color valueColor: Color.foreground
  property string fontFamily: Style.font.family

  visible: value !== ""
  spacing: Style.space(5)

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: stat.glyph
    color: stat.glyphColor
    font.family: stat.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: stat.value
    color: stat.valueColor
    font.family: stat.fontFamily
    font.pixelSize: Style.font.caption
  }
}
