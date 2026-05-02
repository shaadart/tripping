#!/usr/bin/env python3
"""Check publication candidates without printing matched private contents.

Default: inspect both Git's index and tracked/nonignored working files.
--staged: inspect exactly the index; --tree REF: inspect one committed tree.
This is a disclosure tripwire, not a substitute for reviewing data/images.
"""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


@dataclass(frozen=True)
class Finding:
    path: str
    category: str
    line: int | None = None


PRIVATE_PATH_PARTS = {"pb_data", ".publication-private", "AI_CONTEXT", ".aws"}
DATA_SUFFIXES = (
    ".db", ".db-wal", ".db-shm", ".sqlite", ".sqlite-wal", ".sqlite-shm",
    ".sqlite3", ".sqlite3-wal", ".sqlite3-shm", ".gpx", ".fit", ".kml", ".kmz",
)
SIGNING_SUFFIXES = (".jks", ".keystore", ".p12", ".pfx", ".mobileprovision")
ARCHIVE_SUFFIXES = (".zip", ".tar", ".tgz", ".gz", ".7z", ".bundle", ".apk", ".aab")
IMAGE_ROOTS = (
    "assets/", "android/app/src/main/res/", "ios/Runner/Assets.xcassets/", "docs/images/",
    # Golden images rendered from synthetic test fixtures in the test font (D-058).
    "test/goldens/",
)
IMAGE_SIGNATURES = (b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"GIF87a", b"GIF89a")

