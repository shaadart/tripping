#!/usr/bin/env python3
"""Synthetic repository checks for isolated publication preparation."""

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "prepare_publication", Path(__file__).with_name("prepare_publication.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PreparationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="tripping_history_test_")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "source"
        self.root.mkdir()
        self.command("init", "-b", "main")
        self.command("config", "user.name", "Fictional Test")
        self.command("config", "user.email", "fictional@example.invalid")
        (self.root / "app.txt").write_text("synthetic application\n")
        (self.root / "pb_data").mkdir()
        self.private = self.root / "pb_data/data.db"
        self.private.write_bytes(b"fictional private database fixture\n")
        self.command("add", ".")
        self.command("commit", "-m", "Synthetic initial history")
        tree = self.command("rev-parse", "HEAD^{tree}").strip()
        self.command("update-ref", "refs/codex/test/tree", tree)
        (self.root / ".gitignore").write_text("/pb_data/\n/.publication-private/\n")
        self.command("rm", "--cached", "pb_data/data.db")
        self.command("add", ".gitignore")
        self.command("commit", "-m", "Synthetic publication cleanup")
        self.head = self.command("rev-parse", "HEAD").strip()

    def command(self, *arguments):
        return subprocess.run(["git", "-C", str(self.root), *arguments],
                              capture_output=True, text=True, check=True).stdout

    def test_isolated_rewrite_cleans_history_and_preserves_source_and_tree_ref(self):
        before = MODULE.refs(self.root)
        git_files_before = {str(p.relative_to(self.root / ".git")): MODULE.digest(p)
                            for p in (self.root / ".git").rglob("*") if p.is_file()}
        private_bytes = self.private.read_bytes()
        output = self.root / ".publication-private/prepared"
        result = MODULE.prepare(self.root, output, self.head, ["refs/heads/main"])
        self.assertEqual(result["commits_verified"], 2)
        self.assertEqual(result["commits_changed"], 2)
        self.assertTrue(result["parent_graph_verified"])
        self.assertTrue(result["stored_objects_all_reachable"])
        self.assertFalse(result["credential_rotation_confirmed"])
        self.assertFalse(result["publication_authorized"])
        self.assertEqual(MODULE.refs(self.root), before)
        git_files_after = {str(p.relative_to(self.root / ".git")): MODULE.digest(p)
                           for p in (self.root / ".git").rglob("*") if p.is_file()}
        self.assertEqual(git_files_before, git_files_after)
        self.assertEqual(self.private.read_bytes(), private_bytes)
        self.assertEqual(self.command("status", "--porcelain"), "")
        self.assertFalse((self.root / ".git-rewrite").exists())
        self.assertEqual(set(MODULE.refs(output / "candidate.git", bare=True)),
                         {"refs/heads/main"})
        self.assertFalse(any(MODULE.private_path(path) for path in
                             MODULE.objects(output / "candidate.git", bare=True).values()))
        self.assertEqual(os.stat(output).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(output / "all-refs.bundle").st_mode & 0o777, 0o600)
        self.assertEqual(MODULE.refs(output / "restore-check.git", bare=True), before)

    def test_wrong_head_refuses_before_creating_output(self):
        output = Path(self.directory.name) / "not-created"
        with self.assertRaisesRegex(RuntimeError, "HEAD"):
            MODULE.prepare(self.root, output, "0" * 40, ["refs/heads/main"])
        self.assertFalse(output.exists())

    def test_dirty_source_refuses_before_creating_output(self):
        output = Path(self.directory.name) / "not-created"
        (self.root / "app.txt").write_text("unfinished unrelated work\n")
        with self.assertRaises(RuntimeError):
            MODULE.prepare(self.root, output, self.head, ["refs/heads/main"])
        self.assertFalse(output.exists())
        self.assertEqual((self.root / "app.txt").read_text(), "unfinished unrelated work\n")

    def test_existing_output_is_preserved(self):
        output = Path(self.directory.name) / "existing"
        output.mkdir()
        (output / "keep.txt").write_text("preserve\n")
        with self.assertRaisesRegex(RuntimeError, "must not exist"):
            MODULE.prepare(self.root, output, self.head, ["refs/heads/main"])
        self.assertEqual((output / "keep.txt").read_text(), "preserve\n")

    def test_unignored_output_in_source_is_refused(self):
        output = self.root / "unsafe-output"
        with self.assertRaisesRegex(RuntimeError, "Git-ignored"):
            MODULE.prepare(self.root, output, self.head, ["refs/heads/main"])
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
