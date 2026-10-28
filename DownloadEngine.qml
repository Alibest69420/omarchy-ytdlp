import QtQuick
import Quickshell
import Quickshell.Io
import "Formats.js" as Formats

// The download queue. One yt-dlp process at a time; everything else waits in
// `jobs`. Progress and the final file path come from yt-dlp's --print and
// --progress-template output, so no scraping of human-readable log lines is
// needed.
//
// An Item rather than a QtObject: QtObject has no default child property, and
// Process/Timer need to be declared as children.
Item {
  id: engine

  visible: false
  width: 0
  height: 0

  property var settings: ({})
  property bool mutagenOk: false
  property var jobs: []
  property int activeJobId: -1
  property int nextId: 1
  property bool cancelRequested: false
  property string stderrText: ""
  property string lastStderr: ""
  property var lastCommand: []
  property int statJobId: -1
  property bool _dirty: false

  signal changed()
  signal finished(var job)
  signal started(var job)

  readonly property var currentJob: jobById(activeJobId)
  readonly property bool busy: activeJobId >= 0
  readonly property real progress: currentJob ? Math.max(0, Math.min(100, Number(currentJob.progress) || 0)) : 0
  readonly property int queuedCount: countStatus("queued")
  readonly property int doneCount: countStatus("done")
  readonly property int errorCount: countStatus("error")
  readonly property int finishedCount: doneCount + errorCount + countStatus("cancelled")

  readonly property var options: ({
    playlists: setting("playlists", false),
    cookies: String(setting("cookiesBrowser", "none")),
    template: String(setting("filenameTemplate", "%(title)s.%(ext)s")),
    embedMetadata: setting("embedMetadata", true),
    embedThumbnail: setting("embedThumbnail", true)
  })

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
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

  function jobById(id) {
    if (id === undefined || id === null || id < 0) return null
    for (var i = 0; i < jobs.length; i++)
      if (jobs[i].id === id) return jobs[i]
    return null
  }

  function indexOf(id) {
    for (var i = 0; i < jobs.length; i++)
      if (jobs[i].id === id) return i
    return -1
  }

  function countStatus(status) {
    var total = 0
    for (var i = 0; i < jobs.length; i++)
      if (jobs[i].status === status) total++
    return total
  }

  function notifyNow() {
    _dirty = false
    jobs = jobs.slice()
    changed()
  }

  function notifySoon() {
    if (_dirty) return
    _dirty = true
    notifyTimer.restart()
  }

  Timer {
    id: notifyTimer
    interval: 220
    repeat: false
    onTriggered: if (engine._dirty) engine.notifyNow()
  }

  function enqueue(urls, format, quality, directory) {
    var list = urls || []
    if (list.length === 0) return
    if (!Formats.hasFormat(format)) format = "opus"
    if (!Formats.hasQuality(format, quality)) quality = "best"
    for (var i = 0; i < list.length; i++) {
      var url = String(list[i] || "").trim()
      if (url === "") continue
      jobs.push({
        id: nextId++,
        url: url,
        title: url,
        format: format,
        quality: quality,
        dir: directory,
        status: "queued",
        progress: 0,
        downloaded: 0,
        total: 0,
        speed: 0,
        eta: -1,
        filepath: "",
        error: "",
        playlists: Boolean(options.playlists),
        cookies: String(options.cookies),
        template: String(options.template),
        embedMetadata: Boolean(options.embedMetadata),
        embedThumbnail: Boolean(options.embedThumbnail)
      })
    }
    notifyNow()
    pump()
  }

  function pump() {
    if (activeJobId >= 0) return
    var next = null
    for (var i = 0; i < jobs.length; i++) {
      if (jobs[i].status === "queued") { next = jobs[i]; break }
    }
    if (!next) return

    activeJobId = next.id
    cancelRequested = false
    stderrText = ""
    next.status = "starting"
    next.progress = 0
    next.speed = 0
    next.eta = -1
    next.error = ""
    notifyNow()
    started(next)

    var command = buildCommand(next)
    lastCommand = command
    proc.command = command
    proc.running = true
  }

  function isAudioFormat(format) {
    return !Formats.isVideo(format)
  }

  function buildCommand(job) {
    var args = [
      "yt-dlp",
      "--newline",
      "--no-colors",
      "--progress",
      "--progress-delta", "1",
      "--no-simulate",
      "--print", "before_dl:OMARCHY_TITLE:%(title)s",
      "--print", "after_move:OMARCHY_FILE:%(filepath)s",
      "--progress-template",
      "download:OMARCHY_DL:%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(progress._percent_str)s"
    ]

    args.push(job.playlists ? "--yes-playlist" : "--no-playlist")
    if (job.cookies && job.cookies !== "none") args.push("--cookies-from-browser", job.cookies)
    args.push("-P", expandPath(job.dir))
    args.push("-o", job.template || "%(title)s.%(ext)s")

    var format = job.format
    if (Formats.isVideo(format)) {
      var cap = job.quality === "best" ? "" : "[height<=" + String(job.quality) + "]"
      var selector
      if (format === "mp4") {
        selector = "bv*" + cap + "[ext=mp4]+ba[ext=m4a]/b" + cap + "[ext=mp4]/bv*" + cap + "+ba/b" + cap
        args.push("--merge-output-format", "mp4")
      } else if (format === "webm") {
        selector = "bv*" + cap + "[ext=webm]+ba[ext=webm]/b" + cap + "[ext=webm]"
        args.push("--merge-output-format", "webm")
      } else {
        selector = "bv*" + cap + "+ba/b" + cap
        args.push("--merge-output-format", "mkv")
      }
      args.push("-f", selector)
    } else {
      args.push("-f", "bestaudio/best")
      args.push("-x")
      args.push("--audio-format", format)
      if (!Formats.isLosslessContainer(format)) {
        // 0 is the best VBR setting for MP3; explicit bitrates otherwise.
        if (String(job.quality) === "best")
          args.push("--audio-quality", format === "opus" ? "192K" : "0")
        else
          args.push("--audio-quality", String(job.quality))
      }
      if (job.embedThumbnail) {
        // Opus and FLAC cover art is written with mutagen; MP3/M4A use ffmpeg.
        // WAV has no tag chunk for art. Skip unsupported cases so the download
        // still completes instead of failing in postprocessing.
        var needsMutagen = format === "opus" || format === "flac"
        var supportsThumbnail = format === "mp3" || format === "m4a" || needsMutagen
        if (supportsThumbnail && (!needsMutagen || engine.mutagenOk)) {
          args.push("--embed-thumbnail")
          args.push("--convert-thumbnails", "jpg")
        }
      }
    }

    if (job.embedMetadata) args.push("--embed-metadata")
    args.push(job.url)
    return args
  }

  function handleLine(line) {
    var job = currentJob
    if (!job) return
    var text = String(line || "").trim()
    if (text === "") return

    if (text.indexOf("OMARCHY_TITLE:") === 0) {
      var title = text.slice("OMARCHY_TITLE:".length).trim()
      if (title !== "") job.title = title
      notifySoon()
      return
    }

    if (text.indexOf("OMARCHY_FILE:") === 0) {
      job.filepath = text.slice("OMARCHY_FILE:".length).trim()
      job.progress = 100
      job.status = "processing"
      notifySoon()
      return
    }

    if (text.indexOf("OMARCHY_DL:") === 0) {
      var parts = text.slice("OMARCHY_DL:".length).split("|")
      var downloaded = number(parts[0])
      var total = number(parts[1])
      if (!(total > 0)) total = number(parts[2])
      var speed = number(parts[3])
      var eta = number(parts[4])
      var percent = parseFloat(String(parts[5] || "").replace("%", ""))

      job.downloaded = downloaded > 0 ? downloaded : 0
      job.total = total > 0 ? total : 0
      job.speed = speed > 0 ? speed : 0
      job.eta = eta >= 0 ? eta : -1
      if (job.total > 0) job.progress = Math.min(100, (job.downloaded / job.total) * 100)
      else if (isFinite(percent)) job.progress = Math.min(100, percent)
      job.status = job.progress >= 99.9 ? "processing" : "downloading"
      notifySoon()
    }
  }

  function number(value) {
    var n = parseFloat(String(value === undefined || value === null ? "" : value))
    return isFinite(n) ? n : -1
  }

  function lastError(text) {
    var lines = String(text || "").split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line.indexOf("ERROR:") === 0) return line.replace(/^ERROR:\s*/, "")
    }
    for (var j = lines.length - 1; j >= 0; j--) {
      var candidate = lines[j].trim()
      if (candidate === "" || candidate.indexOf("Type yt-dlp") === 0 || candidate.indexOf("Usage:") === 0) continue
      var lower = candidate.toLowerCase()
      if (lower.indexOf("error:") >= 0) return candidate.replace(/^.*?error:\s*/i, "")
    }
    for (var k = lines.length - 1; k >= 0; k--)
      if (lines[k].trim() !== "") return lines[k].trim()
    return ""
  }

  function handleExit(exitCode) {
    var job = currentJob
    if (!job) {
      activeJobId = -1
      pump()
      return
    }

    var cancelled = cancelRequested || job.status === "cancelling"
    cancelRequested = false
    job.speed = 0
    job.eta = -1

    if (cancelled) {
      job.status = "cancelled"
      job.progress = 0
    } else if (exitCode === 0) {
      job.status = "done"
      job.progress = 100
      if (job.filepath) {
        statJobId = job.id
        statProc.command = ["stat", "-c", "%s", "--", job.filepath]
        statProc.running = true
      } else if (!(job.total > 0)) {
        job.total = job.downloaded
      }
    } else {
      job.status = "error"
      job.error = lastError(stderrText) || ("yt-dlp exited with code " + exitCode)
      lastStderr = String(stderrText || "")
    }

    activeJobId = -1
    notifyNow()
    if (job.status === "done" || job.status === "error") finished(job)
    pump()
  }

  function cancel(id) {
    var index = indexOf(id)
    if (index < 0) return
    var job = jobs[index]
    if (job.status === "queued") {
      job.status = "cancelled"
      notifyNow()
      return
    }
    if (job.id !== activeJobId) return
    cancelRequested = true
    job.status = "cancelling"
    notifyNow()
    if (proc.running) proc.running = false
    else handleExit(130)
  }

  function retry(id) {
    var job = jobById(id)
    if (!job) return
    if (job.status !== "error" && job.status !== "cancelled") return
    job.status = "queued"
    job.progress = 0
    job.downloaded = 0
    job.total = 0
    job.speed = 0
    job.eta = -1
    job.error = ""
    job.filepath = ""
    notifyNow()
    pump()
  }

  function clearFinished() {
    var kept = []
    for (var i = 0; i < jobs.length; i++) {
      var status = jobs[i].status
      if (status === "done" || status === "error" || status === "cancelled") continue
      kept.push(jobs[i])
    }
    jobs = kept
    notifyNow()
  }

  // The download size is not the final file size after audio conversion, so
  // replace it with the on-disk size once the file has moved into place.
  Process {
    id: statProc
    command: []
    stdout: StdioCollector {
      id: statCollector
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && engine.statJobId >= 0) {
        var job = engine.jobById(engine.statJobId)
        var size = parseFloat(String(statCollector.text || "").trim())
        if (job && isFinite(size) && size > 0) {
          job.total = size
          engine.notifyNow()
        }
      }
      engine.statJobId = -1
    }
  }

  Process {
    id: proc
    command: []

    stdout: SplitParser {
      onRead: function(line) { engine.handleLine(String(line)) }
    }

    stderr: StdioCollector {
      id: stderrCollector
      waitForEnd: true
      onStreamFinished: engine.stderrText = text
    }

    onExited: function(exitCode, exitStatus) {
      if (engine.stderrText === "" && stderrCollector.text !== "")
        engine.stderrText = stderrCollector.text
      engine.handleExit(exitCode)
    }
  }
}
