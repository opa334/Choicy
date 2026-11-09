#!/usr/bin/env python3
"""Verify one fresh CI package before assigning its downloadable filename."""

import argparse
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", required=True, choices=("Rootless", "Roothide", "Rootful"))
    parser.add_argument("--architecture", required=True)
    args = parser.parse_args()
    architectures = {"Rootless": "iphoneos-arm64", "Roothide": "iphoneos-arm64e", "Rootful": "iphoneos-arm"}
    if args.architecture != architectures[args.label]:
        raise SystemExit("Label and expected architecture disagree")
    packages = list(Path("packages").glob("*.deb"))
    if len(packages) != 1:
        raise SystemExit(f"Expected exactly one fresh .deb; found {len(packages)}")
    package = packages[0]
    metadata = {key: output("dpkg-deb", "-f", str(package), key) for key in ("Package", "Version", "Architecture")}
    expected = {"Package": "com.opa334.choicy", "Version": "1.5.5~b1", "Architecture": args.architecture}
    if metadata != expected:
        raise SystemExit(f"Unexpected package metadata: {metadata!r}; expected {expected!r}")

    review = Path(".ci")
    review.mkdir(exist_ok=True)
    listing = output("dpkg-deb", "-c", str(package))
    (review / f"payload-{args.label}.txt").write_text(listing + "\n", encoding="utf-8")
    payload = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(package)])
    prefix = "var/jb/" if args.label == "Rootless" else ""
    required = [
        "Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib",
        "Library/MobileSubstrate/DynamicLibraries/   Choicy.plist",
        "Library/MobileSubstrate/DynamicLibraries/ChoicySB.dylib",
        "Library/MobileSubstrate/DynamicLibraries/ChoicySB.plist",
        "Library/PreferenceBundles/ChoicyPrefs.bundle/ChoicyPrefs",
        "Library/PreferenceBundles/ChoicyPrefs.bundle/Info.plist",
        "Library/PreferenceBundles/ChoicyPrefs.bundle/Root.plist",
        "Library/PreferenceLoader/Preferences/ChoicyPrefs.plist",
    ]
    localizations = sorted(Path("layout/Library/Application Support/Choicy.bundle").glob("*.lproj/Localizable.strings"))
    if not localizations:
        raise SystemExit("No source localizations found")
    required.extend(path.relative_to("layout").as_posix() for path in localizations)
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
        members = {member.name.removeprefix("./").rstrip("/"): member for member in archive.getmembers()}
        for relative in required:
            name = prefix + relative
            member = members.get(name)
            if member is None or not member.isfile() or not member.size:
                raise SystemExit(f"Missing or empty payload file: /{name}")
            # dpkg-deb -c must also show the exact filename, including its spaces.
            if name not in listing:
                raise SystemExit(f"Payload absent from dpkg-deb -c listing: {name}")
            alternate = relative if prefix else "var/jb/" + relative
            if alternate in members:
                raise SystemExit(f"Unexpected payload for another package scheme: /{alternate}")
        if args.label == "Roothide":
            # Native RootHide stages at /Library (no /var/jb prefix) and links
            # its bootstrap through .jbroot. Inspect the actual packaged images.
            for relative in (required[0], required[2], required[4]):
                image = review / (Path(relative).name.strip() + ".verify")
                image.write_bytes(archive.extractfile(members[relative]).read())
                try:
                    dependencies = output("otool", "-L", str(image))
                    if ".jbroot/" not in dependencies or "libroothide.dylib" not in dependencies:
                        raise SystemExit(f"Missing native RootHide linkage in {relative}:\n{dependencies}")
                finally:
                    image.unlink()

    artifacts = Path("artifacts")
    artifacts.mkdir(exist_ok=True)
    destination = artifacts / f"Choicy_{metadata['Version']}_{args.label}.deb"
    shutil.copy2(package, destination)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
        stream.write(f"version={metadata['Version']}\npath={destination.as_posix()}\n")
    print(f"Verified {metadata['Package']} {metadata['Version']} {metadata['Architecture']}: {destination}")


if __name__ == "__main__":
    main()
