#!/bin/sh
# Builds AnyPS5.app, the PS5-style launcher that finds game dumps, unlocks (converts) them and starts them.
#
#     tools/macos/build_launcher_app.sh <build dir> <Vulkan SDK macOS dir> <output dir>
#
# The build dir is a finished `ninja all libs` build (relinker and prx libraries); the Vulkan SDK
# provides the loader and MoltenVK that every unlocked title carries. MoltenVK is patched here
# (tools/macos/moltenvk_patches.py), so the launcher needs neither Python nor the developer tools.
set -eu

if [ $# -ne 3 ]; then
    echo "usage: $0 <build dir> <Vulkan SDK macOS dir> <output dir>" >&2
    exit 2
fi
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$(cd "$1" && pwd)"
vulkan="$(cd "$2" && pwd)"
mkdir -p "$3"
output="$(cd "$3" && pwd)"
source="$root/tools/macos/launcher"
app="$output/AnyPS5.app"
version="$(git -C "$root" describe --tags --always 2>/dev/null | sed "s/^v//" || echo 0.0.0)"

swift build --package-path "$source" -c release --arch arm64 --arch x86_64 --product AnyPS5
binary="$(swift build --package-path "$source" -c release --arch arm64 --arch x86_64 --show-bin-path)/AnyPS5"

rm -rf "$app"
toolkit="$app/Contents/Resources/toolkit"
mkdir -p "$app/Contents/MacOS" "$toolkit/libs" "$toolkit/vulkan" "$toolkit/patches" "$app/Contents/Resources/licenses"
cp "$binary" "$app/Contents/MacOS/AnyPS5"
cp "$build/core/relinker/relinker" "$toolkit/relinker"
cp "$build"/core/libs/libs/*.prx "$toolkit/libs/"
cp -L "$vulkan/lib/libvulkan.1.dylib" "$vulkan/lib/libMoltenVK.dylib" "$toolkit/vulkan/"
chmod u+w "$toolkit/vulkan/"*.dylib
python3 "$root/tools/macos/moltenvk_patches.py" "$toolkit/vulkan/libMoltenVK.dylib"
sed 's#"library_path": "[^"]*"#"library_path": "../../../MacOS/libs/libMoltenVK.dylib"#' "$vulkan/share/vulkan/icd.d/MoltenVK_icd.json" > "$toolkit/vulkan/MoltenVK_icd.json"
cp "$root"/tools/macos/patches/*.json "$toolkit/patches/"
# An installed game made by another toolkit can be installed again (the launcher offers it).
fingerprint="$(cat "$toolkit/relinker" "$toolkit"/libs/*.prx "$toolkit"/patches/*.json | shasum -a 256 | cut -c1-12)"
echo "$version-$fingerprint" > "$toolkit/version.txt"
cp "$root/LICENSE" "$app/Contents/Resources/licenses/AnyPS5-LICENSE.txt"
cp "$vulkan/../Licenses/LICENSE.txt" "$app/Contents/Resources/licenses/VulkanSDK-LICENSE.txt"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swift "$source/icon.swift" "$scratch/icon.png"
mkdir "$scratch/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size "$scratch/icon.png" --out "$scratch/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$scratch/icon.png" --out "$scratch/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$scratch/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AnyPS5</string>
    <key>CFBundleDisplayName</key><string>AnyPS5</string>
    <key>CFBundleIdentifier</key><string>org.anyps5.launcher</string>
    <key>CFBundleExecutable</key><string>AnyPS5</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>GCSupportsControllerUserInteraction</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>AnyPS5 finds your phone on this network so it can be used as a controller.</string>
    <key>NSBonjourServices</key><array><string>_anyps5-remote._tcp</string></array>
</dict>
</plist>
EOF

# ANYPS5_SIGN_IDENTITY ("Developer ID Application: …") signs it for distribution and, with
# ANYPS5_NOTARY_PROFILE, has it notarized; without them it is signed ad hoc.
if [ -n "${ANYPS5_SIGN_IDENTITY:-}" ]; then
    "$root/tools/macos/sign_launcher_app.sh" "$app" "$ANYPS5_SIGN_IDENTITY" "${ANYPS5_NOTARY_PROFILE:-}"
else
    codesign --force --deep --sign - "$app"
fi
echo "$app"
