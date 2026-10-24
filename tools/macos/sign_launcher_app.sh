#!/bin/sh
# Signs AnyPS5.app for distribution outside the App Store and, with a notary profile, has Apple
# notarize it, so it opens without the "cannot be opened" warning.
#
#     tools/macos/sign_launcher_app.sh <AnyPS5.app> <identity> [<notarytool keychain profile>]
#
# identity: "Developer ID Application: Name (TEAM)", or - to sign ad hoc (no notarization).
# The profile is made once with `xcrun notarytool store-credentials <profile> ...`.
#
# Everything with code in it is signed from the inside out: the toolkit's relinker, its prx
# libraries and the Vulkan loader with MoltenVK (games copy these unchanged), then the app.
# Executables get the hardened runtime that notarization asks for. Games the launcher unlocks
# later are not signed here or anywhere: their relinked executables stay unsigned.
set -eu
. "$(dirname "$0")/toolkit_layout.sh"

if [ $# -lt 2 ]; then
    echo "usage: $0 <AnyPS5.app> <identity> [<notary profile>]" >&2
    exit 2
fi
app="$1"
identity="$2"
profile="${3:-}"
toolkit="$app/Contents/Resources/toolkit"

sign() {
    if [ "$identity" = "-" ]; then
        codesign --force --sign - "$@"
    else
        codesign --force --timestamp --sign "$identity" "$@"
    fi
}

sign_toolkit "$toolkit" "$identity"
# WebRTC for party voice, signed as ours so library validation lets the app load it.
[ ! -d "$app/Contents/Frameworks/WebRTC.framework" ] || sign "$app/Contents/Frameworks/WebRTC.framework"
# The microphone (party voice) under the hardened runtime.
sign --options runtime --entitlements "$(dirname "$0")/launcher/AnyPS5.entitlements" "$app"
codesign --verify --deep --strict "$app"
echo "signed $app"

[ -n "$profile" ] || exit 0
[ "$identity" != "-" ] || { echo "an ad hoc signature cannot be notarized" >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ditto -c -k --keepParent "$app" "$work/AnyPS5.zip"
xcrun notarytool submit "$work/AnyPS5.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"
echo "notarized $app"
