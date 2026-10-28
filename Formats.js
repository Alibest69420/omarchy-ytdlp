.pragma library

// Format catalogue and display helpers shared by the panel, the popup and the
// settings page. Audio formats are downloaded with yt-dlp -x, video formats
// with yt-dlp's best video + best audio selectors.

var AUDIO_FORMATS = [
  { value: "opus", label: "Opus" },
  { value: "mp3", label: "MP3" },
  { value: "flac", label: "FLAC" },
  { value: "m4a", label: "M4A (AAC)" },
  { value: "wav", label: "WAV" }
]

var VIDEO_FORMATS = [
  { value: "mp4", label: "MP4" },
  { value: "mkv", label: "MKV" },
  { value: "webm", label: "WebM" }
]

var SHORT_LABELS = {
  opus: "OPUS",
  mp3: "MP3",
  flac: "FLAC",
  m4a: "M4A",
  wav: "WAV",
  mp4: "MP4",
  mkv: "MKV",
  webm: "WEBM"
}

function allFormats() {
  return AUDIO_FORMATS.concat(VIDEO_FORMATS)
}

function formatEntry(format) {
  var all = allFormats()
  for (var i = 0; i < all.length; i++)
    if (all[i].value === format) return all[i]
  return all[0]
}

function hasFormat(format) {
  return allFormats().some(function(entry) { return entry.value === format })
}

function formatLabel(format) {
  return formatEntry(format).label
}

function shortLabel(format) {
  return SHORT_LABELS[String(format)] || String(format || "").toUpperCase()
}

function isVideo(format) {
  return VIDEO_FORMATS.some(function(entry) { return entry.value === format })
}

function isAudio(format) {
  return !isVideo(format)
}

function isLosslessContainer(format) {
  return format === "flac" || format === "wav"
}

function qualityOptions(format) {
  if (isVideo(format)) {
    return [
      { value: "best", label: "Best available" },
      { value: "2160", label: "2160p (4K)" },
      { value: "1440", label: "1440p" },
      { value: "1080", label: "1080p" },
      { value: "720", label: "720p" },
      { value: "480", label: "480p" },
      { value: "360", label: "360p" }
    ]
  }
  if (format === "flac") return [{ value: "best", label: "Lossless FLAC" }]
  if (format === "wav") return [{ value: "best", label: "Lossless PCM" }]
  if (format === "mp3") {
    return [
      { value: "best", label: "Best (V0 VBR)" },
      { value: "320K", label: "320 kbps" },
      { value: "256K", label: "256 kbps" },
      { value: "192K", label: "192 kbps" },
      { value: "128K", label: "128 kbps" },
      { value: "96K", label: "96 kbps" }
    ]
  }
  if (format === "m4a") {
    return [
      { value: "best", label: "Best (source AAC)" },
      { value: "256K", label: "256 kbps" },
      { value: "192K", label: "192 kbps" },
      { value: "128K", label: "128 kbps" },
      { value: "96K", label: "96 kbps" }
    ]
  }
  // opus
  return [
    { value: "best", label: "Best available" },
    { value: "192K", label: "192 kbps" },
    { value: "160K", label: "160 kbps" },
    { value: "128K", label: "128 kbps" },
    { value: "96K", label: "96 kbps" },
    { value: "64K", label: "64 kbps" }
  ]
}

function qualityLabel(format, quality) {
  var options = qualityOptions(format)
  for (var i = 0; i < options.length; i++)
    if (options[i].value === quality) return options[i].label
  return quality === "best" ? "Best" : String(quality)
}

function hasQuality(format, quality) {
  return qualityOptions(format).some(function(option) { return option.value === quality })
}

function defaultDir(format, audioDir, videoDir) {
  return isVideo(format) ? videoDir : audioDir
}

function bytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return ""
  var units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return (i === 0 ? Math.round(n) : n.toFixed(n >= 100 ? 0 : 1)) + " " + units[i]
}

function speed(value) {
  var text = bytes(value)
  return text === "" ? "" : text + "/s"
}

function eta(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return ""
  n = Math.round(n)
  var hours = Math.floor(n / 3600)
  var minutes = Math.floor((n % 3600) / 60)
  var seconds = n % 60
  function pad(number) { return number < 10 ? "0" + number : String(number) }
  if (hours > 0) return hours + ":" + pad(minutes) + ":" + pad(seconds)
  return minutes + ":" + pad(seconds)
}
