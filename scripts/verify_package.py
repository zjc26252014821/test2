from __future__ import annotations

import hashlib
import io
import plistlib
import sys
import tarfile
from pathlib import Path

from repack_roothide import EXECUTABLES, PACKAGE_ID, PATCH_TARGET, VERSION, read_ar

MODULE_SPECS = {
    "CleanCCBG1x2": (1, 2, "CleanCCBG1x2Module"),
    "CleanCCBG2x2": (2, 2, "CleanCCBG2x2Module"),
    "CleanCCBG2x3": (2, 3, "CleanCCBG2x3Module"),
    "CleanCCBG3x2": (3, 2, "CleanCCBG3x2Module"),
    "CleanCCBG3x3": (3, 3, "CleanCCBG3x3Module"),
}
UTILITY_MODULE_SPECS = (
    ("CleanCCBGDefaultRestore", 1, 1, "CleanCCBGDefaultRestoreModule"),
    ("CleanCCBGMasterSwitch", 1, 1, "CleanCCBGMasterSwitchModule"),
    ("CleanCCBGThemeSwitcher", 1, 1, "CleanCCBGThemeSwitcherModule"),
)


def read_member(archive: tarfile.TarFile, name: str) -> bytes:
    stream = archive.extractfile(name)
    if stream is None:
        raise ValueError(f"missing archive file: {name}")
    return stream.read()


def verify(path: Path) -> None:
    members = read_ar(path)
    if list(members) != ["debian-binary", "control.tar.gz", "data.tar.gz"]:
        raise ValueError(f"unexpected deb members: {list(members)}")
    if members["debian-binary"] != b"2.0\n":
        raise ValueError("invalid debian-binary")

    with tarfile.open(fileobj=io.BytesIO(members["control.tar.gz"]), mode="r:gz") as control:
        if any(member.type in (b"x", b"g") for member in control.getmembers()):
            raise ValueError("control archive has PAX headers")
        text = read_member(control, "./control").decode("utf-8")
        for expected in (
            f"Package: {PACKAGE_ID}",
            f"Version: {VERSION}",
            "Architecture: iphoneos-arm64e",
            "Pre-Depends: rootless-compat (>= 0.9)",
        ):
            if expected not in text:
                raise ValueError(f"missing control field: {expected}")

    with tarfile.open(fileobj=io.BytesIO(members["data.tar.gz"]), mode="r:gz") as data:
        entries = data.getmembers()
        names = {entry.name for entry in entries}
        if any(entry.type in (b"x", b"g") for entry in entries):
            raise ValueError("data archive has PAX headers")
        if any(name.startswith("./var/jb/") for name in names):
            raise ValueError("rootless var/jb path remains")
        links = [entry for entry in entries if entry.name.endswith(".roothidepatch")]
        if len(links) != len(EXECUTABLES):
            raise ValueError(f"wrong AutoPatches count: {len(links)}")
        if any(not entry.issym() or entry.linkname != PATCH_TARGET for entry in links):
            raise ValueError("invalid AutoPatches link")

        for executable in EXECUTABLES:
            binary = read_member(data, executable)
            if len(binary) < 4096 or binary[:4] not in (
                b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf", b"\xcf\xfa\xed\xfe"
            ):
                raise ValueError(f"invalid Mach-O: {executable}")
            mirror = "./var/mobile/Library/pkgmirror/" + executable.removeprefix("./")
            if read_member(data, mirror) != binary:
                raise ValueError(f"pkgmirror differs: {executable}")

        overlay_filter = plistlib.loads(read_member(data, "./Library/MobileSubstrate/DynamicLibraries/CleanCCBGSystemOverlays.plist"))
        if overlay_filter.get("Filter", {}).get("Bundles") != ["com.apple.springboard"]:
            raise ValueError("system overlay tweak is not filtered to SpringBoard")

        for module_name, (width, height, principal_class) in MODULE_SPECS.items():
            module_info = plistlib.loads(read_member(
                data, f"./Library/ControlCenter/Bundles/{module_name}.bundle/Info.plist"
            ))
            portrait = module_info["CCSModuleSize"]["Portrait"]
            if (portrait["Width"], portrait["Height"]) != (width, height):
                raise ValueError(f"wrong module size for {module_name}")
            if module_info.get("NSPrincipalClass") != principal_class:
                raise ValueError(f"wrong principal class for {module_name}")
            for key, expected in (
                ("CCSGetModuleSizeAtRuntime", True),
                ("CFBundleSupportedPlatforms", ["iPhoneOS"]),
                ("MinimumOSVersion", "15.0"),
                ("UIDeviceFamily", [1, 2]),
            ):
                if module_info.get(key) != expected:
                    raise ValueError(f"wrong {module_name} registration field {key}: {module_info.get(key)!r}")
        for module_name, width, height, principal_class in UTILITY_MODULE_SPECS:
            utility_info = plistlib.loads(read_member(
                data, f"./Library/ControlCenter/Bundles/{module_name}.bundle/Info.plist"
            ))
            portrait = utility_info["CCSModuleSize"]["Portrait"]
            if (portrait["Width"], portrait["Height"]) != (width, height):
                raise ValueError(f"wrong module size for {module_name}")
            if utility_info.get("NSPrincipalClass") != principal_class:
                raise ValueError(f"wrong principal class for {module_name}")
            if utility_info.get("CCSGetModuleSizeAtRuntime") is not False:
                raise ValueError(f"wrong runtime sizing flag for {module_name}")
        entry = plistlib.loads(
            read_member(data, "./Library/PreferenceLoader/Preferences/CleanCCBG2x2Prefs.plist")
        )
        entry_data = entry.get("entry", {})
        if entry_data.get("bundle") != "CleanCCBG2x2Prefs":
            raise ValueError("invalid PreferenceLoader entry")
        if entry_data.get("detail") != "CleanCCBG2x2PrefsListController":
            raise ValueError("PreferenceLoader entry has no controller detail")
        if entry_data.get("isController") is not True:
            raise ValueError("PreferenceLoader entry is not a controller")
        prefs = plistlib.loads(
            read_member(data, "./Library/PreferenceBundles/CleanCCBG2x2Prefs.bundle/Root.plist")
        )
        controls = {item.get("key"): item for item in prefs["items"] if item.get("key")}
        expected_keys = {
            "blurEnabled", "blurIntensity", "contentMode", "videoSoundEnabled",
            "slideshowEnabled", "slideshowInterval",
        }
        if set(controls) != expected_keys:
            raise ValueError(f"unexpected preference keys: {set(controls)}")
        for key in expected_keys:
            if controls[key]["defaults"] != PACKAGE_ID:
                raise ValueError(f"wrong domain for {key}")
            if controls[key]["PostNotification"] != f"{PACKAGE_ID}/reload":
                raise ValueError(f"wrong notification for {key}")
        app_info = plistlib.loads(
            read_member(data, "./Applications/CleanCCBG2x2App.app/Info.plist")
        )
        if app_info.get("CFBundleIdentifier") != "com.zjc.cleanccbg2x2.app":
            raise ValueError("invalid configuration app bundle")
        if app_info.get("CFBundleExecutable") != "CleanCCBG2x2App":
            raise ValueError("invalid configuration app executable")

    print(f"Verified: {path}")
    print(f"SHA256: {hashlib.sha256(path.read_bytes()).hexdigest()}")
    print(f"RootHide paths, GNU tar, PAX=0, AutoPatches={len(EXECUTABLES)}, media-modules={len(MODULE_SPECS)}, utility-modules={len(UTILITY_MODULE_SPECS)}, app=1")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_package.py package.deb")
    verify(Path(sys.argv[1]))
