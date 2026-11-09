#!/usr/bin/env python3
"""Check local Legacy Rootful inputs and package a completed Theos stage."""

import argparse
import io
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile


PROJECT = Path(__file__).resolve().parents[1]
MINIMUMS = {"armv7": (10, 0, 0), "arm64": (10, 0, 0), "arm64e": (12, 0, 0)}
ALTLIST = "/Library/Frameworks/AltList.framework/AltList"
SUBSTRATE = {"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", "/usr/lib/libsubstrate.dylib"}
DYLIBS = "Library/MobileSubstrate/DynamicLibraries"
PREFS = "Library/PreferenceBundles/ChoicyPrefs.bundle"
IMAGES = (f"{DYLIBS}/   Choicy.dylib", f"{DYLIBS}/ChoicySB.dylib", f"{PREFS}/ChoicyPrefs")
SCRIPTS = ("postinst", "postrm")


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def version_tuple(version):
    require(re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version), f"Invalid Mach-O version: {version!r}")
    parts = tuple(map(int, version.split(".")))
    return parts + (0,) * (3 - len(parts))


def load_commands(path, arch):
    listing = output("otool", "-arch", arch, "-l", path)
    for block in re.split(r"(?m)^Load command \d+[ \t]*\n", listing)[1:]:
        fields = [line.split(maxsplit=1) for line in block.splitlines() if line[:1].isspace()]
        yield dict(field for field in fields if len(field) == 2)


def check_linkage(commands, context, *, install_names=(), dependency=None):
    identifiers = set()
    dependencies = set()
    for command in commands:
        kind = command.get("cmd", "")
        if kind == "LC_RPATH":
            path = command["path"].rsplit(" (offset ", 1)[0]
            require(path.startswith(("@loader_path", "@executable_path", "/Library/Frameworks", "/usr/lib", "/System/Library")),
                    f"Unexpected Rootful rpath in {context}: {path}")
        elif kind.endswith("_DYLIB"):
            path = command["name"].rsplit(" (offset ", 1)[0]
            if kind == "LC_ID_DYLIB":
                identifiers.add(path)
                require(path.startswith(("/Library/", "/usr/lib/", "@rpath/", "@loader_path/")),
                        f"Unexpected Rootful install name in {context}: {path}")
            else:
                dependencies.add(path)
                system_path = path.startswith(("/System/Library/", "/usr/lib/libSystem.", "/usr/lib/libobjc.", "/usr/lib/libc++."))
                require(system_path or path == ALTLIST or path in SUBSTRATE,
                        f"Unexpected Rootful dependency in {context}: {path}")
        else:
            continue
        require(".jbroot" not in path and "/var/jb" not in path and "roothide" not in path.lower(),
                f"Non-Rootful linkage in {context}: {path}")
    if install_names:
        require(len(identifiers) == 1 and identifiers.issubset(install_names),
                f"Unexpected development library install name in {context}: {identifiers}")
    if dependency:
        require(dependency in dependencies, f"Missing {dependency} linkage in {context}")


