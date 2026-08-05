# Project Instructions

## Repository And Build

- Canonical GitHub repository: https://github.com/zjccrh-arch/zjc
- Git remote: `git@github.com:zjccrh-arch/zjc.git`
- Pushes to `main` trigger `.github/workflows/build.yml` on macOS with Theos as a fallback verification path.
- Successful RootHide packages are force-published to the `build-artifacts` branch with `SHA256SUMS` and are also uploaded as the `CleanCCBG2x2-RootHide` Actions artifact.
- Build failures publish `roothide-error.txt` to the `build-diagnostics` branch when conversion diagnostics are available.
- Before pushing, run the bundled Python `scripts/validate_source.py` and `scripts/test_repack_roothide.py`, then run `git diff --check`.
- Use the bundled local RootHide build script only with a verified Apple-compatible linker that produces genuine `arm64e` chained-fixup binaries. The script must fail rather than relabel `arm64` output as `arm64e`. Before publishing a local package, run the source validator, repack test, and `scripts/verify_package.py` against the generated deb. When no verified local `arm64e` toolchain is available, use the macOS/Theos build workflow.

## Product Invariants

- The five custom modules share media files and basic library metadata only.
- Playback, selected/current media, automation, module behavior, and per-media presentation/playback overrides remain independent per module slot.
- System Connectivity/Music overlays are separate global features and must not silently share a custom module's configuration.
- Preserve existing user changes in the worktree and do not revert unrelated edits.

## Release

- Current release line: `2.3.0`.
- Keep `control`, all bundle `Info.plist` files, local packaging scripts, `scripts/repack_roothide.py`, validation assertions, README package names, and cloud artifact publication aligned when changing versions.

## Artifact Policy

- Build iOS plugin releases locally with the bundled RootHide build script when its toolchain is available. GitHub Actions remains a fallback for independent macOS/Theos verification.
- Store verified final artifacts under `D:\iOS-Plugin-Artifacts\<project>\<version>`.
- Never place or leave final build artifacts on the Desktop.
