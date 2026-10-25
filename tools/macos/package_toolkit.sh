#!/bin/sh
# Packs the engine toolkit (relinker, system libraries, patched MoltenVK, per-title patches) as a
# release download the launcher's engine picker lists and switches to:
#
#     tools/macos/package_toolkit.sh <build dir> <Vulkan SDK macOS dir> <output dir>
#
# Writes <output dir>/AnyPS5-toolkit-macos-<release version>.zip: one folder of that name with the
# same layout as the toolkit inside AnyPS5.app (tools/macos/toolkit_layout.sh) and a toolkit.json
# naming every file's sha256. Attach it to the release, signed with the release's other files by
# tools/release/sign.sh (docs/dev/SIGNED_UPDATES.md); the launcher finds it by its name.
#
# ANYPS5_SIGN_IDENTITY signs the toolkit's code first, as sign_launcher_app.sh does in the app.
# ANYPS5_TOOLKIT_MIN_LAUNCHER is the oldest launcher that may use it (default: the first one
# with the engine picker).
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
version="$(toolkit_release_version "$root")"
name="AnyPS5-toolkit-macos-$version"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
toolkit="$scratch/$name"
make_toolkit "$root" "$build" "$vulkan" "$toolkit" "$version"
[ -z "${ANYPS5_SIGN_IDENTITY:-}" ] || sign_toolkit "$toolkit" "$ANYPS5_SIGN_IDENTITY"
write_toolkit_manifest "$root" "$toolkit" "${ANYPS5_TOOLKIT_MIN_LAUNCHER:-0.2.15}"

zip="$output/$name.zip"
rm -f "$zip"
ditto -c -k --norsrc --noextattr --keepParent "$toolkit" "$zip"
echo "$(shasum -a 256 "$zip" | cut -d' ' -f1)  $name.zip" > "$zip.sha256"
echo "$zip ($(cat "$toolkit/version.txt"))"
