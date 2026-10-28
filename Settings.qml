import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Formats.js" as Formats

// Settings page for the downloader. Values are collected on Apply and written
// to the widget's inline shell.json entry by Panel.persistSettings().
FocusScope {
  id: page

  property var panel: null
  property var settings: ({})
  property alias firstField: audioDirField

  property bool playlists: false
  property bool embedMetadata: true
  property bool embedThumbnail: true
  property bool notifications: true
  property bool autoPaste: true

  signal apply(var values)
  signal closeRequested()

  readonly property color fg: panel ? panel.foreground : Color.foreground
  readonly property color dim: panel ? panel.dim : Qt.darker(Color.foreground, 1.5)
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property color accent: panel ? panel.accent : Color.accent

  implicitWidth: Style.space(480)
  implicitHeight: column.implicitHeight
  focus: true

  Keys.onEscapePressed: function(event) {
    page.closeRequested()
    event.accepted = true
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function begin() {
    var format = String(setting("defaultFormat", "opus"))
    if (!Formats.hasFormat(format)) format = "opus"
    formatDrop.value = format
    qualityDrop.options = Formats.qualityOptions(format)
    var quality = String(setting("defaultQuality", "best"))
    qualityDrop.value = Formats.hasQuality(format, quality) ? quality : "best"

    audioDirField.text = String(setting("audioDir", "~/Music"))
    videoDirField.text = String(setting("videoDir", "~/Videos"))
    favoritesField.text = String(setting("favorites", ""))
    templateField.text = String(setting("filenameTemplate", "%(title)s.%(ext)s"))
    cookiesDrop.value = String(setting("cookiesBrowser", "none"))

    playlists = Boolean(setting("playlists", false))
    embedMetadata = Boolean(setting("embedMetadata", true))
    embedThumbnail = Boolean(setting("embedThumbnail", true))
    notifications = Boolean(setting("notifications", true))
    autoPaste = Boolean(setting("autoPaste", true))
  }

  function collect() {
    return {
      defaultFormat: formatDrop.value,
      defaultQuality: qualityDrop.value,
      audioDir: audioDirField.text.trim() || "~/Music",
      videoDir: videoDirField.text.trim() || "~/Videos",
      favorites: favoritesField.text.trim(),
      filenameTemplate: templateField.text.trim() || "%(title)s.%(ext)s",
      cookiesBrowser: cookiesDrop.value,
      playlists: page.playlists,
      embedMetadata: page.embedMetadata,
      embedThumbnail: page.embedThumbnail,
      notifications: page.notifications,
      autoPaste: page.autoPaste
    }
  }

  function browse(target) {
    browseTarget = target
    picker.command = [
      "zenity", "--file-selection", "--directory",
      "--title=Choose folder",
      "--filename=" + panel.expandPath(target === "audio" ? audioDirField.text : videoDirField.text) + "/"
    ]
    picker.running = true
  }

  property string browseTarget: "audio"

  Process {
    id: picker
    command: []
    stdout: StdioCollector {
      id: pickerOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var path = String(pickerOut.text || "").trim()
      if (exitCode !== 0 || path === "") return
      if (page.browseTarget === "audio") audioDirField.text = path
      else videoDirField.text = path
    }
  }

  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(9)

      PanelHero {
        width: parent.width
        title: "Settings"
        meta: "YT-DLP DOWNLOADS"
        foreground: page.fg
        fontFamily: page.fontFamily

        iconComponent: Component {
          Item {
            width: Style.font.display
            height: Style.font.display

            Text {
              anchors.centerIn: parent
              text: "󰒓"
              color: page.fg
              font.family: page.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        trailingControl: Component {
          PanelActionButton {
            iconText: "󰁍"
            tooltipText: "Back"
            focusable: true
            foreground: page.fg
            fontFamily: page.fontFamily
            onClicked: page.closeRequested()
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: page.fg }

      PanelSectionHeader {
        text: "DEFAULTS"
        foreground: page.fg
        fontFamily: page.fontFamily
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Dropdown {
          id: formatDrop
          Layout.preferredWidth: Style.space(170)
          label: "Format"
          value: "opus"
          options: Formats.allFormats()
          foreground: page.fg
          accent: page.accent
          fontFamily: page.fontFamily
          onChanged: function(value) {
            qualityDrop.options = Formats.qualityOptions(value)
            if (!Formats.hasQuality(value, qualityDrop.value)) qualityDrop.value = "best"
          }
        }

        Dropdown {
          id: qualityDrop
          Layout.fillWidth: true
          label: "Quality"
          value: "best"
          options: []
          foreground: page.fg
          accent: page.accent
          fontFamily: page.fontFamily
        }
      }

      Text {
        width: parent.width
        text: "New downloads start with these. Every download can still override them in the popup."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      PanelSeparator { width: parent.width; foreground: page.fg }

      PanelSectionHeader {
        text: "FOLDERS"
        foreground: page.fg
        fontFamily: page.fontFamily
      }

      Text {
        width: parent.width
        text: "Audio folder"
        color: page.fg
        font.family: page.fontFamily
        font.pixelSize: Style.font.body
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: audioDirField
          Layout.fillWidth: true
          placeholderText: "~/Music"
          foreground: page.fg
          selectByMouse: true
        }

        Button {
          text: "Browse…"
          bordered: true
          focusable: true
          fontSize: Style.font.caption
          foreground: page.fg
          fontFamily: page.fontFamily
          onClicked: page.browse("audio")
        }
      }

      Text {
        width: parent.width
        text: "Video folder"
        color: page.fg
        font.family: page.fontFamily
        font.pixelSize: Style.font.body
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: videoDirField
          Layout.fillWidth: true
          placeholderText: "~/Videos"
          foreground: page.fg
          selectByMouse: true
        }

        Button {
          text: "Browse…"
          bordered: true
          focusable: true
          fontSize: Style.font.caption
          foreground: page.fg
          fontFamily: page.fontFamily
          onClicked: page.browse("video")
        }
      }

      Text {
        width: parent.width
        text: "Extra folder shortcuts"
        color: page.fg
        font.family: page.fontFamily
        font.pixelSize: Style.font.body
      }

      TextField {
        id: favoritesField
        width: parent.width
        placeholderText: "~/Music/Albums, ~/Videos/Clips"
        foreground: page.fg
        selectByMouse: true
      }

      Text {
        width: parent.width
        text: "Comma-separated. They appear as one-click buttons under the folder field."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      PanelSeparator { width: parent.width; foreground: page.fg }

      PanelSectionHeader {
        text: "OUTPUT"
        foreground: page.fg
        fontFamily: page.fontFamily
      }

      Text {
        width: parent.width
        text: "File name template"
        color: page.fg
        font.family: page.fontFamily
        font.pixelSize: Style.font.body
      }

      TextField {
        id: templateField
        width: parent.width
        placeholderText: "%(title)s.%(ext)s"
        foreground: page.fg
        selectByMouse: true
      }

      Text {
        width: parent.width
        text: "yt-dlp output template. Keep %(ext)s so the container extension is correct."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      SettingsToggle {
        label: "Download playlists"
        description: "Off means a playlist link downloads only the selected video."
        checked: page.playlists
        foreground: page.fg
        fontFamily: page.fontFamily
        onToggled: page.playlists = !page.playlists
      }

      SettingsToggle {
        label: "Write metadata tags"
        description: "Title, artist, date and other tags from the source."
        checked: page.embedMetadata
        foreground: page.fg
        fontFamily: page.fontFamily
        onToggled: page.embedMetadata = !page.embedMetadata
      }

      SettingsToggle {
        label: "Embed cover art"
        description: "MP3 and M4A use ffmpeg. Opus and FLAC need the python-mutagen package; without it they download without art."
        checked: page.embedThumbnail
        foreground: page.fg
        fontFamily: page.fontFamily
        onToggled: page.embedThumbnail = !page.embedThumbnail
      }

      Text {
        width: parent.width
        text: "Cookies from browser"
        color: page.fg
        font.family: page.fontFamily
        font.pixelSize: Style.font.body
      }

      Dropdown {
        id: cookiesDrop
        width: parent.width
        value: "none"
        options: [
          { value: "none", label: "Don't use cookies" },
          { value: "chromium", label: "Chromium" },
          { value: "chrome", label: "Google Chrome" },
          { value: "brave", label: "Brave" },
          { value: "firefox", label: "Firefox" },
          { value: "edge", label: "Microsoft Edge" }
        ]
        foreground: page.fg
        accent: page.accent
        fontFamily: page.fontFamily
      }

      Text {
        width: parent.width
        text: "Useful for age-restricted or members-only links. The browser must be installed; close it if yt-dlp cannot read its cookie database."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      PanelSeparator { width: parent.width; foreground: page.fg }

      PanelSectionHeader {
        text: "BEHAVIOUR"
        foreground: page.fg
        fontFamily: page.fontFamily
      }

      SettingsToggle {
        label: "Desktop notifications"
        description: "Notify when a download completes or fails."
        checked: page.notifications
        foreground: page.fg
        fontFamily: page.fontFamily
        onToggled: page.notifications = !page.notifications
      }

      SettingsToggle {
        label: "Paste clipboard link on open"
        description: "Prefill an empty link field with a URL already on the clipboard."
        checked: page.autoPaste
        foreground: page.fg
        fontFamily: page.fontFamily
        onToggled: page.autoPaste = !page.autoPaste
      }

      PanelSeparator { width: parent.width; foreground: page.fg }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Button {
          text: "Cancel"
          bordered: true
          focusable: true
          foreground: page.fg
          fontFamily: page.fontFamily
          onClicked: page.closeRequested()
        }

        Item { Layout.fillWidth: true }

        Button {
          text: "Apply"
          iconText: "󰄬"
          bordered: true
          focusable: true
          foreground: page.fg
          fontFamily: page.fontFamily
          onClicked: page.apply(page.collect())
        }
      }
    }
  }
}
