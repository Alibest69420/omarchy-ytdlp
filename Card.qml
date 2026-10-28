import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Formats.js" as Formats

// The download popup. Queue state lives in Panel.qml / DownloadEngine.qml; this file
// only collects the link, format, quality and destination, then renders the
// live queue.
FocusScope {
  id: card

  property var panel: null
  property string errorText: ""
  property bool dirTouched: false
  property bool _initialized: false
  property bool _autoPaste: false
  property string lastAutoPasted: ""
  property alias inputField: urlField

  readonly property var engine: panel ? panel.engine : null
  readonly property color fg: panel ? panel.foreground : Color.foreground
  readonly property color dim: panel ? panel.dim : Qt.darker(Color.foreground, 1.5)
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property color urgent: panel ? panel.urgent : Color.urgent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property real bodyHeight: content.implicitHeight

  anchors.fill: parent
  focus: true

  Keys.onEscapePressed: function(event) {
    if (panel) panel.close()
    event.accepted = true
  }

  function defaultDirFor(format) {
    return Formats.defaultDir(format, panel.setting("audioDir", "~/Music"), panel.setting("videoDir", "~/Videos"))
  }

  function initForm() {
    if (_initialized || !panel) return
    _initialized = true
    var format = String(panel.setting("defaultFormat", "opus"))
    if (!Formats.hasFormat(format)) format = "opus"
    formatDrop.value = format

    var options = Formats.qualityOptions(format)
    qualityDrop.options = options
    var quality = String(panel.setting("defaultQuality", "best"))
    qualityDrop.value = Formats.hasQuality(format, quality) ? quality : "best"
    dirField.text = defaultDirFor(format)
  }

  function maybeAutoPaste() {
    initForm()
    if (!panel || !panel.setting("autoPaste", true)) return
    if (urlField.text.trim() !== "") return
    pasteClipboard(true)
  }

  function isUrl(text) {
    return /^https?:\/\//i.test(String(text || "").trim())
  }

  function pasteClipboard(auto) {
    _autoPaste = auto === true
    if (clipProc.running) clipProc.running = false
    clipProc.running = true
  }

  function applyClipboard(text) {
    var value = String(text || "").trim()
    if (value === "") return
    if (_autoPaste) {
      if (!isUrl(value)) return
      if (value === lastAutoPasted || value === panel.lastSubmittedUrl) return
      if (urlField.text.trim() !== "") return
      lastAutoPasted = value
    }
    urlField.text = value
    errorText = ""
  }

  function browser() {
    var start = panel.expandPath(dirField.text)
    picker.command = [
      "zenity", "--file-selection", "--directory",
      "--title=Choose download folder",
      "--filename=" + start + "/"
    ]
    picker.running = true
  }

  function startDownload() {
    initForm()
    if (!panel) return
    if (!panel.toolsOk) {
      errorText = panel.toolError
      return
    }
    var parts = urlField.text.trim().split(/[\s,]+/)
    var urls = []
    for (var i = 0; i < parts.length; i++)
      if (isUrl(parts[i])) urls.push(parts[i])
    if (urls.length === 0) {
      errorText = "Enter a link starting with http:// or https://"
      return
    }
    var directory = dirField.text.trim()
    if (directory === "") {
      errorText = "Choose a download folder"
      dirField.focus = true
      return
    }
    if (!panel.startDownload(urls, formatDrop.value, qualityDrop.value, directory)) {
      errorText = panel.toolError || "Could not start the download"
      return
    }
    urlField.text = ""
    dirTouched = false
    dirField.text = defaultDirFor(formatDrop.value)
    errorText = ""
  }

  Process {
    id: clipProc
    command: ["wl-paste", "--no-newline", "--type", "text/plain"]
    stdout: StdioCollector {
      id: clipOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) card.applyClipboard(clipOut.text)
    }
  }

  Process {
    id: picker
    command: []
    stdout: StdioCollector {
      id: pickerOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var path = String(pickerOut.text || "").trim()
      if (exitCode === 0 && path !== "") {
        dirField.text = path
        card.dirTouched = true
        card.errorText = ""
      }
    }
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(9)

    PanelHero {
      width: parent.width
      title: "yt-dlp"
      meta: !card.panel || !card.panel.toolsOk ? "YT-DLP OR FFMPEG MISSING"
        : card.engine && card.engine.busy ? "DOWNLOADING"
        : card.panel.ytdlpVersion !== "" ? "AUDIO & VIDEO · " + card.panel.ytdlpVersion
        : "AUDIO & VIDEO"
      detail: card.engine && card.engine.busy ? Math.round(card.engine.progress) + "%"
        : card.engine && card.engine.queuedCount > 0 ? card.engine.queuedCount + " queued"
        : ""
      foreground: card.fg
      fontFamily: card.fontFamily

      iconComponent: Component {
        Item {
          width: Style.font.display
          height: Style.font.display

          Text {
            anchors.centerIn: parent
            text: "󰇚"
            color: card.fg
            font.family: card.fontFamily
            font.pixelSize: Style.font.display
          }
        }
      }

      trailingControl: Component {
        Row {
          spacing: Style.space(4)

          PanelActionButton {
            iconText: "󰒓"
            tooltipText: "Settings"
            focusable: true
            foreground: card.fg
            fontFamily: card.fontFamily
            onClicked: if (card.panel) card.panel.showSettings()
          }
        }
      }
    }

    PanelSeparator { width: parent.width; foreground: card.fg }

    RowLayout {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: urlField
        Layout.fillWidth: true
        placeholderText: "Paste a video or track link"
        foreground: card.fg
        selectByMouse: true
        onAccepted: card.startDownload()
        onTextEdited: card.errorText = ""
        Keys.onEscapePressed: function(event) {
          card.panel.close()
          event.accepted = true
        }
      }

      Button {
        text: "Paste"
        bordered: true
        focusable: true
        fontSize: Style.font.caption
        foreground: card.fg
        fontFamily: card.fontFamily
        onClicked: card.pasteClipboard(false)
      }
    }

    Text {
      width: parent.width
      visible: card.errorText !== ""
      text: card.errorText
      color: card.urgent
      font.family: card.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      Dropdown {
        id: formatDrop
        Layout.preferredWidth: Style.space(160)
        label: "Format"
        value: "opus"
        options: Formats.allFormats()
        foreground: card.fg
        accent: card.accent
        fontFamily: card.fontFamily
        onChanged: function(value) {
          qualityDrop.options = Formats.qualityOptions(value)
          if (!Formats.hasQuality(value, qualityDrop.value)) qualityDrop.value = "best"
          if (!card.dirTouched) dirField.text = card.defaultDirFor(value)
          card.errorText = ""
        }
      }

      Dropdown {
        id: qualityDrop
        Layout.fillWidth: true
        label: "Quality"
        value: "best"
        options: []
        foreground: card.fg
        accent: card.accent
        fontFamily: card.fontFamily
      }
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: "󰉋"
        color: card.dim
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }

      TextField {
        id: dirField
        Layout.fillWidth: true
        placeholderText: "~/Music"
        foreground: card.fg
        selectByMouse: true
        onTextEdited: card.dirTouched = true
        onAccepted: card.startDownload()
        Keys.onEscapePressed: function(event) {
          card.panel.close()
          event.accepted = true
        }
      }

      Button {
        text: "Browse…"
        bordered: true
        focusable: true
        fontSize: Style.font.caption
        foreground: card.fg
        fontFamily: card.fontFamily
        onClicked: card.browser()
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(4)
      visible: card.panel && card.panel.favoriteDirs().length > 0

      Repeater {
        model: card.panel ? card.panel.favoriteDirs() : []

        delegate: Button {
          required property var modelData
          text: card.panel.shortPath(modelData)
          tooltipText: modelData
          bordered: true
          focusable: true
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.sm
          foreground: card.fg
          fontFamily: card.fontFamily
          onClicked: {
            dirField.text = modelData
            card.dirTouched = true
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: {
        var format = formatDrop.value
        if (Formats.isLosslessContainer(format))
          return "FLAC and WAV are lossless containers. Converting a lossy source keeps its quality; it cannot restore detail."
        if (Formats.isVideo(format))
          return "Video picks the best video and audio streams up to the quality you choose."
        return ""
      }
      color: card.dim
      font.family: card.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Button {
      width: parent.width
      text: card.engine && card.engine.busy ? "Add to queue" : "Download"
      iconText: "󰇚"
      bordered: true
      focusable: true
      fontSize: Style.font.body
      foreground: card.fg
      fontFamily: card.fontFamily
      enabled: card.panel ? card.panel.toolsOk : false
      onClicked: card.startDownload()
    }

    RowLayout {
      width: parent.width
      visible: card.engine && card.engine.jobs.length > 0

      PanelSectionHeader {
        Layout.fillWidth: true
        text: "QUEUE"
        foreground: card.fg
        fontFamily: card.fontFamily
      }

      Button {
        visible: card.engine && card.engine.finishedCount > 0
        text: "Clear finished"
        focusable: true
        fontSize: Style.font.caption
        foreground: card.fg
        fontFamily: card.fontFamily
        onClicked: card.engine.clearFinished()
      }
    }

    ListView {
      id: queueList
      width: parent.width
      height: visible ? Math.min(contentHeight, Style.space(190)) : 0
      visible: count > 0
      model: card.engine ? card.engine.jobs : []
      spacing: 1
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: JobRow {
        width: ListView.view.width
        job: modelData
        panel: card.panel
      }
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      Button {
        text: "Open folder"
        iconText: "󰉋"
        bordered: true
        focusable: true
        fontSize: Style.font.caption
        foreground: card.fg
        fontFamily: card.fontFamily
        onClicked: card.panel.openDir(dirField.text)
      }

      Item { Layout.fillWidth: true }

      Text {
        text: card.engine ? card.engine.jobs.length + (card.engine.jobs.length === 1 ? " item" : " items") : ""
        color: card.dim
        font.family: card.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
