import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Formats.js" as Formats

// yt-dlp downloader for the Omarchy bar.
//
// The bar widget owns the queue: it lives for the whole shell session, so
// closing the popup (or switching panels) does not interrupt a download. The
// popup is only a view onto DownloadEngine.qml.
Panel {
  id: root

  moduleName: "ddrglazer.ytdlp"
  ipcTarget: "ddrglazer.ytdlp"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool settingsOpen: false
  property bool toolsOk: true
  property bool mutagenOk: false
  property string toolError: ""
  property string lastSubmittedUrl: ""
  property string lastCompletedDir: ""

  readonly property var engine: downloadEngine
  readonly property string barText: {
    if (engine.currentJob) {
      var percent = Math.round(engine.progress)
      if (bar && bar.vertical) return "󰇚"
      return percent > 0 ? "󰇚 " + percent + "%" : "󰇚"
    }
    if (engine.queuedCount > 0) return "󰇚 " + engine.queuedCount
    return "󰇚"
  }

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function home() {
    return Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "")
  }

  function expandPath(path) {
    var value = String(path || "").trim()
    if (value === "") return home() + "/Downloads"
    if (value === "~") return home()
    if (value.indexOf("~/") === 0) return home() + value.slice(1)
    return value
  }

  function shortPath(path) {
    var value = String(path || "")
    var homePath = home()
    if (value === homePath) return "~"
    if (value.indexOf(homePath + "/") === 0) value = value.slice(homePath.length)
    var parts = value.split("/").filter(function(part) { return part !== "" })
    return parts.length > 0 ? parts[parts.length - 1] : value
  }

  function favoriteDirs() {
    var raw = String(setting("favorites", ""))
    var parts = raw.split(/[\n,]+/)
    var result = []
    for (var i = 0; i < parts.length; i++) {
      var dir = parts[i].trim()
      if (dir !== "" && result.indexOf(dir) < 0) result.push(dir)
    }
    return result
  }

  function startDownload(urls, format, quality, directory) {
    if (!toolsOk) return false
    var dir = String(directory || "").trim()
    if (dir === "") return false
    engine.enqueue(urls, format, quality, dir)
    if (urls && urls.length > 0) lastSubmittedUrl = String(urls[urls.length - 1])
    return true
  }

  function openDir(directory) {
    var dir = String(directory || "").trim()
    if (dir === "") return
    Quickshell.execDetached(["xdg-open", expandPath(dir)])
  }

  function jobStatusLine(job) {
    if (!job) return ""
    var format = Formats.shortLabel(job.format) + " · " + Formats.qualityLabel(job.format, job.quality)
    if (job.status === "queued") return "Queued · " + format
    if (job.status === "starting") return "Fetching info…"
    if (job.status === "downloading") {
      var line = Math.round(Number(job.progress) || 0) + "%"
      if (job.speed > 0) line += " · " + Formats.speed(job.speed)
      if (job.eta >= 0) line += " · ETA " + Formats.eta(job.eta)
      return line + " · " + format
    }
    if (job.status === "processing") return "Finishing · " + format
    if (job.status === "done") {
      var size = Formats.bytes(job.total)
      return "Done" + (size !== "" ? " · " + size : "") + " · " + format
    }
    if (job.status === "cancelling") return "Cancelling…"
    if (job.status === "cancelled") return "Cancelled · " + format
    if (job.status === "error") return job.error || "Download failed"
    return format
  }

  function statusColor(job) {
    if (!job) return dim
    if (job.status === "error") return urgent
    if (job.status === "done") return accent
    return dim
  }

  function statusIcon(job) {
    if (!job) return "󰇚"
    if (job.status === "done") return "󰄬"
    if (job.status === "error") return "󰅚"
    if (job.status === "cancelled") return "󰅖"
    if (job.status === "processing") return "󰔄"
    if (job.status === "queued") return "󰇚"
    return "󰇚"
  }

  function tooltipText() {
    if (!toolsOk) return "yt-dlp and ffmpeg are required"
    var job = engine.currentJob
    if (job) {
      return "Downloading " + Math.round(engine.progress) + "%\n" + (job.title || job.url)
    }
    if (engine.queuedCount > 0)
      return engine.queuedCount + (engine.queuedCount === 1 ? " download queued" : " downloads queued")
    if (engine.errorCount > 0)
      return engine.errorCount + (engine.errorCount === 1 ? " failed download" : " failed downloads")
    return "yt-dlp downloads\nClick to open"
  }

  function showSettings() {
    settingsPage.begin()
    settingsOpen = true
    if (!opened) open()
    Qt.callLater(function() {
      if (root.opened) settingsPage.firstField.forceActiveFocus()
    })
  }

  function hideSettings() {
    settingsOpen = false
    Qt.callLater(function() {
      if (root.opened) card.inputField.forceActiveFocus()
    })
  }

  function persistSettings(values) {
    var merged = {}
    if (root.settings) for (var key in root.settings) merged[key] = root.settings[key]
    for (var incoming in values) merged[incoming] = values[incoming]
    merged.id = moduleName
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, merged)
    else
      settings = merged
  }

  onOpenedChanged: {
    if (opened) {
      Qt.callLater(function() {
        if (root.opened && !root.settingsOpen) card.maybeAutoPaste()
      })
    } else {
      settingsOpen = false
    }
  }

  Component.onCompleted: {
    toolsProc.running = true
    mutagenProc.running = true
  }

  Process {
    id: toolsProc
    command: ["which", "yt-dlp", "ffmpeg"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.toolsOk = exitCode === 0
      root.toolError = exitCode === 0 ? "" : "yt-dlp and ffmpeg are required. Install them with: omarchy pkg add yt-dlp"
    }
  }

  Process {
    id: mutagenProc
    command: ["python3", "-c", "import mutagen"]
    onExited: function(exitCode) { root.mutagenOk = exitCode === 0 }
  }

  DownloadEngine {
    id: downloadEngine
    settings: root.settings
    mutagenOk: root.mutagenOk
  }

  Connections {
    target: downloadEngine
    function onFinished(job) {
      if (job.status !== "done" && job.status !== "error") return
      if (job.status === "done") root.lastCompletedDir = root.expandPath(job.dir)
      if (!root.setting("notifications", true)) return

      var title = job.title && job.title !== job.url ? job.title : job.url
      var done = job.status === "done"
      var headline = done ? "Download complete" : "Download failed"
      var body = done
        ? title + "\nSaved to " + root.expandPath(job.dir)
        : title + "\n" + (job.error || "yt-dlp exited with an error")
      var args = [
        "omarchy-notification-send",
        "-u", done ? "low" : "normal",
        "-g", done ? "󰇚" : "󰅚",
        headline,
        body
      ]
      if (done) {
        args.push("--exec")
        args.push("xdg-open")
        args.push(root.expandPath(job.dir))
      }
      Quickshell.execDetached(args)
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function settings(): void { root.showSettings() }
    function clear(): void { root.engine.clearFinished() }

    function download(url: string): string {
      if (!root.toolsOk) return JSON.stringify({ ok: false, error: "yt-dlp or ffmpeg is missing" })
      var format = String(root.setting("defaultFormat", "opus"))
      var quality = String(root.setting("defaultQuality", "best"))
      var dir = String(Formats.defaultDir(format, root.setting("audioDir", "~/Music"), root.setting("videoDir", "~/Videos")))
      var started = root.startDownload([String(url || "")], format, quality, dir)
      return JSON.stringify({ ok: started, format: format, quality: quality, dir: dir })
    }

    function enqueue(payload: string): string {
      try {
        var request = JSON.parse(String(payload || "{}"))
        var urls = request.urls || (request.url ? [request.url] : [])
        if (!urls || urls.length === 0) return JSON.stringify({ ok: false, error: "No URL supplied" })
        var format = String(request.format || root.setting("defaultFormat", "opus"))
        var quality = String(request.quality || root.setting("defaultQuality", "best"))
        var dir = String(request.dir || Formats.defaultDir(format, root.setting("audioDir", "~/Music"), root.setting("videoDir", "~/Videos")))
        return JSON.stringify({ ok: root.startDownload(urls, format, quality, dir), count: urls.length, format: format, quality: quality, dir: dir })
      } catch (error) {
        return JSON.stringify({ ok: false, error: "Invalid JSON payload" })
      }
    }

    function status(): string {
      return JSON.stringify({
        ok: true,
        toolsOk: root.toolsOk,
        busy: root.engine.busy,
        progress: root.engine.progress,
        queued: root.engine.queuedCount,
        done: root.engine.doneCount,
        errors: root.engine.errorCount,
        mutagenOk: root.mutagenOk,
        lastCommand: root.engine.lastCommand,
        lastStderr: root.engine.lastStderr,
        jobs: root.engine.jobs
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    foreground: root.barForeground
    activeColor: root.accent
    active: root.engine.busy
    fontFamily: root.fontFamily
    fontSize: Style.bar.iconFont
    horizontalMargin: Style.space(7)
    fixedWidth: button.bar && button.bar.vertical ? -1
      : Math.max(Style.bar.iconSlot, (root.engine.currentJob || root.engine.queuedCount > 0)
        ? button.labelWidth + button.scaledHorizontalMargin * 2 : 0)
    fixedHeight: button.bar && button.bar.vertical ? Style.bar.iconSlot : -1
    tooltipText: root.tooltipText()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.showSettings()
      else if (buttonCode === Qt.MiddleButton) root.openDir(root.lastCompletedDir || root.setting("audioDir", "~/Music"))
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.settingsOpen ? settingsPage.firstField : card.inputField
    contentWidth: panel.fittedContentWidth(Style.space(root.settingsOpen ? 500 : 470))
    contentHeight: panel.fittedContentHeight(root.settingsOpen ? settingsPage.implicitHeight : card.bodyHeight)

    Card {
      id: card
      anchors.fill: parent
      panel: root
      visible: !root.settingsOpen
    }

    Settings {
      id: settingsPage
      anchors.fill: parent
      visible: root.settingsOpen
      panel: root
      settings: root.settings
      onApply: function(values) {
        root.persistSettings(values)
        root.hideSettings()
      }
      onCloseRequested: root.hideSettings()
    }
  }
}
