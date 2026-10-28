#!/usr/bin/env python3
"""Apply yt-dlp metadata without trusting remote IDs or searching the filesystem.

The caller sends one JSON line on stdin:

    {
      "private_dir": "/run/user/1000/ytdlp-private.XXXXXX",
      "outdir": "/home/user/Music",
      "records": [
        {"file": "/home/user/Music/id.opus", "info": "/run/.../id.info.json"}
      ]
    }

`records` is the exact allowlist produced by the current yt-dlp job. The helper
never uses a remote ID to find a file, never globs for a target, and refuses any
path outside the declared output directory or private directory.

Text tags are written with mutagen (Opus) or a mode-0600 ffmetadata file passed
to ffmpeg (other containers). The ffmetadata file lives in the mode-0700 tmpfs
private directory. After tagging, the helper overwrites and removes the info
JSON, ffmetadata file, leftover thumbnails, and the private directory.
"""
from __future__ import annotations

import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

def log(message: str) -> None:
    print(f"embed-metadata: {message}", file=sys.stderr)

def absolute(raw: object, label: str) -> Path:
    if not isinstance(raw, str) or raw == "":
        raise ValueError(f"missing {label}")
    path = Path(raw)
    if not path.is_absolute():
        raise ValueError(f"{label} must be absolute")
    return Path(os.path.abspath(path))

def safe_file(raw: object, root_lexical: Path, root_resolved: Path, label: str) -> Path:
    """Return a resolved regular file inside root, rejecting symlinks/escapes."""
    lexical = absolute(raw, label)
    root_lexical = Path(os.path.abspath(root_lexical))
    if not lexical.is_relative_to(root_lexical):
        raise ValueError(f"{label} is outside its root")
    relative = lexical.relative_to(root_lexical)
    if not relative.parts:
        raise ValueError(f"{label} is the root itself")

    current = root_lexical
    for part in relative.parts:
        current = current / part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            raise ValueError(f"{label} is missing")
        if stat.S_ISLNK(mode):
            raise ValueError(f"{label} uses a symlink")

    resolved = lexical.resolve(strict=True)
    if not resolved.is_relative_to(root_resolved):
        raise ValueError(f"{label} resolves outside its root")
    info = resolved.stat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"{label} is not a regular file")
    if info.st_nlink != 1:
        raise ValueError(f"{label} has multiple hard links")
    return resolved

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
    """Overwrite a small metadata file before unlinking it.

    Never follow a symlink: a symlink in the private directory must be
    unlinked, not used to overwrite whatever it points at.
    """
    try:
        if path.is_symlink():
            path.unlink()
            return
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            # Never overwrite a hard-linked inode: that would change the file
            # outside the private directory too. Unlink our entry only.
            path.unlink()
            return
        with path.open("r+b", buffering=0) as handle:
            handle.write(b"\0" * info.st_size)
            handle.flush()
            os.fsync(handle.fileno())
    except (FileNotFoundError, OSError):
        pass
    try:
        path.unlink()
    except FileNotFoundError:
        pass

def ff_escape(value: str) -> str:
    return "".join("\\" + char if char in "\\=;#\n\r" else char for char in value)

def write_ffmeta(path: Path, tags: dict[str, str]) -> None:
    lines = [";FFMETADATA1"]
    for key, value in tags.items():
        if value:
            lines.append(f"{key}={ff_escape(value)}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

def apply_ffmpeg(media: Path, tags: dict[str, str], workdir: Path) -> None:
    metadata = workdir / f"meta-{secrets.token_hex(6)}.ffmeta"
    write_ffmeta(metadata, tags)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".tagtmp-", suffix=media.suffix, dir=str(media.parent)
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
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

def main() -> int:
    line = sys.stdin.readline()
    if line.strip() == "":
        log("missing manifest")
        return 2
    try:
        payload = json.loads(line)
        private_lexical = absolute(payload.get("private_dir"), "private_dir")
        out_lexical = absolute(payload.get("outdir"), "outdir")
        records = payload.get("records")
        if not isinstance(records, list) or not records:
            raise ValueError("missing records")
    except Exception:
        log("invalid manifest")
        return 2

    try:
        private_resolved = private_lexical.resolve(strict=True)
        out_resolved = out_lexical.resolve(strict=True)
    except OSError:
        log("metadata directory is missing")
        return 1
    if not private_resolved.is_dir() or not out_resolved.is_dir():
        log("metadata directory is missing")
        return 1
    if private_lexical.is_symlink():
        log("private directory is a symlink")
        return 1
    if not private_lexical.name.startswith("ytdlp-private."):
        log("unexpected private directory name")
        return 1
    if stat.S_IMODE(private_resolved.stat().st_mode) != 0o700:
        log("private directory is not mode 0700")
        return 1
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or "/dev/shm").resolve()
    if private_resolved.parent != runtime:
        log("private directory is outside the runtime directory")
        return 1
    if (private_resolved == out_resolved
            or private_resolved.is_relative_to(out_resolved)
            or out_resolved.is_relative_to(private_resolved)):
        log("private and output directories overlap")
        return 1

    seen_info: set[Path] = set()
    seen_media: set[Path] = set()
    failures = 0

    for record in records:
        info_path: Path | None = None
        try:
            if not isinstance(record, dict):
                raise ValueError("invalid record")
            info_path = safe_file(record.get("info"), private_lexical, private_resolved, "info")
            media_path = safe_file(record.get("file"), out_lexical, out_resolved, "media")
            if not info_path.name.endswith(".info.json"):
                raise ValueError("info is not an info JSON file")
            if media_path.name.endswith(".info.json"):
                raise ValueError("media is an info JSON file")
            if info_path.name != media_path.stem + ".info.json":
                raise ValueError("info does not belong to this media file")
            if media_path.is_relative_to(private_resolved):
                raise ValueError("media is inside the metadata directory")
            if info_path in seen_info or media_path in seen_media:
                raise ValueError("duplicate record")
            seen_info.add(info_path)
            seen_media.add(media_path)

            info = json.loads(info_path.read_text(encoding="utf-8"))
            tags = tags_from(info)
            if media_path.suffix.lower() == ".opus":
                try:
                    apply_opus(media_path, tags)
                except ImportError:
                    # Without mutagen there is no Opus cover-art stream to
                    # preserve, so ffmpeg can write the text tags.
                    apply_ffmpeg(media_path, tags, private_lexical)
            else:
                apply_ffmpeg(media_path, tags, private_lexical)
        except Exception:
            # Never include a title, URL or path in this diagnostic.
            log("refused or failed a metadata record")
            failures += 1
        finally:
            if info_path is not None:
                shred(info_path)

    # Anything left in the private directory is a thumbnail or an unclaimed
    # info file. Remove it without touching anything outside the directory.
    for path in private_lexical.iterdir():
        if path.is_symlink():
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        elif path.is_file():
            shred(path)
    try:
        private_lexical.rmdir()
    except OSError:
        shutil.rmtree(private_lexical, ignore_errors=True)

    return 1 if failures else 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Do not emit a traceback that could contain private paths or values.
        log("internal failure")
        sys.exit(1)
