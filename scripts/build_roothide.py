from __future__ import annotations

import sys
import traceback
from pathlib import Path

from repack_roothide import main as repack
from verify_package import verify


ROOT = Path(__file__).resolve().parents[1]


def annotation_text(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main() -> None:
    packages = ROOT / "packages"
    sources = sorted(
        path for path in packages.glob("*.deb") if "roothide" not in path.name.lower()
    )
    if len(sources) != 1:
        raise ValueError(f"expected one rootless package, found: {[p.name for p in sources]}")
    output = repack(str(sources[0]))
    verify(output)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        summary = f"{type(error).__name__}: {error}"
        details = "".join(traceback.format_exception(error))
        diagnostics = ROOT / "packages/roothide-error.txt"
        diagnostics.parent.mkdir(parents=True, exist_ok=True)
        diagnostics.write_text(details, encoding="utf-8")
        print(
            f"::error title=RootHide conversion failed::{annotation_text(summary)}",
            file=sys.stderr,
        )
        print(details, file=sys.stderr)
        raise SystemExit(1) from error
