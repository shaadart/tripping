#!/usr/bin/env python3
"""Audit or prepare a private, isolated publication copy; never rewrite source.

Default invocation is read-only. --prepare requires the full expected source
HEAD and creates a protected original Git copy, all-ref bundle and candidate.
Only explicitly selected heads/tags enter candidate.git (main by default).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


PRIVATE_PATH = "pb_data"


def git(repo: Path, *arguments: str, bare: bool = False,
        data: bytes | None = None, env: dict[str, str] | None = None) -> bytes:
    prefix = ["git", f"--git-dir={repo}"] if bare else ["git", "-C", str(repo)]
    result = subprocess.run(prefix + list(arguments), input=data,
                            capture_output=True, env=env, cwd=repo)
    if result.returncode:
        # Git errors may contain configuration or URLs. Never echo them.
        raise RuntimeError(f"Git {arguments[0]} failed (exit {result.returncode})")
    return result.stdout


def refs(repo: Path, *, bare: bool = False) -> dict[str, dict[str, str]]:
    rows = git(repo, "for-each-ref", "--format=%(refname) %(objectname) %(objecttype)",
               bare=bare).decode().splitlines()
    return {name: {"oid": oid, "type": kind}
            for name, oid, kind in (row.split(" ") for row in rows)}


def objects(repo: Path, *, bare: bool = False) -> dict[str, str]:
    rows = git(repo, "rev-list", "--objects", "--all", bare=bare).decode().splitlines()
    return {row.partition(" ")[0]: row.partition(" ")[2] for row in rows}


def private_path(path: str) -> bool:
    return path == PRIVATE_PATH or path.startswith(PRIVATE_PATH + "/")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protect(directory: Path) -> None:
    os.chmod(directory, 0o700)
    for path in directory.rglob("*"):
        if path.is_symlink():
            raise RuntimeError("Unexpected symlink in protected copy")
        os.chmod(path, 0o700 if path.is_dir() else 0o600)


def tree_without_private(repo: Path, commit: str) -> dict[str, str]:
    rows = git(repo, "ls-tree", "-r", "-z", commit, bare=True).split(b"\0")
    result = {}
    for row in rows:
        if not row:
            continue
        metadata, path = row.split(b"\t", 1)
        name = path.decode()
        if not private_path(name):
            result[name] = metadata.decode()
    return result


def prepare(source: Path, output: Path, expected_head: str,
            publication_refs: list[str]) -> dict[str, object]:
    head = git(source, "rev-parse", "HEAD").decode().strip()
    if len(expected_head) != 40 or head != expected_head:
        raise RuntimeError("Expected full source HEAD does not match")
    git(source, "diff", "--quiet")
    git(source, "diff", "--cached", "--quiet")
    before = refs(source)
    for ref in publication_refs:
        if not ref.startswith(("refs/heads/", "refs/tags/")) or ref not in before:
            raise RuntimeError("Select existing publication heads/tags only")
        if before[ref]["type"] != "commit":
            raise RuntimeError("This procedure requires commit-valued publication refs")
    source_git = Path(git(source, "rev-parse", "--absolute-git-dir").decode().strip())
    if (source_git / "shallow").exists() or (source_git / "objects/info/alternates").exists():
        raise RuntimeError("Preparation requires complete independent source objects")
    if output.exists():
        raise RuntimeError("Output must not exist; originals are never overwritten")
    if output == source or source_git in output.parents or output == source_git:
        raise RuntimeError("Output must not replace source or be inside its Git directory")
    if source in output.parents:
        relative = str(output.relative_to(source))
        result = subprocess.run(["git", "-C", str(source), "check-ignore", "-q", relative])
        if result.returncode:
            raise RuntimeError("An output inside source must already be Git-ignored")
    os.umask(0o077)
    output.mkdir(parents=True, mode=0o700)
    protect(output)
    original = output / "original.git"
    shutil.copytree(source_git, original, symlinks=False)
    manifest = {}
    for path in source_git.rglob("*"):
        if path.is_file():
            relative = path.relative_to(source_git)
            value = digest(path)
            if value != digest(original / relative):
                raise RuntimeError("Source Git files changed during independent backup")
            manifest[str(relative)] = value
    if before != refs(source) or head != git(source, "rev-parse", "HEAD").decode().strip():
        raise RuntimeError("Source refs changed during backup; retry with a new output")
    (output / "copy-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "original-refs.json").write_text(json.dumps(before, indent=2) + "\n")
    git(original, "config", "core.bare", "true", bare=True)
    # A copied worktree config must never send candidate operations elsewhere.
    subprocess.run(["git", f"--git-dir={original}", "config", "--unset", "core.worktree"],
                   capture_output=True)
    git(original, "fsck", "--full", bare=True)
    bundle = output / "all-refs.bundle"
    git(original, "bundle", "create", str(bundle), "--all", bare=True)
    git(original, "bundle", "verify", str(bundle), bare=True)
    restore = output / "restore-check.git"
    subprocess.run(["git", "clone", "--mirror", str(bundle), str(restore)],
                   capture_output=True, check=True)
    if refs(restore, bare=True) != before:
        raise RuntimeError("Restored bundle refs differ from protected original")
    git(restore, "fsck", "--full", bare=True)
    original_objects = objects(original, bare=True)
    removed_ids = {oid for oid, path in original_objects.items() if private_path(path)}
    candidate = output / "candidate.git"
    shutil.copytree(original, candidate)
    # Index is a worktree artifact, not a publication ref. Keeping the old
    # index would retain the removed blobs even after rewriting/pruning.
    (candidate / "index").unlink(missing_ok=True)
    for ref in before:
        if ref not in publication_refs:
            git(candidate, "update-ref", "-d", ref, bare=True)
    git(candidate, "symbolic-ref", "HEAD", publication_refs[0], bare=True)
    for remote in git(candidate, "remote", bare=True).decode().splitlines():
        git(candidate, "remote", "remove", remote, bare=True)
    old_commits = git(candidate, "rev-list", "--reverse", *publication_refs,
                      bare=True).decode().splitlines()
    environment = os.environ.copy()
    environment["FILTER_BRANCH_SQUELCH_WARNING"] = "1"
    log = git(candidate, "filter-branch", "--force", "--index-filter",
              "git rm -r --cached --ignore-unmatch -- pb_data",
              "--tag-name-filter", "cat", "--", *publication_refs,
              bare=True, env=environment)
    (output / "rewrite.log").write_bytes(log)
    for ref in refs(candidate, bare=True):
        if ref.startswith("refs/original/"):
            git(candidate, "update-ref", "-d", ref, bare=True)
    git(candidate, "reflog", "expire", "--expire=now", "--all", bare=True)
    git(candidate, "repack", "-Ad", bare=True)
    git(candidate, "prune", "--expire=now", bare=True)
    git(candidate, "prune-packed", bare=True)
    after = refs(candidate, bare=True)
    if set(after) != set(publication_refs):
        raise RuntimeError("Candidate contains unexpected references")
    candidate_objects = objects(candidate, bare=True)
    if any(private_path(path) for path in candidate_objects.values()):
        raise RuntimeError("Forbidden path remains reachable in candidate")
    for oid in removed_ids:
        probe = subprocess.run(["git", f"--git-dir={candidate}", "cat-file", "-e", oid],
                               capture_output=True)
        if probe.returncode == 0:
            raise RuntimeError("An excluded object still exists in candidate storage")
    new_commits = git(candidate, "rev-list", "--reverse", *publication_refs,
                      bare=True).decode().splitlines()
    if len(old_commits) != len(new_commits):
        raise RuntimeError("Commit count changed unexpectedly")
    # No prune-empty: preserve graph shape, including formerly private-only
    # commits. Check each rewritten tree against its original minus pb_data.
    commit_map = dict(zip(old_commits, new_commits))
    for old, new in commit_map.items():
        old_parents = git(original, "show", "-s", "--format=%P", old,
                          bare=True).decode().split()
        new_parents = git(candidate, "show", "-s", "--format=%P", new,
                          bare=True).decode().split()
        if [commit_map[parent] for parent in old_parents] != new_parents:
            raise RuntimeError("Rewritten commit changed parent graph or ordering")
        if tree_without_private(original, old) != tree_without_private(candidate, new):
            raise RuntimeError("Rewritten commit changed unrelated tree content")
    if git(candidate, "fsck", "--full", "--no-reflogs", "--unreachable", bare=True).strip():
        raise RuntimeError("Candidate fsck reports unreachable/dangling objects")
    stored = set(git(candidate, "cat-file", "--batch-all-objects",
                     "--batch-check=%(objectname)", bare=True).decode().splitlines())
    if stored != set(candidate_objects):
        raise RuntimeError("Candidate stores objects outside its publication graph")
    if before != refs(source) or head != git(source, "rev-parse", "HEAD").decode().strip():
        raise RuntimeError("Source refs changed during preparation")
    summary = {
        "source_head": head,
        "source_untouched": True,
        "source_ref_count": len(before),
        "excluded_nonpublication_refs": sorted(set(before) - set(publication_refs)),
        "publication_refs": after,
        "commits_verified": len(commit_map),
        "commits_changed": sum(old != new for old, new in commit_map.items()),
        "excluded_objects_absent": len(removed_ids),
        "stored_objects_all_reachable": True,
        "parent_graph_verified": True,
        "backup_git_files_verified": len(manifest),
        "bundle_sha256": digest(bundle),
        "credential_rotation_confirmed": False,
        "publication_authorized": False,
    }
    (output / "commit-map.json").write_text(json.dumps(commit_map, indent=2) + "\n")
    (output / "verification.json").write_text(json.dumps(summary, indent=2) + "\n")
    protect(output)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path.cwd())
    parser.add_argument("--prepare", type=Path,
                        help="new private output directory; default is read-only audit")
    parser.add_argument("--expected-head", help="required full HEAD for --prepare")
    parser.add_argument("--publication-ref", action="append", dest="publication_refs")
    args = parser.parse_args()
    source = args.source.resolve()
    try:
        if args.prepare is None:
            found_refs = refs(source)
            found_objects = objects(source)
            print(json.dumps({
                "head": git(source, "rev-parse", "HEAD").decode().strip(),
                "refs": found_refs,
                "reachable_objects": len(found_objects),
                "excluded_path_objects": sum(private_path(p) for p in found_objects.values()),
                "remote_count": len(git(source, "remote").decode().splitlines()),
                "source_modified": False,
            }, indent=2))
        else:
            if not args.expected_head:
                parser.error("--prepare requires --expected-head")
            summary = prepare(source, args.prepare.resolve(), args.expected_head,
                              args.publication_refs or ["refs/heads/main"])
            print(json.dumps(summary, indent=2))
            print("Prepared privately. Source refs unchanged. Credential and publication gates remain open.")
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Preparation stopped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
