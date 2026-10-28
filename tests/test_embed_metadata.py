#!/usr/bin/env python3
"""Regression tests for the private metadata helper.

Run from the plugin root:
    python3 -m unittest discover -s tests -v
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
HELPER = PLUGIN / "bin" / "embed-metadata.py"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_wav(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "anullsrc=r=8000:cl=mono",
            "-t", "0.1", "-c:a", "pcm_s16le", str(path),
        ],
        check=True,
    )


def title_of(path: Path) -> str:
    result = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "format_tags=title",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


class MetadataHelperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.top = Path(tempfile.mkdtemp(prefix="ytdlp-meta-test-"))
        self.outdir = self.top / "output"
        self.private = self.top / "private"
        self.outdir.mkdir()
        self.private.mkdir(mode=0o700)
        self.outside = self.top / "outside"
        self.outside.mkdir()

    def tearDown(self) -> None:
        shutil.rmtree(self.top, ignore_errors=True)

    def info(self, name: str, data: dict) -> Path:
        path = self.private / name
        path.write_text(json.dumps(data), encoding="utf-8")
        os.chmod(path, 0o600)
        return path

    def manifest(self, records: list[dict]) -> dict:
        return {
            "private_dir": str(self.private),
            "outdir": str(self.outdir),
            "records": records,
        }

    def run_helper(self, manifest: dict) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(HELPER)],
            input=json.dumps(manifest) + "\n",
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_single_exact_record(self) -> None:
        media = self.outdir / "one.wav"
        make_wav(media)
        info = self.info("one.info.json", {"id": "remote-id", "title": "Expected Title"})

        result = self.run_helper(self.manifest([{"file": str(media), "info": str(info)}]))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(title_of(media), "Expected Title")
        self.assertFalse(info.exists())
        self.assertFalse(self.private.exists())

    def test_multiple_records_are_all_tagged(self) -> None:
        first = self.outdir / "one.wav"
        second = self.outdir / "two.wav"
        make_wav(first)
        make_wav(second)
        info_one = self.info("one.info.json", {"id": "one", "title": "First"})
        info_two = self.info("two.info.json", {"id": "two", "title": "Second"})

        result = self.run_helper(self.manifest([
            {"file": str(first), "info": str(info_one)},
            {"file": str(second), "info": str(info_two)},
        ]))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(title_of(first), "First")
        self.assertEqual(title_of(second), "Second")
        self.assertFalse(self.private.exists())

    def test_malicious_remote_ids_cannot_select_an_outside_decoy(self) -> None:
        first = self.outdir / "real-one.wav"
        second = self.outdir / "real-two.wav"
        make_wav(first)
        make_wav(second)
        decoy = self.outside / "decoy.wav"
        make_wav(decoy)
        before = digest(decoy)
        # These IDs would have escaped or globbed under the old implementation.
        info_one = self.info("a.info.json", {"id": "../../outside/decoy", "title": "Inside A"})
        info_two = self.info("b.info.json", {"id": "*", "title": "Inside B"})

        result = self.run_helper(self.manifest([
            {"file": str(first), "info": str(info_one)},
            {"file": str(second), "info": str(info_two)},
        ]))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(title_of(first), "Inside A")
        self.assertEqual(title_of(second), "Inside B")
        self.assertEqual(digest(decoy), before)
        self.assertNotIn("decoy", result.stderr)

    def test_unclaimed_info_json_is_not_used(self) -> None:
        media = self.outdir / "real.wav"
        make_wav(media)
        decoy = self.outside / "decoy.wav"
        make_wav(decoy)
        before = digest(decoy)
        claimed = self.info("real.info.json", {"id": "real", "title": "Real"})
        # An extra JSON in the private directory must not be searched by ID.
        self.info("evil.info.json", {"id": "../../outside/decoy", "title": "Evil"})

        result = self.run_helper(self.manifest([{"file": str(media), "info": str(claimed)}]))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(title_of(media), "Real")
        self.assertEqual(digest(decoy), before)
        self.assertFalse(self.private.exists())

    def test_manifest_target_outside_output_is_rejected(self) -> None:
        decoy = self.outside / "decoy.wav"
        make_wav(decoy)
        before = digest(decoy)
        info = self.info("x.info.json", {"id": "x", "title": "Nope"})

        result = self.run_helper(self.manifest([{"file": str(decoy), "info": str(info)}]))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(digest(decoy), before)
        self.assertFalse(info.exists())
        self.assertFalse(self.private.exists())

    def test_parent_component_in_manifest_is_rejected(self) -> None:
        decoy = self.outside / "decoy.wav"
        make_wav(decoy)
        before = digest(decoy)
        info = self.info("x.info.json", {"id": "x", "title": "Nope"})
        escaping = self.outdir / ".." / "outside" / "decoy.wav"

        result = self.run_helper(self.manifest([{"file": str(escaping), "info": str(info)}]))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(digest(decoy), before)

    def test_absolute_manifest_target_is_rejected(self) -> None:
        info = self.info("x.info.json", {"id": "x", "title": "Nope"})

        result = self.run_helper(self.manifest([{"file": "/etc/hostname", "info": str(info)}]))

        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(Path("/etc/hostname").exists())

    def test_symlinked_media_is_rejected(self) -> None:
        decoy = self.outside / "decoy.wav"
        make_wav(decoy)
        before = digest(decoy)
        link = self.outdir / "link.wav"
        link.symlink_to(decoy)
        info = self.info("x.info.json", {"id": "x", "title": "Nope"})

        result = self.run_helper(self.manifest([{"file": str(link), "info": str(info)}]))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(digest(decoy), before)

    def test_symlinked_info_is_rejected(self) -> None:
        media = self.outdir / "one.wav"
        make_wav(media)
        outside_info = self.outside / "outside.info.json"
        outside_info.write_text(json.dumps({"id": "x", "title": "Nope"}), encoding="utf-8")
        outside_before = digest(outside_info)
        link = self.private / "link.info.json"
        link.symlink_to(outside_info)

        result = self.run_helper(self.manifest([{"file": str(media), "info": str(link)}]))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(title_of(media), "")
        self.assertEqual(digest(outside_info), outside_before)

    def test_hardlinked_info_is_unlinked_without_overwriting_outside(self) -> None:
        media = self.outdir / "one.wav"
        make_wav(media)
        outside_info = self.outside / "outside.info.json"
        outside_info.write_text(json.dumps({"id": "x", "title": "Nope"}), encoding="utf-8")
        outside_before = digest(outside_info)
        link = self.private / "hardlink.info.json"
        os.link(outside_info, link)

        result = self.run_helper(self.manifest([{"file": str(media), "info": str(link)}]))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(digest(outside_info), outside_before)
        self.assertFalse(link.exists())

    def test_hardlinked_media_is_rejected(self) -> None:
        decoy = self.outside / "decoy.wav"
        make_wav(decoy)
        before = digest(decoy)
        link = self.outdir / "hardlink.wav"
        os.link(decoy, link)
        info = self.info("x.info.json", {"id": "x", "title": "Nope"})

        result = self.run_helper(self.manifest([{"file": str(link), "info": str(info)}]))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(digest(decoy), before)


if __name__ == "__main__":
    unittest.main()
