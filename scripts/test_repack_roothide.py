from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

from repack_roothide import VERSION, make_gnu_tar_gz, main as repack, write_ar
from verify_package import verify


ROOT = Path(__file__).resolve().parents[1]


def fake_macho() -> bytes:
    return b"\xcf\xfa\xed\xfe" + b"\0" * 8192


def main() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        payload = root / "payload"
        control = root / "control"
        prefs = payload / "var/jb/Library/PreferenceBundles/CleanCCBG2x2Prefs.bundle"
        entry = payload / "var/jb/Library/PreferenceLoader/Preferences"
        app = payload / "var/jb/Applications/CleanCCBG2x2App.app"
        tweaks = payload / "var/jb/Library/MobileSubstrate/DynamicLibraries"
        for directory in (prefs, entry, app, tweaks, control):
            directory.mkdir(parents=True)

        for module_name, source_dir in (
            ("CleanCCBG1x2", "module1x2"), ("CleanCCBG2x2", "module"),
            ("CleanCCBG2x3", "module2x3"), ("CleanCCBG3x2", "module3x2"),
            ("CleanCCBG3x3", "module3x3"),
            ("CleanCCBGDefaultRestore", "utilitymodule"),
            ("CleanCCBGMasterSwitch", "utilitytoggle"),
            ("CleanCCBGThemeSwitcher", "utilitytheme"),
        ):
            module = payload / f"var/jb/Library/ControlCenter/Bundles/{module_name}.bundle"
            module.mkdir(parents=True)
            (module / module_name).write_bytes(fake_macho())
            shutil.copy2(ROOT / source_dir / "Info.plist", module / "Info.plist")
        (tweaks / "CleanCCBGSystemOverlays.dylib").write_bytes(fake_macho())
        shutil.copy2(ROOT / "systemoverlay/CleanCCBGSystemOverlays.plist", tweaks / "CleanCCBGSystemOverlays.plist")
        (prefs / "CleanCCBG2x2Prefs").write_bytes(fake_macho())
        shutil.copy2(ROOT / "prefs/Info.plist", prefs / "Info.plist")
        shutil.copy2(ROOT / "prefs/Root.plist", prefs / "Root.plist")
        shutil.copy2(ROOT / "prefs/entry.plist", entry / "CleanCCBG2x2Prefs.plist")
        (app / "CleanCCBG2x2App").write_bytes(fake_macho())
        shutil.copy2(ROOT / "app/Info.plist", app / "Info.plist")
        (control / "control").write_text(
            "Package: com.zjc.cleanccbg2x2\n"
            "Name: Clean 2x2 Background\n"
            f"Version: {VERSION}\n"
            "Architecture: iphoneos-arm64\n"
            "Description: synthetic packaging test\n",
            encoding="ascii",
        )

        source = root / "synthetic-rootless.deb"
        write_ar(
            source,
            [
                ("debian-binary", b"2.0\n"),
                ("control.tar.gz", make_gnu_tar_gz(control)),
                ("data.tar.gz", make_gnu_tar_gz(payload)),
            ],
        )
        output = repack(str(source))
        verify(output)

    print("Synthetic rootless-to-RootHide packaging test passed")


if __name__ == "__main__":
    main()
