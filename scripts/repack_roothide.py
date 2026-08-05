from __future__ import annotations

import gzip
import io
import re
import shutil
import sys
import tarfile
import tempfile
import time
from pathlib import Path


PACKAGE_ID = "com.zjc.cleanccbg2x2"
VERSION = "2.3.0"
PATCH_TARGET = "/usr/lib/DynamicPatches/AutoPatches.dylib"
EXECUTABLES = (
    "./Library/ControlCenter/Bundles/CleanCCBG1x2.bundle/CleanCCBG1x2",
    "./Library/ControlCenter/Bundles/CleanCCBG2x2.bundle/CleanCCBG2x2",
    "./Library/ControlCenter/Bundles/CleanCCBG2x3.bundle/CleanCCBG2x3",
    "./Library/ControlCenter/Bundles/CleanCCBG3x2.bundle/CleanCCBG3x2",
    "./Library/ControlCenter/Bundles/CleanCCBG3x3.bundle/CleanCCBG3x3",
    "./Library/ControlCenter/Bundles/CleanCCBGDefaultRestore.bundle/CleanCCBGDefaultRestore",
    "./Library/ControlCenter/Bundles/CleanCCBGMasterSwitch.bundle/CleanCCBGMasterSwitch",
    "./Library/ControlCenter/Bundles/CleanCCBGThemeSwitcher.bundle/CleanCCBGThemeSwitcher",
    "./Library/MobileSubstrate/DynamicLibraries/CleanCCBGSystemOverlays.dylib",
    "./Library/PreferenceBundles/CleanCCBG2x2Prefs.bundle/CleanCCBG2x2Prefs",
    "./Applications/CleanCCBG2x2App.app/CleanCCBG2x2App",
)


