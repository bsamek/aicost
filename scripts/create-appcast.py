#!/usr/bin/env python3
"""Sign a validated ZIP and build a single stable-release Sparkle feed."""
import base64
import os
import pathlib
import plistlib
import re
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile


def create_appcast(directory, repository, tag, signing_tool):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Expected stable version tag")
    archives = list(directory.glob("Token-Meter-*-arm64.zip"))
    if len(archives) != 1:
        raise ValueError("Expected exactly one validated release ZIP")
    archive = archives[0]
    with zipfile.ZipFile(archive) as zipped:
        info = plistlib.loads(zipped.read("Token Meter.app/Contents/Info.plist"))
    if info["CFBundleShortVersionString"] != tag[1:]:
        raise ValueError("Release tag does not match the packaged app")
    secret = os.environ.get("SPARKLE_PRIVATE_KEY")
    if not secret:
        raise ValueError("SPARKLE_PRIVATE_KEY is required to publish updates")
    # Pass the secret over stdin, never in argv or logged output.
    result = subprocess.run(
        [str(signing_tool), "--ed-key-file", "-", "-p", str(archive)],
        input=secret, text=True, capture_output=True,
    )
    if result.returncode:
        raise ValueError("Sparkle archive signing failed")
    signature = result.stdout.strip()
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Invalid update signature")
    subprocess.run(
        ["swift", "-module-cache-path", str(pathlib.Path(__file__).resolve().parents[1] / ".build/update-module-cache"),
         str(pathlib.Path(__file__).with_name("verify-update.swift")),
         str(archive), info["SUPublicEDKey"], signature], check=True,
    )
    namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", namespace)
    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Token Meter Updates"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "Token Meter " + tag[1:]
    ET.SubElement(item, "link").text = f"https://github.com/{repository}/releases/tag/{tag}"
    for name, value in (
        ("version", info["CFBundleVersion"]),
        ("shortVersionString", info["CFBundleShortVersionString"]),
        ("minimumSystemVersion", info["LSMinimumSystemVersion"]),
    ):
        ET.SubElement(item, f"{{{namespace}}}{name}").text = value
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/{repository}/releases/download/{tag}/{urllib.parse.quote(archive.name)}",
        "length": str(archive.stat().st_size),
        "type": "application/octet-stream",
        f"{{{namespace}}}edSignature": signature,
    })
    ET.indent(root)
    output = directory / "appcast.xml"
    ET.ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)
    return output


if __name__ == "__main__":
    try:
        print(create_appcast(pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])))
    except Exception as error:
        sys.exit(str(error))
