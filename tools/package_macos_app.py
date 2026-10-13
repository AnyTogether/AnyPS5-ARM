"""Packages a title relinked with `relinker --macos` as a macOS application bundle.

    python3 tools/package_macos_app.py --relinked <dir> [--game <dir>] --libs <dir> --vulkan <dir> [--input-config <file>] [--no-game-patches] <Title.app>

--relinked is the relinker's output directory: the executable (eboot) and the app0/sce_module guest
modules it wrote. --game is the title's own folder (sce_sys and its data), copied as app0 under the
relinked modules. --libs is the patched prx directory (build/core/libs/libs) and --vulkan the macOS
directory of a Vulkan SDK, whose loader and MoltenVK go into the bundle. The title's patches in
tools/macos/patches (see tools/macos/game_patches.py) are applied to the bundled eboot unless
--no-game-patches is given.

The bundle runs without the SDK or environment variables:

    Contents/MacOS/launch           enters the game folder (AnyPS5 maps /app0 under the working
                                    directory) and starts eboot
    Contents/MacOS/eboot, libs/     the title, the prx libraries, libvulkan and MoltenVK
    Contents/MacOS/app0             a link to the game folder, where eboot loads its guest modules
    Contents/Resources/game/app0    the title's files
    Contents/Resources/vulkan/icd.d MoltenVK's driver manifest

The shader cache goes to ~/Library/Caches/<bundle id> and the output to ~/Library/Logs/AnyPS5."""
import argparse
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "macos"))
import game_patches

LAUNCHER = """#!/bin/sh
# Starts the title from its game folder: AnyPS5 maps /app0 under the working directory.
here="$(cd "$(dirname "$0")" && pwd)"
export VK_DRIVER_FILES="${{VK_DRIVER_FILES:-$here/../Resources/vulkan/icd.d/MoltenVK_icd.json}}"
export ANYPS5_SHADER_CACHE_DIR="${{ANYPS5_SHADER_CACHE_DIR:-$HOME/Library/Caches/{identifier}/shader_cache}}"
mkdir -p "$ANYPS5_SHADER_CACHE_DIR" "$HOME/Library/Logs/AnyPS5"
cd "$here/../Resources/game" || exit 1
exec "$here/eboot" "$@" >> "$HOME/Library/Logs/AnyPS5/{title_id}.log" 2>&1
"""


def title_metadata(app0):
    parameters = json.loads((app0 / "sce_sys" / "param.json").read_text(encoding="utf-8"))
    title_id = parameters.get("titleId") or "UNKNOWN"
    localized = parameters.get("localizedParameters", {})
    language = localized.get("defaultLanguage") or parameters.get("defaultLanguage") or "en-US"
    name = (localized.get(language) or localized.get("en-US") or {}).get("titleName") or title_id
    version = parameters.get("contentVersion") or "1.0"
    return title_id, name, version


def make_icon(png, resources):
    """icon0.png as AppIcon.icns, or nothing when the title has none."""
    if not png.is_file():
        return None
    with tempfile.TemporaryDirectory() as scratch:
        iconset = Path(scratch) / "AppIcon.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                subprocess.run(["sips", "-z", str(size * scale), str(size * scale), str(png), "--out", str(iconset / name)], check=True, capture_output=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns")], check=True)
    return "AppIcon"


def package(relinked, game, libs, vulkan, input_config, bundle, patch=True):
    executable = relinked / "eboot"
    if not executable.is_file():
        raise RuntimeError(f"No relinked executable: {executable}")
    if bundle.suffix != ".app":
        raise ValueError(f"The bundle name must end in .app: {bundle}")
    if bundle.exists():
        shutil.rmtree(bundle)
    contents = bundle / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    app0 = resources / "game" / "app0"
    (macos / "libs").mkdir(parents=True)
    app0.mkdir(parents=True)

    # The title's files first, then the guest modules the relinker wrote over them.
    if game is not None:
        shutil.copytree(game, app0, dirs_exist_ok=True)
    if (relinked / "app0").is_dir():
        shutil.copytree(relinked / "app0", app0, dirs_exist_ok=True)
    title_id, name, version = title_metadata(app0)
    identifier = "org.anyps5." + "".join(character for character in title_id.lower() if character.isalnum())

    shutil.copy2(executable, macos / "eboot")
    (macos / "eboot").chmod(0o755)
    if patch:
        for patch_name, state in game_patches.apply(macos / "eboot", title_id):
            print(f"{title_id} patch {patch_name}: {state}")
    # The relinked executable loads its guest modules from @executable_path/app0/sce_module.
    (macos / "app0").symlink_to(Path("..") / "Resources" / "game" / "app0")
    libraries = sorted(libs.glob("*.prx"))
    if not libraries:
        raise RuntimeError(f"No prx libraries in {libs}")
    for library in libraries:
        shutil.copy2(library, macos / "libs" / library.name)
    # libSceAgcDriver opens libvulkan.1.dylib through its @loader_path rpath, so both go into libs.
    for name_in_sdk in ("libvulkan.1.dylib", "libMoltenVK.dylib"):
        source = (vulkan / "lib" / name_in_sdk).resolve()
        if not source.is_file():
            raise RuntimeError(f"Missing {name_in_sdk} in {vulkan / 'lib'}")
        shutil.copy2(source, macos / "libs" / name_in_sdk)
    manifest = json.loads((vulkan / "share" / "vulkan" / "icd.d" / "MoltenVK_icd.json").read_text())
    manifest["ICD"]["library_path"] = "../../../MacOS/libs/libMoltenVK.dylib"
    (resources / "vulkan" / "icd.d").mkdir(parents=True)
    (resources / "vulkan" / "icd.d" / "MoltenVK_icd.json").write_text(json.dumps(manifest, indent=4) + "\n")
    # SDL looks for anyps5-input.ini in the bundle's Resources.
    if input_config is not None:
        shutil.copy2(input_config, resources / "anyps5-input.ini")

    launcher = macos / "launch"
    launcher.write_text(LAUNCHER.format(identifier=identifier, title_id=title_id))
    launcher.chmod(0o755)
    icon = make_icon(app0 / "sce_sys" / "icon0.png", resources)
    info = {
        "CFBundleName": name,
        "CFBundleDisplayName": name,
        "CFBundleIdentifier": identifier,
        "CFBundleExecutable": "launch",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "LSMinimumSystemVersion": "11.0",
        "LSApplicationCategoryType": "public.app-category.games",
        "NSHighResolutionCapable": True,
    }
    if icon is not None:
        info["CFBundleIconFile"] = icon
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    return name, identifier


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--relinked", required=True, type=Path)
    parser.add_argument("--game", type=Path)
    parser.add_argument("--libs", required=True, type=Path)
    parser.add_argument("--vulkan", required=True, type=Path)
    parser.add_argument("--input-config", type=Path)
    parser.add_argument("--no-game-patches", action="store_true", help="leave the relinked eboot unpatched")
    parser.add_argument("bundle", type=Path)
    arguments = parser.parse_args()
    name, identifier = package(arguments.relinked, arguments.game, arguments.libs, arguments.vulkan, arguments.input_config, arguments.bundle, not arguments.no_game_patches)
    print(f"{arguments.bundle}: {name} ({identifier})")


if __name__ == "__main__":
    main()
