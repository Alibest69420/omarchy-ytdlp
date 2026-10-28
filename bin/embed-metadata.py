#!/usr/bin/env python3
"""Apply yt-dlp metadata without putting private values in a process argv.

Called with:
    embed-metadata.py <private-dir> <output-dir> [media-file-hint]

yt-dlp writes .info.json files into <private-dir> (a 0700 tmpfs directory),
and thumbnails are written there too. This helper reads the JSON, writes tags
with mutagen (Opus) or an ffmpeg ffmetadata file (other containers), then
overwrites and removes every temporary metadata file before exiting.

The title/artist/etc. never appear in a child process command line: the
ffmpeg command only receives paths, and the ffmetadata file lives inside the
private tmpfs directory with mode 0600.
"""
from __future__ import annotations

import json
import os
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

def log(message: str) -> None:
    print(f"embed-metadata: {message}", file=sys.stderr)

def first(info: dict, keys: tuple[str, ...]) -> str:
    for key in keys:
        value = info.get(key)
        if isinstance(value, (list, tuple)):
            value = value[0] if value else None
        if isinstance(value, dict):
            continue
        if value not in (None, ""):
            return str(value)
    return ""

def tags_from(info: dict) -> dict[str, str]:
    date = first(info, ("upload_date", "release_date"))
    if len(date) == 8 and date.isdigit():
        date = f"{date[0:4]}-{date[4:6]}-{date[6:8]}"
    tags = {
        "title": first(info, ("track", "title")),
        "artist": first(info, ("artist", "artists", "creator", "uploader", "channel")),
        "album": first(info, ("album", "series")),
        "date": date,
        "tracknumber": first(info, ("track_number",)),
        "genre": first(info, ("genre", "categories", "tags")),
        "comment": first(info, ("webpage_url",)),
    }
    return {key: value for key, value in tags.items() if value}

def shred(path: Path) -> None:
    """Overwrite a small metadata file before unlinking it."""
    try:
        size = path.stat().st_size
        with path.open("r+b", buffering=0) as handle:
            handle.write(b"\0" * size)
            handle.flush()
            os.fsync(handle.fileno())
    except (FileNotFoundError, OSError):
        pass
    try:
        path.unlink()
    except FileNotFoundError:
        pass

def ff_escape(value: str) -> str:
    return "".join("\\" + char if char in "\\=;#\n" else char for char in value)

def write_ffmeta(path: Path, tags: dict[str, str]) -> None:
    lines = [";FFMETADATA1"]
    for key, value in tags.items():
        if value:
            lines.append(f"{key}={ff_escape(value)}")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

def apply_ffmpeg(media: Path, tags: dict[str, str], workdir: Path) -> None:
    metadata = workdir / f"meta-{secrets.token_hex(6)}.ffmeta"
    temporary = media.with_name(
        f"{media.stem}.tagtmp-{secrets.token_hex(6)}{media.suffix}"
    )
    write_ffmeta(metadata, tags)
    try:
        result = subprocess.run(
            [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", str(media),
                "-i", str(metadata),
                "-map", "0",
                "-map_chapters", "0",
                "-map_metadata", "1",
                "-c", "copy",
                str(temporary),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError("ffmpeg could not write the tags")
        os.replace(temporary, media)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        shred(metadata)

def apply_opus(media: Path, tags: dict[str, str]) -> None:
    from mutagen.oggopus import OggOpus

    audio = OggOpus(str(media))
    for key, value in tags.items():
        if value:
            audio[key] = value
    audio.save()

def find_media(info: dict, outdir: Path, hint: Path | None, unique: bool) -> Path | None:
    if unique and hint is not None and hint.is_file():
        return hint
    media_id = str(info.get("id") or "")
    if not media_id:
        return None
    candidates = [
        path for path in outdir.glob(f"{media_id}.*")
        if path.is_file()
        and not path.name.endswith(".info.json")
        and not path.name.endswith(".part")
        and path.suffix not in (".json", ".jpg", ".jpeg", ".png", ".webp")
    ]
    return candidates[0] if candidates else None

def main() -> int:
    if len(sys.argv) not in (3, 4):
        log("usage: embed-metadata.py <private-dir> <output-dir> [media-hint]")
        return 2

    workdir = Path(sys.argv[1])
    outdir = Path(sys.argv[2])
    hint = Path(sys.argv[3]) if len(sys.argv) == 4 and sys.argv[3] else None
    if not workdir.is_dir():
        log("private metadata directory is missing")
        return 1

    infos = sorted(workdir.glob("*.info.json"))
    unique = len(infos) == 1
    failures = 0

    for info_path in infos:
        try:
            info = json.loads(info_path.read_text(encoding="utf-8"))
        except Exception:
            log("could not read a metadata file")
            failures += 1
            shred(info_path)
            continue

        media = find_media(info, outdir, hint, unique)
        if media is None:
            log("could not match a media file to its metadata")
            failures += 1
            shred(info_path)
            continue

        tags = tags_from(info)
        try:
            if media.suffix.lower() == ".opus":
                try:
                    apply_opus(media, tags)
                except ImportError:
                    # Without mutagen there is no Opus cover-art stream to
                    # preserve, so the ffmpeg path can write the text tags.
                    apply_ffmpeg(media, tags, workdir)
            else:
                apply_ffmpeg(media, tags, workdir)
        except Exception as error:
            # Deliberately do not include the title, URL or tag values here.
            message = "tagging failed"
            if isinstance(error, ImportError):
                message = "opus tagging needs python-mutagen"
            log(message)
            failures += 1
        finally:
            shred(info_path)

    # Thumbnails are normally removed by yt-dlp after embedding. If one was
    # left behind, remove it before removing the private directory.
    for path in workdir.iterdir():
        if path.is_file():
            shred(path)
    try:
        workdir.rmdir()
    except OSError:
        shutil.rmtree(workdir, ignore_errors=True)

    return 1 if failures else 0

if __name__ == "__main__":
    sys.exit(main())
