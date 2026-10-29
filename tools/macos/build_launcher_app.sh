#!/bin/sh
# Builds AnyPS5.app, the PS5-style launcher that finds game dumps, unlocks (converts) them and starts them.
#
#     tools/macos/build_launcher_app.sh <build dir> <Vulkan SDK macOS dir> <output dir>
#
# The build dir is a finished `ninja all libs` build (relinker and prx libraries); the Vulkan SDK
# provides the loader and MoltenVK that every unlocked title carries. MoltenVK is patched here
# (tools/macos/moltenvk_patches.py), so the launcher needs neither Python nor the developer tools.
set -eu
. "$(dirname "$0")/toolkit_layout.sh"

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
version="$(toolkit_release_version "$root")"
# The release keys the app trusts for its updates (docs/dev/SIGNED_UPDATES.md) must be the ones
# in tools/release/release-signing.pub.
"$root/tools/release/embed_keys.sh" --check --swift-only

swift build --package-path "$source" -c release --arch arm64 --arch x86_64 --product AnyPS5
products="$(swift build --package-path "$source" -c release --arch arm64 --arch x86_64 --show-bin-path)"
binary="$products/AnyPS5"
# WebRTC (party voice) is a framework beside the executable in the build; the app carries it in
# Contents/Frameworks.
webrtc="$(find "$products" -maxdepth 2 -name WebRTC.framework -type d | head -n 1)"
[ -n "$webrtc" ] || { echo "WebRTC.framework not found in $products" >&2; exit 1; }

rm -rf "$app"
toolkit="$app/Contents/Resources/toolkit"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/licenses"
cp "$binary" "$app/Contents/MacOS/AnyPS5"
mkdir -p "$app/Contents/Frameworks"
ditto "$webrtc" "$app/Contents/Frameworks/WebRTC.framework"
otool -l "$app/Contents/MacOS/AnyPS5" | grep -q "@executable_path/../Frameworks" ||
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$app/Contents/MacOS/AnyPS5"
webrtc_license="$(find "$source/.build/artifacts" -path '*WebRTC.xcframework/LICENSE' | head -n 1)"
make_toolkit "$root" "$build" "$vulkan" "$toolkit" "$version"
cp "$root/LICENSE" "$app/Contents/Resources/licenses/AnyPS5-LICENSE.txt"
cp "$vulkan/../Licenses/LICENSE.txt" "$app/Contents/Resources/licenses/VulkanSDK-LICENSE.txt"
[ -z "$webrtc_license" ] || cp "$webrtc_license" "$app/Contents/Resources/licenses/WebRTC-LICENSE.txt"
# The Noto fonts games get when they ask for the console's system fonts (SystemFonts.swift);
# Japanese, Chinese and Korean are downloaded the first time a game needs them.
mkdir -p "$app/Contents/Resources/fonts"
cp "$source"/Fonts/*.ttf "$source/Fonts/OFL.txt" "$app/Contents/Resources/fonts/"
cp "$source/Fonts/OFL.txt" "$app/Contents/Resources/licenses/Noto-OFL.txt"
# Play from a browser: the pad page the launcher serves to phones (BrowserPadServer.swift);
# AnyPS5-Desktop serves a copy of the same file.
mkdir -p "$app/Contents/Resources/browser-pad"
cp "$source/BrowserPad/index.html" "$app/Contents/Resources/browser-pad/index.html"
# The launcher's texts, one JSON file per language (l10n/TRANSLATING.md); AnyPS5-Desktop has the
# same format and keys in its assets/l10n.
mkdir -p "$app/Contents/Resources/l10n"
cp "$source"/l10n/*.json "$app/Contents/Resources/l10n/"

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
    <key>NSMicrophoneUsageDescription</key><string>AnyPS5 sends your voice to your friends in AnyTogether parties and calls while your microphone is on.</string>
    <key>NSLocalNetworkUsageDescription</key><string>AnyPS5 finds your phone on this network so it can be used as a controller.</string>
    <key>NSBonjourServices</key><array><string>_anyps5-remote._tcp</string></array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>AnyPS5 link</string>
            <key>CFBundleURLSchemes</key><array><string>anyps5</string></array>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Folder</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.folder</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>AnyPS5 Theme</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key><array><string>org.anyps5.theme</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>org.anyps5.theme</string>
            <key>UTTypeDescription</key><string>AnyPS5 Theme</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.archive</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>anyps5theme</string></array></dict>
        </dict>
    </array>
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
