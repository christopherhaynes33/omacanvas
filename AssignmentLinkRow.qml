import QtQuick
import qs.Commons

Item {
  id: row

  required property string title
  required property string subtitle
  required property bool submitted
  property bool linkAvailable: false
  property color foreground
  property color muted
  property color accent
  property string fontFamily

  signal activated()

  implicitHeight: summary.implicitHeight

  Column {
    id: summary
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Text {
      width: parent.width
      text: (row.submitted ? "✓  " : "•  ") + row.title
      textFormat: Text.PlainText
      color: linkArea.containsMouse
        ? row.accent : (row.submitted ? row.muted : row.foreground)
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      font.bold: !row.submitted
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      text: row.subtitle
      textFormat: Text.PlainText
      color: row.muted
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  MouseArea {
    id: linkArea
    anchors.fill: parent
    enabled: row.linkAvailable
    hoverEnabled: enabled
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: row.activated()
  }
}