def read_ar(path: Path) -> dict[str, bytes]:
    data = path.read_bytes()
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("invalid deb ar archive")
    result: dict[str, bytes] = {}
    cursor = 8
    while cursor < len(data):
        header = data[cursor : cursor + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError(f"invalid ar header at {cursor}")
        name = header[:16].decode("ascii").strip().removesuffix("/")
        size = int(header[48:58].decode("ascii").strip())
        start = cursor + 60
        result[name] = data[start : start + size]
        cursor = start + size + (size & 1)
    return result


def write_ar(path: Path, members: list[tuple[str, bytes]]) -> None:
    now = int(time.time())
    output = bytearray(b"!<arch>\n")
    for name, content in members:
        header = (
            f"{name + '/':<16}{now:<12}{0:<6}{0:<6}{0o100644:<8o}{len(content):<10}`\n"
        ).encode("ascii")
        if len(header) != 60:
            raise ValueError("invalid generated ar header")
        output.extend(header)
        output.extend(content)
        if len(content) & 1:
            output.extend(b"\n")
    path.write_bytes(output)


def archive_member(members: dict[str, bytes], prefix: str) -> bytes:
    matches = [value for name, value in members.items() if name.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(f"expected one {prefix} member, got {len(matches)}")
    return matches[0]


def extract_tar(content: bytes, destination: Path) -> None:
    with tarfile.open(fileobj=io.BytesIO(content), mode="r:*") as archive:
        for member in archive.getmembers():
            resolved = (destination / member.name).resolve()
            if destination.resolve() not in resolved.parents and resolved != destination.resolve():
                raise ValueError(f"unsafe tar path: {member.name}")
        archive.extractall(destination)


def add_tree(archive: tarfile.TarFile, root: Path) -> None:
    for path in [root, *sorted(root.rglob("*"))]:
        relative = path.relative_to(root)
        name = "." if not relative.parts else "./" + relative.as_posix()
        info = archive.gettarinfo(str(path), arcname=name)
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "wheel"
        if path.is_file():
            with path.open("rb") as stream:
                archive.addfile(info, stream)
        else:
            archive.addfile(info)


def make_gnu_tar_gz(root: Path, symlinks=()) -> bytes:
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as archive:
        add_tree(archive, root)
        for name, target in symlinks:
            info = tarfile.TarInfo(name)
            info.type = tarfile.SYMTYPE
            info.linkname = target
            info.mode = 0o777
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "wheel"
            info.mtime = int(time.time())
            archive.addfile(info)
    compressed = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=compressed, mtime=int(time.time())) as output:
        output.write(raw.getvalue())
    return compressed.getvalue()


def update_control(control: Path, payload: Path) -> None:
    content = control.read_bytes()
    content = re.sub(rb"(?m)^Architecture:.*$", b"Architecture: iphoneos-arm64e", content)
    content = re.sub(rb"(?m)^Version:.*$", f"Version: {VERSION}".encode(), content)
    installed_kib = (
        sum(path.stat().st_size for path in payload.rglob("*") if path.is_file()) + 1023
    ) // 1024
    if re.search(rb"(?m)^Installed-Size:", content):
        content = re.sub(rb"(?m)^Installed-Size:.*$", f"Installed-Size: {installed_kib}".encode(), content)
    else:
        content += f"Installed-Size: {installed_kib}\n".encode()
    if not re.search(rb"(?m)^Pre-Depends:", content):
        content += b"Pre-Depends: rootless-compat (>= 0.9)\n"
    control.write_bytes(content)


def main(input_path: str) -> Path:
    source = Path(input_path).resolve()
    members = read_ar(source)
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        source_data = root / "source_data"
        control = root / "control"
        payload = root / "payload"
        source_data.mkdir()
        control.mkdir()
        payload.mkdir()
        extract_tar(archive_member(members, "data.tar"), source_data)
        extract_tar(archive_member(members, "control.tar"), control)

        source_library = source_data / "var/jb/Library"
        if not source_library.is_dir():
            raise ValueError("rootless package has no var/jb/Library")
        shutil.copytree(source_library, payload / "Library")
        source_applications = source_data / "var/jb/Applications"
        if source_applications.is_dir():
            shutil.copytree(source_applications, payload / "Applications")
        source_mobile = source_data / "var/mobile"
        if source_mobile.is_dir():
            shutil.copytree(source_mobile, payload / "var/mobile", dirs_exist_ok=True)

        postinst = control / "postinst"
        postinst.write_text(
            "#!/bin/sh\n"
            "mkdir -p /var/mobile/Library/CleanCCBG2x2/Media\n"
            "chown -R mobile:mobile /var/mobile/Library/CleanCCBG2x2 2>/dev/null || true\n"
            "if command -v uicache >/dev/null 2>&1; then uicache -p /Applications/CleanCCBG2x2App.app >/dev/null 2>&1 || uicache -a >/dev/null 2>&1 || true; fi\n"
            "exit 0\n",
            encoding="ascii",
            newline="\n",
        )
        postinst.chmod(0o755)
        update_control(control / "control", payload)

        mirror = payload / "var/mobile/Library/pkgmirror"
        shutil.copytree(payload / "Library", mirror / "Library")
        if (payload / "Applications").is_dir():
            shutil.copytree(payload / "Applications", mirror / "Applications")
        mirror_control = mirror / f"DEBIAN.{PACKAGE_ID}"
        mirror_control.mkdir(parents=True)
        shutil.copy2(control / "control", mirror_control / "control")
        shutil.copy2(postinst, mirror_control / "postinst")

        for executable in EXECUTABLES:
            if not (payload / executable.removeprefix("./")).is_file():
                raise FileNotFoundError(executable)
        links = [(f"{path}.roothidepatch", PATCH_TARGET) for path in EXECUTABLES]
        control_tar = make_gnu_tar_gz(control)
        data_tar = make_gnu_tar_gz(payload, links)

    destination = source.with_name(f"{PACKAGE_ID}_{VERSION}_roothide_iphoneos-arm64e.deb")
    write_ar(
        destination,
        [
            ("debian-binary", b"2.0\n"),
            ("control.tar.gz", control_tar),
            ("data.tar.gz", data_tar),
        ],
    )
    print(destination)
    return destination


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: repack_roothide.py package.deb")
    main(sys.argv[1])
