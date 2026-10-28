import QtQuick
import qs.Commons
import qs.Ui

// Labeled toggle row used by the settings page.
Item {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal toggled()

  width: parent ? parent.width : 0
  implicitHeight: Math.max(labels.implicitHeight, toggle.height) + Style.space(8)

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: toggle.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
    }

    Text {
      width: parent.width
      visible: root.description !== ""
      text: root.description
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
    }
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    foreground: root.foreground
    onToggled: root.toggled()
  }
}
