#!/usr/bin/env bash
# Install yt-dlp Downloads and choose which bar section it uses.
set -euo pipefail

ID="ddrglazer.ytdlp"
REPO_URL="https://github.com/Alibest69420/omarchy-ytdlp.git"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID"

usage() {
  cat <<EOF
Usage: $(basename "$0") [left|right|center]

Install the yt-dlp Downloads widget and place it in a bar section.
With no argument, the script asks (default: left).

Options:
  -h, --help             Show this help
  --section SECTION      left, right, or center
EOF
}

die() {
  echo "install.sh: $*" >&2
  exit 1
}

section=""
while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --section|--placement)
      (( $# >= 2 )) || die "missing value for $1"
      section="$2"
      shift 2
      ;;
    --section=*|--placement=*)
      section="${1#*=}"
      shift
      ;;
    left|right|center)
      section="$1"
      shift
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -z "$section" ]]; then
  if [[ -t 0 ]]; then
    while true; do
      read -r -p "Place the yt-dlp widget [left/right/center] (default: left): " answer || answer=""
      answer="${answer:-left}"
      answer="${answer,,}"
      case "$answer" in
        left|right|center)
          section="$answer"
          break
          ;;
        *)
          echo "Please enter left, right, or center."
          ;;
      esac
    done
  else
    section="left"
  fi
fi

section="${section,,}"
case "$section" in
  left|right|center) ;;
  *) die "invalid section '$section' (use left, right, or center)" ;;
esac

command -v omarchy >/dev/null 2>&1 || die "the omarchy command was not found"
command -v omarchy-shell >/dev/null 2>&1 || die "the omarchy-shell command was not found"

if [[ ! -d "$PLUGIN_DIR" ]]; then
  echo "Installing $ID…"
  omarchy plugin add "$REPO_URL" --enable --yes
else
  echo "Plugin is already installed; refreshing it…"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable "$ID" >/dev/null 2>&1 || true
fi

omarchy bar move "$ID" --section "$section"

echo
echo "$ID is now in the $section section."
echo "Right-click the bar icon to open settings."