def check_macho(path, *, package_image=False, install_names=(), dependency=None):
    slices = set(output("lipo", "-archs", path).split())
    wanted = set(MINIMUMS)
    require(wanted.issubset(slices) and (not package_image or slices == wanted),
            f"Unexpected architectures in {path}: {sorted(slices)}. Need armv7, arm64 and arm64e.")

    header_lines = output("otool", "-arch", "arm64e", "-h", path).splitlines()
    headers = [header_lines[i + 1].split() for i, line in enumerate(header_lines[:-1])
               if line.split()[:4] == ["magic", "cputype", "cpusubtype", "caps"]]
    # CPU_SUBTYPE_ARM64E is 2. The versioned ABI sets capability bits.
    require(headers and all(tuple(int(field, 0) for field in header[1:4]) == (0x0100000C, 2, 0) for header in headers),
            f"Expected old userspace arm64e ABI in {path}")

    for arch, limit in MINIMUMS.items():
        context = f"{path} ({arch})"
        commands = list(load_commands(path, arch))
        deployments = []
        for command in commands:
            kind = command.get("cmd")
            if kind == "LC_BUILD_VERSION":
                require(command["platform"].lower() in ("2", "ios", "iphoneos"), f"Expected iOS platform in {context}")
                deployments.append(version_tuple(command["minos"]))
            elif kind == "LC_VERSION_MIN_IPHONEOS":
                deployments.append(version_tuple(command["version"]))
            elif kind and kind.startswith("LC_VERSION_MIN_"):
                raise SystemExit(f"Unexpected platform in {context}: {kind}")
            else:
                continue
            if package_image:
                require(version_tuple(command["sdk"]) == (13, 7, 0), f"Expected SDK 13.7 in {context}")
        require(deployments and all(version == limit if package_image else version <= limit for version in deployments),
                f"Unexpected deployment version in {context}: {deployments}. Expected {'exactly' if package_image else 'at most'} {limit}.")
        if path.suffix != ".a":
            check_linkage(commands, context, install_names=install_names, dependency=dependency)
        if package_image:
            print(f"{path.name} {arch}: iOS {limit[0]}.{limit[1]}")


def first_file(paths):
    for path in paths:
        if path.is_file() and path.stat().st_size:
            return path
    raise SystemExit("Missing prepared input (checked " + ", ".join(map(str, paths)) + ")")


def check_stub(path, install_names):
    if path.suffix != ".tbd":
        check_macho(path, install_names=install_names)
        return
    # The patched SDK and legacy development stubs use the archs/platform TBD format.
    stub = path.read_text(encoding="utf-8")
    archs = re.search(r"(?m)^archs:\s*\[([^]]+)\]", stub)
    platform = re.search(r"(?m)^platform:\s*(\S+)", stub)
    name = re.search(r"(?m)^install-name:[ \t]*([^\n]+)", stub)
    require(archs and set(MINIMUMS).issubset(arch.strip().strip("'\"") for arch in archs[1].split(","))
            and platform and platform[1] == "ios" and name and name[1].strip().strip("'\"") in install_names,
            f"Expected an iOS Rootful stub with armv7, arm64 and arm64e in {path}")


def preflight(theos, sdk):
    settings = plistlib.loads(first_file([sdk / "SDKSettings.plist"]).read_bytes())
    require(settings.get("Version") == "13.7", f"Expected SDK version 13.7 in {sdk}")
    first_file([theos / "makefiles/common.mk"])
    for submodule, headers in (("litehook", ("litehook.h",)), ("ChOma", ("MachO.h", "Fat.h", "Host.h", "DyldSharedCache.h"))):
        source = PROJECT / "external" / submodule / "src"
        for header in headers:
            first_file([source / header])
        require(any(path.is_file() and path.stat().st_size for path in source.glob("*.c")), f"Supply {submodule} sources in {source}")

    includes = (theos / "include", theos / "vendor/include", sdk / "usr/include")
    for header in ("HBLog.h", "Preferences/PSListController.h", "Preferences/PSSpecifier.h",
                   "Preferences/PSTableCell.h", "Preferences/PSSwitchTableCell.h", "MobileCoreServices/LSApplicationProxy.h",
                   "MobileCoreServices/LSBundleProxy.h", "MobileCoreServices/LSPlugInKitProxy.h", "launch.h", "bsm/audit.h", "version.h",
                   "xpc/xpc.h", "xpc/base.h", "xpc/connection.h", "xpc/endpoint.h", "xpc/availability.h",
                   "xpc/activity.h", "xpc/debug.h", "substrate.h"):
        first_file([directory / header for directory in includes])
    first_file([directory / header for directory in includes for header in ("libroot.h", "libroot/libroot.h")])

    for framework in ("UIKit", "QuartzCore", "Preferences", "MobileCoreServices", "BackBoardServices"):
        directories = [Path("System/Library") / kind / f"{framework}.framework" for kind in ("Frameworks", "PrivateFrameworks")]
        stub = first_file([sdk / directory / f"{framework}{suffix}" for directory in directories for suffix in (".tbd", "")])
        check_stub(stub, {f"/{directory.as_posix()}/{framework}" for directory in directories})
    check_stub(first_file([sdk / "usr/lib/libSystem.tbd"]), {"/usr/lib/libSystem.B.dylib"})

    altlist = theos / "lib/AltList.framework"
    for header in ("ATLApplicationListSubcontrollerController.h", "ATLApplicationListControllerBase.h"):
        first_file([altlist / "Headers" / header])
    check_macho(first_file([altlist / "AltList"]), install_names={ALTLIST})
    libraries = (theos / "lib", theos / "lib/iphone", theos / "vendor/lib", theos / "vendor/lib/iphone")
    check_macho(first_file([directory / "libroot.a" for directory in libraries]))
    check_stub(first_file([directory / name for directory in libraries for name in ("libsubstrate.tbd", "libsubstrate.dylib")]), SUBSTRATE)
    help_text = output("dpkg-deb", "--help")
    require("--root-owner-group" in help_text and "--uniform-compression" in help_text,
            "Prepare dpkg-deb with --root-owner-group and --uniform-compression support")