# Specific constructions, rather than entropy alone: public identifiers,
# algorithm constants and generated source are expected in an open repository.
CONTENT_PATTERNS = {
    "private key material": re.compile(
        rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"
        rb"[\s\S]{32,65536}?"
        rb"-----END (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"
    ),
    "GitHub access token": re.compile(rb"(?:gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
    "AWS access key identifier": re.compile(rb"(?:AKIA|ASIA)[A-Z0-9]{16}"),
    "private invitation capability": re.compile(
        rb"tripping://invite/join\?[^\s\x22\x27<>]*[?&]k=[A-Za-z0-9_-]{22}(?![A-Za-z0-9_-])"
    ),
    "literal invitation secret": re.compile(
        rb"\bsecret\s*[:=]\s*[\x22\x27][A-Za-z0-9_-]{22}[\x22\x27]"
    ),
    "service account private key": re.compile(rb"[\x22\x27]private_key[\x22\x27]\s*:\s*[\x22\x27](?![\x22\x27])"),
}
PROPERTY_SECRET = re.compile(
    rb"(?im)^\s*(?:storePassword|keyPassword|client_secret|aws_secret_access_key)\s*[=:]\s*(.+)$"
)
PLACEHOLDER = re.compile(rb"^(?:REPLACE_|YOUR_|EXAMPLE_|CHANGE_ME|<)")


def sensitive_path(path: str) -> str | None:
    p = PurePosixPath(path)
    if PRIVATE_PATH_PARTS.intersection(p.parts):
        return "private data/context directory"
    name = p.name.lower()
    if name.endswith(DATA_SUFFIXES) or name.startswith("raw_fixes"):
        return "location or database artifact"
    if name.endswith(SIGNING_SUFFIXES):
        return "private signing artifact"
    if name.endswith(ARCHIVE_SUFFIXES):
        return "opaque archive/build artifact"
    if name in {"key.properties", "google-services.json", "googleservice-info.plist"}:
        return "local configuration (use a placeholder example)"
    if name == ".env" or (name.startswith(".env.") and name != ".env.example"):
        return "local environment configuration"
    if ("service-account" in name or "serviceaccount" in name) and name.endswith(".json"):
        return "service account configuration"
    return None


def inspect(path: str, data: bytes, *, symlink: bool = False) -> list[Finding]:
    findings = []
    if category := sensitive_path(path):
        findings.append(Finding(path, category))
    if symlink:
        findings.append(Finding(path, "symlink needs publication review"))
        return findings
    if data.startswith(b"SQLite format 3\x00"):
        findings.append(Finding(path, "SQLite database contents"))
        return findings
    if data.startswith(b"\xfe\xed\xfe\xed"):
        findings.append(Finding(path, "Java keystore contents"))
        return findings
    try:
        data.decode("utf-8")
        binary = b"\x00" in data
    except UnicodeDecodeError:
        binary = True
    if binary:
        approved_image = path.startswith(IMAGE_ROOTS) and (
            data.startswith(IMAGE_SIGNATURES)
            or (data.startswith(b"RIFF") and data[8:12] == b"WEBP")
        )
        if not approved_image:
            findings.append(Finding(path, "unreviewed binary contents"))
        return findings
    for category, pattern in CONTENT_PATTERNS.items():
        for match in pattern.finditer(data):
            findings.append(Finding(path, category, data[:match.start()].count(b"\n") + 1))
    # A Gradle assignment reads these values from Properties; it is not a
    # credential. Parse literal property files, not executable expressions.
    if path.endswith((".properties", ".properties.example")) or PurePosixPath(path).name.startswith(".env"):
        for match in PROPERTY_SECRET.finditer(data):
            value = match.group(1).strip().strip(b"\x22\x27")
            if value and not PLACEHOLDER.match(value):
                findings.append(Finding(path, "literal credential assignment", data[:match.start()].count(b"\n") + 1))
    return findings


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def git_paths(*args: str) -> list[str]:
    return [p.decode("utf-8", "surrogateescape") for p in git(*args).split(b"\x00") if p]


def check_index(tree: str | None = None) -> tuple[list[Finding], int]:
    findings = []
    if tree is None:
        entries = git("ls-files", "--stage", "-z").split(b"\x00")
    else:
        entries = git("ls-tree", "-r", "-z", "--full-tree", tree).split(b"\x00")
    count = 0
    for entry in entries:
        if not entry:
            continue
        header, raw_path = entry.split(b"\t", 1)
        fields = header.split()
        mode, oid = fields[0], fields[1 if tree is None else 2]
        path = raw_path.decode("utf-8", "surrogateescape")
        if mode == b"160000":
            findings.append(Finding(path, "submodule requires separate publication review"))
            continue
        findings.extend(inspect(path, git("cat-file", "blob", oid.decode()), symlink=mode == b"120000"))
        count += 1
    return findings, count


def check_working() -> tuple[list[Finding], int]:
    findings = []
    paths = set(git_paths("ls-files", "-z")) | set(git_paths("ls-files", "--others", "--exclude-standard", "-z"))
    count = 0
    for path in sorted(paths):
        file = Path(path)
        if not file.exists() and not file.is_symlink():
            continue
        if file.is_symlink():
            findings.extend(inspect(path, b"", symlink=True))
        elif file.is_file():
            findings.extend(inspect(path, file.read_bytes()))
        count += 1
    return findings, count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="check the Git index only")
    mode.add_argument("--tree", metavar="REF", help="check one committed tree")
    args = parser.parse_args()
    try:
        root = git("rev-parse", "--show-toplevel").decode().strip()
        os.chdir(root)
        findings, count = check_index(args.tree)
        if not args.staged and not args.tree:
            working, n = check_working()
            findings.extend(working)
            count += n
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Disclosure check could not complete ({type(error).__name__}); no file contents printed.", file=sys.stderr)
        return 2
    unique = sorted(set(findings), key=lambda f: (f.path, f.line or 0, f.category))
    for finding in unique:
        at = f":{finding.line}" if finding.line is not None else ""
        print(f"BLOCK {ascii(finding.path)}{at}: {finding.category}")
    if unique:
        print("Publication blocked. Preserve private originals outside Git; replace configuration with examples.")
        return 1
    print(f"Disclosure check passed ({count} file versions; no private values printed). Review images/data provenance separately.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
