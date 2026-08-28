import QtQuick
import qs.Commons
import qs.Ui

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

  implicitHeight: Math.max(summary.implicitHeight, openAction.implicitHeight)

  Column {
    id: summary
    anchors.left: parent.left
    anchors.right: openAction.visible ? openAction.left : parent.right
    anchors.rightMargin: openAction.visible ? Style.space(8) : 0
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

  PanelActionButton {
    id: openAction
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: row.linkAvailable
    iconText: "\uf35d"
    tooltipText: "Open in Canvas"
    foreground: row.muted
    hoverColor: row.accent
    fontFamily: row.fontFamily
    onClicked: row.activated()
  }

  MouseArea {
    id: linkArea
    anchors.left: parent.left
    anchors.right: openAction.visible ? openAction.left : parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    enabled: row.linkAvailable
    hoverEnabled: enabled
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: row.activated()
  }
}
