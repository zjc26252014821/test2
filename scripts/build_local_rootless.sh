#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 <repo-root> <iphoneos-sdk> <work-dir> <ldid> <apple-ld64>" >&2
    exit 2
fi

ROOT="$(cd "$1" && pwd)"
SDK="$(cd "$2" && pwd)"
WORK="$3"
LDID="$4"
LD64="$5"
TOOLCHAIN_DIR="$(cd "$(dirname "$LD64")" && pwd)"
CLANG="$TOOLCHAIN_DIR/clang"
LIPO="$TOOLCHAIN_DIR/lipo"
STRIP="$TOOLCHAIN_DIR/strip"

case "$WORK" in
    /mnt/d/CodexData/Temp/*) ;;
    *) echo "work directory must be under /mnt/d/CodexData/Temp" >&2; exit 2 ;;
esac

[[ -f "$SDK/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h" ]]
[[ -x "$LDID" ]]
[[ -x "$LD64" ]]
[[ -x "$CLANG" ]]
[[ -x "$LIPO" ]]
[[ -x "$STRIP" ]]

# RootHide targets run on arm64e devices.  An arm64 binary with its Mach-O
# header relabelled as arm64e may pass archive validation, but dyld cannot load
# it safely.  Prove that the selected linker can emit a real arm64e binary with
# chained fixups before compiling any product.
if [[ "$(basename "$LD64")" == ld64.lld* ]]; then
    echo "refusing unsafe local build: $(basename "$LD64") cannot link arm64e chained fixups" >&2
    echo "use an Apple-compatible arm64e linker, or the macOS/Theos release workflow" >&2
    exit 1
fi

verify_arm64e_linker() {
    local probe_dir="$WORK/.arm64e-linker-probe"
    local probe_source="$probe_dir/probe.c"
    local probe_object="$probe_dir/probe.o"
    local probe_binary="$probe_dir/probe.dylib"
    local probe_log="$probe_dir/link.log"
    mkdir -p "$probe_dir"
    printf 'int ccbg_local_arm64e_probe(void) { return 0; }\n' > "$probe_source"
    "$CLANG" -target arm64e-apple-ios15.0 -arch arm64e -isysroot "$SDK" -miphoneos-version-min=15.0 \
        -c "$probe_source" -o "$probe_object"
    if ! "$LD64" -demangle -dynamic -arch arm64e -platform_version ios 15.0 16.5 \
        -syslibroot "$SDK" -fixup_chains -dylib \
        -install_name /var/jb/usr/lib/ccbg-local-arm64e-probe.dylib \
        -o "$probe_binary" "$probe_object" -lSystem >"$probe_log" 2>&1; then
        cat "$probe_log" >&2
        echo "refusing unsafe local build: linker cannot create an arm64e chained-fixup binary" >&2
        exit 1
    fi
    # ld64-609 reports this warning for the LLVM 11 arm64e object format even
    # though it emits a valid arm64e chained-fixup binary. The structural
    # checks below are the release gate; do not relabel or otherwise rewrite
    # the produced Mach-O to silence this diagnostic.
    grep -qi 'incompatible arm64e ABI' "$probe_log" && cat "$probe_log" >&2
    python3 - "$probe_binary" <<'PY'
import struct
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
magic, cpu_type, cpu_subtype, _, command_count, _, _ = struct.unpack_from('<IIIIIII', data, 0)
if magic != 0xFEEDFACF or cpu_type != 0x0100000C or (cpu_subtype & 0x00FFFFFF) != 2:
    raise SystemExit('local linker did not emit a genuine arm64e Mach-O slice')
offset = 32
has_chained_fixups = False
for _ in range(command_count):
    command, size = struct.unpack_from('<II', data, offset)
    has_chained_fixups |= command == 0x80000034
    offset += size
if not has_chained_fixups:
    raise SystemExit('local linker omitted LC_DYLD_CHAINED_FIXUPS for arm64e')
PY
}

verify_arm64e_linker

BUILD="$WORK/local-rootless-build"
THIN="$BUILD/thin"
PRODUCTS="$BUILD/products"
STAGE="$BUILD/rootless-stage"
PACKAGE="$BUILD/com.zjc.cleanccbg2x2_2.3.0_iphoneos-arm64.deb"
REUSE_THIN="${CCBG_REUSE_THIN:-0}"
REUSE_OBJECTS="${CCBG_REUSE_OBJECTS:-0}"
if [[ "$REUSE_THIN" == 1 || "$REUSE_OBJECTS" == 1 ]]; then
    [[ -d "$THIN/arm64" && -d "$THIN/arm64e" ]]
    rm -rf "$PRODUCTS" "$STAGE"
else
    rm -rf "$BUILD"
fi
mkdir -p "$THIN" "$PRODUCTS" "$STAGE"

ARCHS=(arm64 arm64e)
COMMON_CFLAGS=(-isysroot "$SDK" -miphoneos-version-min=15.0 -fobjc-arc -fblocks -O2 -I"$ROOT/shared")
BASE_FRAMEWORKS=(-framework UIKit -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework CoreMedia -framework QuartzCore)
MODULE_FRAMEWORKS=(-framework AVFoundation -framework AVKit -framework CoreImage -framework QuartzCore -framework ImageIO)

compile_object() {
    local arch="$1" source="$2" output="$3"
    shift 3
    mkdir -p "$(dirname "$output")"
    "$CLANG" -target "${arch}-apple-ios15.0" -arch "$arch" "${COMMON_CFLAGS[@]}" "$@" -c "$source" -o "$output"
}

link_bundle() {
    local arch="$1" output="$2"
    shift 2
    local name="$(basename "$output")"
    local install_root="/var/jb/Library/ControlCenter/Bundles"
    if [[ "$name" == CleanCCBG2x2Prefs ]]; then
        install_root="/var/jb/Library/PreferenceBundles"
    fi
    "$LD64" -demangle -dynamic -arch "$arch" -platform_version ios 15.0 16.5 \
        -syslibroot "$SDK" -fixup_chains -dylib \
        -install_name "${install_root}/${name}.bundle/${name}" \
        -o "$output" "$@" -lobjc -lSystem
}

link_dylib() {
    local arch="$1" output="$2"
    shift 2
    "$LD64" -demangle -dynamic -arch "$arch" -platform_version ios 15.0 16.5 \
        -syslibroot "$SDK" -fixup_chains -dylib \
        -install_name /var/jb/Library/MobileSubstrate/DynamicLibraries/CleanCCBGSystemOverlays.dylib \
        -o "$output" "$@" -lobjc -lSystem
}

link_app() {
    local arch="$1" output="$2"
    shift 2
    "$LD64" -demangle -dynamic -arch "$arch" -platform_version ios 15.0 16.5 \
        -syslibroot "$SDK" -fixup_chains -o "$output" "$@" -lobjc -lSystem
}

make_fat() {
    local name="$1" destination="$2"
    mkdir -p "$(dirname "$destination")"
    "$LIPO" -create "$THIN/arm64/$name" "$THIN/arm64e/$name" -output "$destination"
    # Match the release build's final-symbol policy before ldid signs the
    # universal binary. This removes local linker symbols, not Objective-C
    # runtime metadata or either architecture slice.
    "$STRIP" -x "$destination"
    chmod 0755 "$destination"
}

sign_binary() {
    local binary="$1" entitlements="${2:-}"
    if [[ -n "$entitlements" ]]; then
        "$LDID" "-S$entitlements" "$binary"
    else
        "$LDID" -S "$binary"
    fi
}

MODULE_NAMES=(CleanCCBG2x2 CleanCCBG1x2 CleanCCBG2x3 CleanCCBG3x2 CleanCCBG3x3)
MODULE_DIRS=(module module1x2 module2x3 module3x2 module3x3)
MODULE_DEFINES=(
    "-DCCBG_DEFAULT_GRID_WIDTH=2 -DCCBG_DEFAULT_GRID_HEIGHT=2"
    "-DCCBG_VIEW_CONTROLLER_CLASS=CleanCCBG1x2ViewController -DCCBG_MODULE_CLASS=CleanCCBG1x2Module -DCCBG_MODULE_SLOT=1 -DCCBG_DEFAULT_GRID_WIDTH=1 -DCCBG_DEFAULT_GRID_HEIGHT=2"
    "-DCCBG_VIEW_CONTROLLER_CLASS=CleanCCBG2x3ViewController -DCCBG_MODULE_CLASS=CleanCCBG2x3Module -DCCBG_MODULE_SLOT=2 -DCCBG_DEFAULT_GRID_WIDTH=2 -DCCBG_DEFAULT_GRID_HEIGHT=3"
    "-DCCBG_VIEW_CONTROLLER_CLASS=CleanCCBG3x2ViewController -DCCBG_MODULE_CLASS=CleanCCBG3x2Module -DCCBG_MODULE_SLOT=3 -DCCBG_DEFAULT_GRID_WIDTH=3 -DCCBG_DEFAULT_GRID_HEIGHT=2"
    "-DCCBG_VIEW_CONTROLLER_CLASS=CleanCCBG3x3ViewController -DCCBG_MODULE_CLASS=CleanCCBG3x3Module -DCCBG_MODULE_SLOT=4 -DCCBG_DEFAULT_GRID_WIDTH=3 -DCCBG_DEFAULT_GRID_HEIGHT=3"
)

UTILITY_NAMES=(CleanCCBGDefaultRestore CleanCCBGMasterSwitch CleanCCBGThemeSwitcher)
UTILITY_DIRS=(utilitymodule utilitytoggle utilitytheme)
UTILITY_SOURCES=(CleanCCBGDefaultRestore.m CleanCCBGMasterSwitch.m CleanCCBGThemeSwitcher.m)

APP_SOURCES=(
    CleanCCBG2x2App.m CCBGMainTabBarController.m CCBGQuickConfigController.m
    CCBGBackupTimelineController.m CCBGControls.m CCBGRootController.m
    CCBGMediaDetailController.m CCBGPreviewController.m CCBGSettingsControllers.m
    CCBGGenericSystemModulesController.m CCBGAdvancedControllers.m
    CCBGVisualFeaturesControllers.m CCBGSceneDirectorController.m CCBGSceneEditorController.m
)

if [[ "$REUSE_THIN" != 1 ]]; then
for arch in "${ARCHS[@]}"; do
    arch_dir="$THIN/$arch"
    obj_dir="$arch_dir/objects"
    mkdir -p "$obj_dir"

    if [[ "$REUSE_OBJECTS" != 1 ]]; then
        # Module bundles must use the compile-time SpringBoard-safe catalog
        # variant; the App and utility targets retain diagnostics.
        compile_object "$arch" "$ROOT/shared/CCBGMediaCatalog.m" "$obj_dir/CCBGMediaCatalog.o"
        compile_object "$arch" "$ROOT/shared/CCBGMediaCatalog.m" "$obj_dir/CCBGModuleMediaCatalog.o" -DCCBG_MODULE_SLOT=0
    fi

    for index in "${!MODULE_NAMES[@]}"; do
        name="${MODULE_NAMES[$index]}"
        read -r -a defines <<< "${MODULE_DEFINES[$index]}"
        if [[ "$REUSE_OBJECTS" != 1 ]]; then
            compile_object "$arch" "$ROOT/module/CleanCCBG2x2.m" "$obj_dir/${name}.o" "${defines[@]}"
        fi
        link_bundle "$arch" "$arch_dir/$name" "$obj_dir/${name}.o" "$obj_dir/CCBGModuleMediaCatalog.o" \
            "${BASE_FRAMEWORKS[@]}" "${MODULE_FRAMEWORKS[@]}"
    done

    for index in "${!UTILITY_NAMES[@]}"; do
        name="${UTILITY_NAMES[$index]}"
        directory="${UTILITY_DIRS[$index]}"
        source="${UTILITY_SOURCES[$index]}"
        if [[ "$REUSE_OBJECTS" != 1 ]]; then
            compile_object "$arch" "$ROOT/$directory/$source" "$obj_dir/${name}.o"
        fi
        utility_frameworks=()
        [[ "$name" == CleanCCBGThemeSwitcher ]] && utility_frameworks=(-framework AVFoundation)
        link_bundle "$arch" "$arch_dir/$name" "$obj_dir/${name}.o" "$obj_dir/CCBGMediaCatalog.o" \
            "${BASE_FRAMEWORKS[@]}" "${utility_frameworks[@]}" -framework AVFoundation -framework ImageIO
    done

    if [[ "$REUSE_OBJECTS" != 1 ]]; then
        compile_object "$arch" "$ROOT/systemoverlay/CleanCCBGSystemOverlays.m" "$obj_dir/CleanCCBGSystemOverlays.o"
    fi
    link_dylib "$arch" "$arch_dir/CleanCCBGSystemOverlays.dylib" \
        "$obj_dir/CleanCCBGSystemOverlays.o" "$obj_dir/CCBGMediaCatalog.o" \
        "${BASE_FRAMEWORKS[@]}" -framework AVFoundation -framework QuartzCore -framework Network -framework ImageIO

    if [[ "$REUSE_OBJECTS" != 1 ]]; then
        compile_object "$arch" "$ROOT/prefs/CleanCCBG2x2PrefsListController.m" "$obj_dir/CleanCCBG2x2Prefs.o"
    fi
    link_bundle "$arch" "$arch_dir/CleanCCBG2x2Prefs" "$obj_dir/CleanCCBG2x2Prefs.o" \
        "${BASE_FRAMEWORKS[@]}" -framework UniformTypeIdentifiers -undefined dynamic_lookup

    app_objects=()
    for source in "${APP_SOURCES[@]}"; do
        object="$obj_dir/app-${source%.m}.o"
        if [[ "$REUSE_OBJECTS" != 1 ]]; then
            compile_object "$arch" "$ROOT/app/$source" "$object" -I"$ROOT/app"
        fi
        app_objects+=("$object")
    done
    app_objects+=("$obj_dir/CCBGMediaCatalog.o")
    link_app "$arch" "$arch_dir/CleanCCBG2x2App" "${app_objects[@]}" \
        "${BASE_FRAMEWORKS[@]}" -framework UniformTypeIdentifiers -framework AVFoundation \
        -framework AVKit -framework QuartzCore -framework PhotosUI -framework Photos \
        -framework ImageIO -framework QuickLookThumbnailing
done
fi

for index in "${!MODULE_NAMES[@]}"; do
    name="${MODULE_NAMES[$index]}"
    directory="${MODULE_DIRS[$index]}"
    bundle="$PRODUCTS/Library/ControlCenter/Bundles/$name.bundle"
    make_fat "$name" "$bundle/$name"
    cp "$ROOT/$directory/Info.plist" "$bundle/Info.plist"
    sign_binary "$bundle/$name"
done

for index in "${!UTILITY_NAMES[@]}"; do
    name="${UTILITY_NAMES[$index]}"
    directory="${UTILITY_DIRS[$index]}"
    bundle="$PRODUCTS/Library/ControlCenter/Bundles/$name.bundle"
    make_fat "$name" "$bundle/$name"
    cp "$ROOT/$directory/Info.plist" "$bundle/Info.plist"
    sign_binary "$bundle/$name"
done

dylib_dir="$PRODUCTS/Library/MobileSubstrate/DynamicLibraries"
make_fat CleanCCBGSystemOverlays.dylib "$dylib_dir/CleanCCBGSystemOverlays.dylib"
cp "$ROOT/systemoverlay/CleanCCBGSystemOverlays.plist" "$dylib_dir/CleanCCBGSystemOverlays.plist"
sign_binary "$dylib_dir/CleanCCBGSystemOverlays.dylib"

prefs_bundle="$PRODUCTS/Library/PreferenceBundles/CleanCCBG2x2Prefs.bundle"
make_fat CleanCCBG2x2Prefs "$prefs_bundle/CleanCCBG2x2Prefs"
cp "$ROOT/prefs/Info.plist" "$prefs_bundle/Info.plist"
cp "$ROOT/prefs/Root.plist" "$prefs_bundle/Root.plist"
sign_binary "$prefs_bundle/CleanCCBG2x2Prefs"

app_bundle="$PRODUCTS/Applications/CleanCCBG2x2App.app"
make_fat CleanCCBG2x2App "$app_bundle/CleanCCBG2x2App"
cp "$ROOT/app/Info.plist" "$app_bundle/Info.plist"
cp "$ROOT/app/AppIcon60x60@2x.png" "$app_bundle/AppIcon60x60@2x.png"
cp "$ROOT/app/AppIcon60x60@3x.png" "$app_bundle/AppIcon60x60@3x.png"
sign_binary "$app_bundle/CleanCCBG2x2App" "$ROOT/app/AppEntitlements.plist"

mkdir -p "$STAGE/var/jb" "$STAGE/DEBIAN"
cp -a "$PRODUCTS/Library" "$STAGE/var/jb/Library"
cp -a "$PRODUCTS/Applications" "$STAGE/var/jb/Applications"
cp -a "$ROOT/layout/Library/." "$STAGE/var/jb/Library/"
cp "$ROOT/control" "$STAGE/DEBIAN/control"

installed_size=$(du -sk "$STAGE/var/jb" | awk '{print $1}')
printf 'Installed-Size: %s\n' "$installed_size" >> "$STAGE/DEBIAN/control"
cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
mkdir -p /var/mobile/Library/CleanCCBG2x2/Media
chown -R mobile:mobile /var/mobile/Library/CleanCCBG2x2 2>/dev/null || true
if command -v uicache >/dev/null 2>&1; then
    uicache -p /var/jb/Applications/CleanCCBG2x2App.app >/dev/null 2>&1 || uicache -a >/dev/null 2>&1 || true
fi
exit 0
POSTINST
chmod 0755 "$STAGE/DEBIAN/postinst"

python3 "$ROOT/scripts/package_local_rootless.py" "$STAGE" "$PACKAGE"
python3 "$ROOT/scripts/repack_roothide.py" "$PACKAGE"
