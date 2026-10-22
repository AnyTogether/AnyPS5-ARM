#!/bin/sh
# Installs the latest AnyPS5 launcher into /Applications (or ~/Applications):
#
#     curl -fsSL https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/install.sh | sh
#
# A download through curl carries no quarantine flag, so macOS opens the app without the
# "cannot be opened" / "damaged" warnings it shows for unsigned apps downloaded in a browser.
set -eu

repository="${ANYPS5_REPOSITORY:-utkuhalis/AnyPS5-ARM}"
url="https://github.com/$repository/releases/latest/download/AnyPS5-macOS.zip"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "AnyPS5: downloading $url"
curl -fL --progress-bar "$url" -o "$scratch/AnyPS5-macOS.zip"
ditto -x -k "$scratch/AnyPS5-macOS.zip" "$scratch/unpacked"
app="$(find "$scratch/unpacked" -maxdepth 2 -name 'AnyPS5.app' -type d | head -n 1)"
if [ -z "$app" ]; then
    echo "AnyPS5: the download holds no AnyPS5.app" >&2
    exit 1
fi

target=/Applications
if [ ! -w "$target" ]; then
    target="$HOME/Applications"
    mkdir -p "$target"
fi
rm -rf "$target/AnyPS5.app"
ditto "$app" "$target/AnyPS5.app"
xattr -dr com.apple.quarantine "$target/AnyPS5.app" 2>/dev/null || true
xattr -dr com.apple.provenance "$target/AnyPS5.app" 2>/dev/null || true

if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
    echo "AnyPS5: games run through Rosetta; installing it (macOS asks for your password)"
    softwareupdate --install-rosetta --agree-to-license || echo "AnyPS5: install Rosetta later from the launcher's settings" >&2
fi

echo "AnyPS5: installed $target/AnyPS5.app"
open "$target/AnyPS5.app"
