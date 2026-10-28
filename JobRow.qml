import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One row in the popup queue.
Item {
  id: root

  property var job: ({})
  property var panel: null

  readonly property color fg: panel ? panel.foreground : Color.foreground
  readonly property color dim: panel ? panel.dim : Qt.darker(Color.foreground, 1.5)
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property color urgent: panel ? panel.urgent : Color.urgent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property bool active: job.status === "downloading" || job.status === "starting" || job.status === "processing"
  readonly property bool showBar: active || job.status === "done"
  readonly property real ratio: Math.max(0, Math.min(1, (Number(job.progress) || 0) / 100))

  implicitHeight: Style.space(58)

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
    spacing: Style.space(8)

    Text {
      text: panel ? panel.statusIcon(job) : "󰇚"
      color: job.status === "error" ? root.urgent : job.status === "done" ? root.accent : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(2)

      Text {
        Layout.fillWidth: true
        text: root.job.title || root.job.url || ""
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.active
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        Layout.fillWidth: true
        text: panel ? panel.jobStatusLine(root.job) : ""
        color: panel ? panel.statusColor(root.job) : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(3)
        visible: root.showBar

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
        }

        Rectangle {
          width: parent.width * root.ratio
          height: parent.height
          radius: height / 2
          color: root.accent
        }
      }
    }

    Row {
      spacing: Style.space(1)
      Layout.alignment: Qt.AlignVCenter

      PanelActionButton {
        visible: root.job.status === "done"
        iconText: "󰉋"
        tooltipText: "Open folder"
        focusable: true
        foreground: root.fg
        fontFamily: root.fontFamily
        onClicked: if (root.panel) root.panel.openDir(root.job.dir)
      }

      PanelActionButton {
        visible: root.job.status === "error" || root.job.status === "cancelled"
        iconText: "󰑐"
        tooltipText: "Retry"
        focusable: true
        foreground: root.fg
        fontFamily: root.fontFamily
        onClicked: if (root.panel) root.panel.engine.retry(root.job.id)
      }

      PanelActionButton {
        visible: root.job.status === "queued" || root.job.status === "downloading"
          || root.job.status === "starting" || root.job.status === "processing"
          || root.job.status === "cancelling"
        iconText: "󰅖"
        tooltipText: "Cancel"
        focusable: true
        hoverColor: root.urgent
        foreground: root.fg
        fontFamily: root.fontFamily
        onClicked: if (root.panel) root.panel.engine.cancel(root.job.id)
      }
    }
  }
}
