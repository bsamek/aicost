"""Exercise real Sparkle signing with a temporary synthetic key and app ZIP."""
import base64
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("appcast", ROOT / "scripts/create-appcast.py")
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)
NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
TOOL = ROOT / ".build/artifacts/sparkle/Sparkle/bin/sign_update"


class AppcastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # A synthetic key used only for these tests; no Keychain or account access.
        code = """import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
"""
        with tempfile.TemporaryDirectory() as temporary:
            script = Path(temporary) / "key.swift"
            script.write_text(code)
            result = subprocess.check_output(["swift", "-module-cache-path", str(ROOT / ".build/update-module-cache"), str(script)], text=True)
        cls.private_key, cls.public_key = result.strip().splitlines()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.archive = self.directory / "Token-Meter-1.2.3-arm64.zip"
        self.write_archive(self.public_key)

    def write_archive(self, public_key):
        info = {
            "CFBundleVersion": "42", "CFBundleShortVersionString": "1.2.3",
            "LSMinimumSystemVersion": "13.0", "SUPublicEDKey": public_key,
        }
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("Token Meter.app/Contents/Info.plist", plistlib.dumps(info))

    def create(self):
        with patch.dict(os.environ, {"SPARKLE_PRIVATE_KEY": self.private_key}):
            return appcast.create_appcast(self.directory, "example/token-meter", "v1.2.3", TOOL)

    def test_signed_feed_matches_packaged_metadata_and_download(self):
        item = ET.parse(self.create()).find("channel/item")
        self.assertEqual(item.find(f"{{{NAMESPACE}}}version").text, "42")
        self.assertEqual(item.find(f"{{{NAMESPACE}}}shortVersionString").text, "1.2.3")
        self.assertEqual(item.find(f"{{{NAMESPACE}}}minimumSystemVersion").text, "13.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("length"), str(self.archive.stat().st_size))
        self.assertEqual(enclosure.get("url"), "https://github.com/example/token-meter/releases/download/v1.2.3/Token-Meter-1.2.3-arm64.zip")
        self.assertEqual(len(base64.b64decode(enclosure.get(f"{{{NAMESPACE}}}edSignature"))), 64)

    def test_tampered_archive_is_rejected(self):
        signature = ET.parse(self.create()).find("channel/item/enclosure").get(f"{{{NAMESPACE}}}edSignature")
        with self.archive.open("ab") as stream:
            stream.write(b"tampered")
        result = subprocess.run(["swift", "-module-cache-path", str(ROOT / ".build/update-module-cache"), str(ROOT / "scripts/verify-update.swift"),
                                 str(self.archive), self.public_key, signature], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"does not match", result.stderr)

    def test_wrong_private_key_cannot_publish_feed(self):
        self.write_archive(base64.b64encode(bytes(range(32))).decode())
        with self.assertRaises(subprocess.CalledProcessError):
            self.create()
        self.assertFalse((self.directory / "appcast.xml").exists())

    def test_missing_secret_cannot_publish_feed(self):
        with patch.dict(os.environ, {"SPARKLE_PRIVATE_KEY": ""}):
            with self.assertRaisesRegex(ValueError, "required"):
                appcast.create_appcast(self.directory, "example/token-meter", "v1.2.3", TOOL)
        self.assertFalse((self.directory / "appcast.xml").exists())

    def test_mismatched_release_tag_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            appcast.create_appcast(self.directory, "example/token-meter", "v1.2.4", TOOL)


if __name__ == "__main__":
    unittest.main()
