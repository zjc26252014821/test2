from __future__ import annotations

import gzip
import io
import sys
import tarfile
import time
from pathlib import Path

from repack_roothide import write_ar


EXECUTABLES = {
    "var/jb/Library/ControlCenter/Bundles/CleanCCBG1x2.bundle/CleanCCBG1x2",
    "var/jb/Library/ControlCenter/Bundles/CleanCCBG2x2.bundle/CleanCCBG2x2",
    "var/jb/Library/ControlCenter/Bundles/CleanCCBG2x3.bundle/CleanCCBG2x3",
    "var/jb/Library/ControlCenter/Bundles/CleanCCBG3x2.bundle/CleanCCBG3x2",
    "var/jb/Library/ControlCenter/Bundles/CleanCCBG3x3.bundle/CleanCCBG3x3",
    "var/jb/Library/ControlCenter/Bundles/CleanCCBGDefaultRestore.bundle/CleanCCBGDefaultRestore",
    "var/jb/Library/ControlCenter/Bundles/CleanCCBGMasterSwitch.bundle/CleanCCBGMasterSwitch",
    "var/jb/Library/ControlCenter/Bundles/CleanCCBGThemeSwitcher.bundle/CleanCCBGThemeSwitcher",
    "var/jb/Library/MobileSubstrate/DynamicLibraries/CleanCCBGSystemOverlays.dylib",
    "var/jb/Library/PreferenceBundles/CleanCCBG2x2Prefs.bundle/CleanCCBG2x2Prefs",
    "var/jb/Applications/CleanCCBG2x2App.app/CleanCCBG2x2App",
}


def add_path(archive: tarfile.TarFile, root: Path, path: Path, executable: bool) -> None:
    relative = path.relative_to(root)
    name = "." if not relative.parts else "./" + relative.as_posix()
    info = archive.gettarinfo(str(path), arcname=name)
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "wheel"
    info.mtime = int(time.time())
    if path.is_dir():
        info.mode = 0o755
        archive.addfile(info)
    else:
        info.mode = 0o755 if executable else 0o644
        with path.open("rb") as stream:
            archive.addfile(info, stream)


def make_tar_gz(root: Path, *, control: bool) -> bytes:
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as archive:
        add_path(archive, root, root, False)
        for path in sorted(root.rglob("*")):
            relative = path.relative_to(root).as_posix()
            if not control and relative.split("/", 1)[0] == "DEBIAN":
                continue
            executable = relative == "postinst" if control else relative in EXECUTABLES
            add_path(archive, root, path, executable)
    compressed = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=compressed, mtime=int(time.time())) as output:
        output.write(raw.getvalue())
    return compressed.getvalue()


def main(stage_text: str, output_text: str) -> None:
    stage = Path(stage_text).resolve()
    output = Path(output_text).resolve()
    control = stage / "DEBIAN"
    if not (control / "control").is_file() or not (control / "postinst").is_file():
        raise FileNotFoundError("rootless stage is missing DEBIAN/control or DEBIAN/postinst")
    missing = sorted(path for path in EXECUTABLES if not (stage / path).is_file())
    if missing:
        raise FileNotFoundError(f"rootless stage is missing executables: {missing}")
    output.parent.mkdir(parents=True, exist_ok=True)
    write_ar(
        output,
        [
            ("debian-binary", b"2.0\n"),
            ("control.tar.gz", make_tar_gz(control, control=True)),
            ("data.tar.gz", make_tar_gz(stage, control=False)),
        ],
    )
    print(output)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} <stage-dir> <output.deb>")
    main(sys.argv[1], sys.argv[2])