def control_fields(control):
    fields = {}
    for line in control.splitlines():
        key, separator, value = line.partition(":")
        require(separator and key not in fields, f"Invalid control field: {line!r}")
        fields[key] = value.strip()
    return fields


def legacy_metadata():
    modern = control_fields((PROJECT / "control").read_text(encoding="utf-8"))
    legacy = control_fields((PROJECT / "control.legacy").read_text(encoding="utf-8"))
    runtime = {"mobilesubstrate", "com.opa334.altlist (>=1.0.4)", "preferenceloader"}
    for fields, ios in ((modern, "15.0"), (legacy, "10.0")):
        require(fields.get("Package") == "com.opa334.choicy" and fields.get("Architecture") == "iphoneos-arm",
                f"Unexpected package ID or Rootful architecture in iOS {ios} control")
        depends = [entry.strip() for entry in fields["Depends"].split(",")]
        require(len(depends) == 4 and set(depends) == runtime | {f"firmware (>= {ios})"},
                f"Unexpected iOS {ios} dependencies: {depends}")
    version = legacy.get("Version", "")
    require(version == modern.get("Version") and re.fullmatch(r"[0-9][A-Za-z0-9.+~\-]*", version),
            "control.legacy must use the same release version as control")
    return legacy


def archive_members(archive):
    members = {}
    for member in archive.getmembers():
        name = member.name.removeprefix("./").rstrip("/")
        require(name not in members and member.uid == 0 and member.gid == 0, f"Duplicate or non-root archive member: {name}")
        members[name] = member
    return members


def verify_payload(names, required):
    require(not any(name == "var/jb" or name.startswith("var/jb/") for name in names), "Found Rootless /var/jb payload")
    for suffix in ("dylib", "plist"):
        require(f"{DYLIBS}/Choicy.{suffix}" not in names, "Choicy staged without the three-space load-order prefix")
    missing = set(required).difference(names)
    require(not missing, f"Missing Rootful payload: {sorted(missing)}")


def verify_package(package, metadata, required):
    require(output("ar", "-t", package).splitlines() == ["debian-binary", "control.tar.gz", "data.tar.gz"],
            "Expected gzip-compressed Debian control and data members")
    require(control_fields(output("dpkg-deb", "-f", package)) == metadata, "Packaged control does not match control.legacy")
    for part, flag in (("control", "--ctrl-tarfile"), ("data", "--fsys-tarfile")):
        payload = subprocess.check_output(["dpkg-deb", flag, package])
        with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
            members = archive_members(archive)
            if part == "control":
                for script in SCRIPTS:
                    member = members.get(script)
                    require(member and member.isfile() and member.mode & 0o111, f"Missing executable maintainer script: {script}")
                    require(archive.extractfile(member).read() == (PROJECT / "layout/DEBIAN" / script).read_bytes(),
                            f"Packaged maintainer script differs from layout: {script}")
                continue
            verify_payload(members, required)
            for relative in required:
                member = members[relative]
                require(member.isfile() and member.size, f"Missing regular payload file: {relative}")
            for relative in IMAGES:
                image = package.parent / Path(relative).name
                image.write_bytes(archive.extractfile(members[relative]).read())
                image.chmod(members[relative].mode & 0o777)
                check_macho(image, package_image=True, dependency=ALTLIST if relative == IMAGES[2] else None)
                subprocess.run(["codesign", "--verify", "--all-architectures", image], check=True)


