# yt-dlp Downloads for Omarchy

A bar widget for [Omarchy](https://omarchy.org/) that downloads audio and video
with `yt-dlp` without leaving the desktop.

- Audio: **Opus** (default), MP3, FLAC, M4A (AAC), WAV
- Video: MP4, MKV, WebM
- Best-available quality by default; lower bitrates and resolution caps per download
- Separate default folders for audio and video, editable per download, with a
  native folder picker and one-click shortcuts for extra folders
- One-at-a-time queue that keeps running when the popup closes; the bar shows
  live progress and the queue has cancel/retry/open-folder actions
- Clipboard prefill, native completion notifications, metadata and cover art
- Playlist downloads, browser-cookie support, and a configurable filename template

## Requirements

- Omarchy 4.x (the Quickshell shell with the plugin system)
- `yt-dlp` and `ffmpeg` (both are present on a stock Omarchy install)
- `python-mutagen` for cover art on Opus/FLAC (MP3/M4A cover art works
  without it)
- `zenity` for the folder picker (stock Omarchy install)
- `wl-paste` for clipboard prefill (stock Omarchy install)

Check the shell can see both download tools:

```bash
yt-dlp --version
ffmpeg -version
```

## Install

Install from GitHub:

```bash
omarchy plugin add https://github.com/Alibest69420/omarchy-ytdlp.git --enable
```

Or install a local checkout by copying this directory to
`~/.config/omarchy/plugins/ddrglazer.ytdlp/`, then:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable ddrglazer.ytdlp
```

It lands in the left side of the bar by default. Move it with:

```bash
omarchy bar move ddrglazer.ytdlp --section right --index 4
```

### Choose placement during install

Omarchy's own installer only clones and enables a plugin; it does not run
repository install hooks. This repo includes a small wrapper that asks where
the widget should go:

```bash
git clone https://github.com/Alibest69420/omarchy-ytdlp.git
cd omarchy-ytdlp
./install.sh
```

It offers **left**, **right**, or **center** (default: left). For unattended
installs:

```bash
./install.sh right
```

If the plugin is already installed, run the copy inside the plugin folder:

```bash
~/.config/omarchy/plugins/ddrglazer.ytdlp/install.sh center
```

The wrapper uses the normal `omarchy plugin add` and `omarchy bar move`
commands and leaves saved settings untouched.

## Remove

```bash
omarchy plugin disable ddrglazer.ytdlp
omarchy plugin remove ddrglazer.ytdlp --yes
```

`disable` takes it off the bar; `remove` deletes the plugin folder. Saved
settings remain in `~/.config/omarchy/shell.json`; delete the
`ddrglazer.ytdlp` entry there if you want to clear them too.

## Safety

This plugin runs unsandboxed inside `omarchy-shell`, like every Omarchy shell
plugin. It:

- writes only its own inline entry in `~/.config/omarchy/shell.json`, and only
  when you press **Apply** in settings
- writes downloads only to folders you choose
- never requests elevated privileges and does not modify system configuration
- invokes `yt-dlp`, `ffmpeg`, `zenity`, `wl-paste`, `xdg-open`, `stat`, and
  `omarchy-notification-send`

`yt-dlp` downloads from the URLs you paste, so normal network access applies.

## Use

- **Left-click** the bar icon to open the downloader.
- **Right-click** to open settings.
- **Middle-click** to open the last completed download folder.
- Paste a link, choose format, quality and folder, press **Enter** or
  **Download**. Multiple links can be pasted separated by spaces or commas.
- The popup can be closed while a download runs; progress stays in the bar.
- Click the gear, or right-click the bar icon, for defaults, folders, cookies
  and output options.

## Quality notes

- **Opus "best"** re-encodes at 192 kbps only when the source is not already
  Opus; yt-dlp copies a matching source stream instead of re-encoding it.
  Cover art for Opus and FLAC needs `python-mutagen`; without it the plugin
  skips the cover instead of failing the download.
- **MP3 "best"** uses V0 VBR (roughly 245 kbps). Choosing 320/256/192/128/96
  kbps forces a CBR transcode.
- **M4A "best"** keeps a matching AAC source; otherwise it re-encodes at the
  best setting. Lower bitrates are available.
- **FLAC and WAV** are lossless containers, but sources are usually lossy. The
  conversion preserves what the source has; it cannot restore detail. The
  popup says this when either is selected.
- **Video** downloads the best video and best audio streams with yt-dlp, capped
  at the resolution you choose. MP4 prefers MP4/AAC streams and merges to MP4;
  WebM stays WebM; MKV accepts the best available streams.

## Settings

The settings page writes plain values into this widget's inline entry in
`~/.config/omarchy/shell.json`. Defaults:

| Key | Default | Meaning |
| --- | --- | --- |
| `barIconSize` | `16` | Bar glyph size in pixels (12–22) |
| `defaultFormat` | `opus` | Format for new downloads |
| `defaultQuality` | `best` | Quality for new downloads |
| `audioDir` | `~/Music` | Default audio folder |
| `videoDir` | `~/Videos` | Default video folder |
| `favorites` | empty | Comma-separated extra folder shortcuts |
| `filenameTemplate` | `%(title)s.%(ext)s` | yt-dlp output template |
| `cookiesBrowser` | `none` | `chromium`, `chrome`, `brave`, `firefox`, or `edge` |
| `playlists` | `false` | Download full playlists |
| `embedMetadata` | `true` | Write tags |
| `embedThumbnail` | `true` | Embed cover art in audio |
| `notifications` | `true` | Desktop notification on finish/failure |
| `autoPaste` | `true` | Prefill an empty field from the clipboard |

## IPC

The plugin exposes a `ddrglazer.ytdlp` IPC target:

Bar widgets register their own IPC target, so call it directly rather than
through the shell target:

```bash
# Open the popup
quickshell ipc -p /usr/share/omarchy/shell call ddrglazer.ytdlp open

# Download a URL with current defaults
quickshell ipc -p /usr/share/omarchy/shell call ddrglazer.ytdlp download "https://example.com/video"

# Full control (JSON string)
quickshell ipc -p /usr/share/omarchy/shell call ddrglazer.ytdlp enqueue \
  '{"urls":["https://example.com/video"],"format":"flac","quality":"best","dir":"~/Music/Lossless"}'

# Queue state as JSON
quickshell ipc -p /usr/share/omarchy/shell call ddrglazer.ytdlp status
```

Queue state is in memory: restarting the shell (`omarchy restart shell`) stops
active downloads and clears the queue. Finished files stay in their folders.

## Files

```
manifest.json      Plugin metadata and defaults
Panel.qml          Bar widget, popup lifecycle, notifications, IPC
DownloadEngine.qml Sequential yt-dlp queue, progress parsing
install.sh         Installer wrapper with bar placement prompt
Card.qml           Download popup
JobRow.qml         One queue row
Settings.qml       Settings page
SettingsToggle.qml Small labeled switch used by settings
Formats.js         Format/quality catalogue and display helpers
```

## License

MIT. See [LICENSE](LICENSE).
