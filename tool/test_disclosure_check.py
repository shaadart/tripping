"""Synthetic disclosure regressions; never store actual credentials as fixtures."""

from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

from disclosure_check import inspect


class DisclosureCheckTest(unittest.TestCase):
    def test_private_paths_are_blocked_even_with_innocent_contents(self):
        for path in (
            "pb_data/types.d.ts", ".publication-private/history.bundle",
            "AI_CONTEXT/CURRENT_STATE.md", "backup/journeys.sqlite-wal",
            "ride.gpx", ".env.production", "android/key.properties",
            "android/app/google-services.json", "copy/upload.p12",
        ):
            with self.subTest(path=path):
                self.assertTrue(inspect(path, b"not sensitive by itself"))

    def test_renamed_database_and_keystore_are_blocked(self):
        self.assertTrue(inspect("source.dat", b"SQLite format 3\x00" + bytes(100)))
        self.assertTrue(inspect("source.dat", bytes.fromhex("feedfeed") + bytes(20)))

    def test_embedded_credentials_and_invites_are_blocked_without_echoing_values(self):
        private = b"-----BEGIN " + b"PRIVATE KEY-----\n" + b"Y" * 64 + b"\n-----END " + b"PRIVATE KEY-----"
        fixtures = (
            private,
            b"ghp_" + b"x" * 36,
            b"AKIA" + b"X" * 16,
            b"tripping://invite/join?g=fiction&k=" + b"A" * 22 + b"&n=Asha",
            b"secret: '" + b"A" * 22 + b"'",
            b"storePassword=" + b"fictional-password",
        )
        for data in fixtures:
            with self.subTest(prefix=data[:8]):
                findings = inspect("candidate.properties", data)
                self.assertTrue(findings)
                self.assertTrue(all(data.decode() not in str(f) for f in findings))

    def test_source_public_identifiers_examples_and_synthetic_geometry_are_allowed(self):
        for path, data in (
            ("lib/group/keys.dart", b"const salt = 'tripping-group-v1';"),
            ("test/trace.dart", b"latitude: 12.9763, longitude: 77.5929"),
            ("android/key.properties.example", b"storePassword=REPLACE_WITH_PASSWORD\nkeyPassword=YOUR_PASSWORD"),
            ("config/firebase.example.json", b'{"project_id":"example-project","api_key":"PUBLIC_CLIENT_IDENTIFIER"}'),
            ("docs/source.md", b"The marker -----BEGIN " + b"PRIVATE KEY----- is documentation, without a key."),
            (".env.example", b"PUBLIC_ENDPOINT=https://example.invalid"),
        ):
            with self.subTest(path=path):
                self.assertEqual(inspect(path, data), [])

    def test_unknown_binaries_and_symlinks_need_review(self):
        self.assertTrue(inspect("test.bin", b"secret\x00payload"))
        self.assertTrue(inspect("test.bin", bytes.fromhex("fffeabcd")))
        self.assertTrue(inspect("asset", b"", symlink=True))
        self.assertEqual(inspect("docs/images/demo.png", b"\x89PNG\r\n\x1a\n\x00"), [])
        self.assertEqual(inspect("test/goldens/screen.png", b"\x89PNG\r\n\x1a\n\x00"), [])
        self.assertTrue(inspect("test/other/screen.png", b"\x89PNG\r\n\x1a\n\x00"))

    def test_staged_check_reads_index_even_if_working_file_has_been_cleaned(self):
        script = Path(__file__).with_name("disclosure_check.py").resolve()
        with tempfile.TemporaryDirectory(prefix="tripping-disclosure-") as tmp:
            subprocess.run(["git", "init", "-q", tmp], check=True)
            file = Path(tmp, "candidate.txt")
            file.write_bytes(b"ghp_" + b"x" * 36)
            subprocess.run(["git", "-C", tmp, "add", "candidate.txt"], check=True)
            file.write_text("clean working file")
            run = subprocess.run(["python3", str(script), "--staged"], cwd=tmp, capture_output=True, text=True)
            self.assertEqual(run.returncode, 1)
            self.assertIn("GitHub access token", run.stdout)
            self.assertNotIn("x" * 36, run.stdout)


class AndroidBackupPolicyTest(unittest.TestCase):
    def test_manifest_disables_backup_and_references_transfer_exclusions(self):
        root = Path(__file__).resolve().parents[1]
        manifest = ET.parse(root / "android/app/src/main/AndroidManifest.xml")
        app = manifest.getroot().find("application")
        ns = "{http://schemas.android.com/apk/res/android}"
        self.assertEqual(app.attrib[ns + "allowBackup"], "false")
        self.assertEqual(app.attrib[ns + "fullBackupContent"], "false")
        self.assertEqual(app.attrib[ns + "dataExtractionRules"], "@xml/data_extraction_rules")
        rules = ET.parse(root / "android/app/src/main/res/xml/data_extraction_rules.xml")
        expected = {"root", "file", "database", "sharedpref", "external", "device_root", "device_file", "device_database", "device_sharedpref"}
        for kind in ("cloud-backup", "device-transfer"):
            branch = rules.getroot().find(kind)
            self.assertEqual({e.attrib["domain"] for e in branch.findall("exclude") if e.attrib["path"] == "."}, expected)


if __name__ == "__main__":
    unittest.main()