def package_stage(stage):
    stage = stage.resolve()
    build = PROJECT / ".theos"
    require(not build.is_symlink() and stage.is_dir() and build in stage.parents, f"Expected a project .theos staging directory: {stage}")
    layout = PROJECT / "layout"
    resources = sorted(path.relative_to(layout).as_posix() for path in (layout / "Library").rglob("*") if path.is_file())
    require(any(name.endswith("/Localizable.strings") for name in resources), "Missing source localizations")
    required = (*IMAGES, f"{DYLIBS}/   Choicy.plist", f"{DYLIBS}/ChoicySB.plist", f"{PREFS}/Info.plist", f"{PREFS}/Root.plist",
                "Library/PreferenceLoader/Preferences/ChoicyPrefs.plist", *resources)
    verify_payload({path.relative_to(stage).as_posix() for path in stage.rglob("*")}, required)
    for relative in required:
        first_file([stage / relative])
    metadata = legacy_metadata()

    debian = stage / "DEBIAN"
    require(not debian.is_symlink(), f"Staged DEBIAN must not be a symlink: {debian}")
    debian.mkdir(exist_ok=True)
    for script in SCRIPTS:
        source = first_file([layout / "DEBIAN" / script])
        destination = debian / script
        require(not destination.is_symlink(), f"Staged maintainer script must not be a symlink: {destination}")
        if not destination.exists():
            shutil.copy2(source, destination)
        require(destination.read_bytes() == source.read_bytes(), f"Staged maintainer script differs from layout: {script}")
        mode = stat.S_IMODE(destination.stat().st_mode)
        if not mode & 0o111:
            destination.chmod(0o755)
    # Replace the stage's control entry without editing the tracked modern control.
    with tempfile.NamedTemporaryFile(dir=debian, delete=False) as control:
        control.write((PROJECT / "control.legacy").read_bytes())
    temporary_control = Path(control.name)
    try:
        temporary_control.chmod(0o644)
        os.replace(temporary_control, debian / "control")
    finally:
        temporary_control.unlink(missing_ok=True)

    artifacts = PROJECT / "artifacts/legacy"
    require(artifacts.resolve() == artifacts, "Legacy artifact directory must be inside the project and free of symlinks")
    artifacts.mkdir(parents=True, exist_ok=True)
    destination = artifacts / f"Choicy_{metadata['Version']}_Rootful_Legacy_iOS10.deb"
    with tempfile.TemporaryDirectory(prefix=".package-", dir=artifacts) as scratch:
        package = Path(scratch) / destination.name
        subprocess.run(["dpkg-deb", "--root-owner-group", "--uniform-compression", "-Zgzip", "--build", stage, package], check=True)
        verify_package(package, metadata, required)
        os.replace(package, destination)
    print(f"Verified Legacy Rootful package: {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inputs = commands.add_parser("preflight")
    inputs.add_argument("theos", type=Path)
    inputs.add_argument("sdk", type=Path)
    package = commands.add_parser("package")
    package.add_argument("stage", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "preflight":
            preflight(args.theos, args.sdk)
        else:
            package_stage(args.stage)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, tarfile.TarError) as error:
        raise SystemExit(f"Legacy Rootful: {error}") from None


if __name__ == "__main__":
    main()
