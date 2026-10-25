#!/bin/sh
# Writes the keys of tools/release/release-signing.pub into both launchers as constants:
#
#     tools/release/embed_keys.sh [--check] [<AnyPS5-Desktop folder>]
#
# The macOS launcher's Sources/AnyPS5Core/ReleaseKeys.swift, and AnyPS5 Desktop's
# lib/core/release_keys.dart when its folder is given, in ANYPS5_DESKTOP, or beside this
# repository's folder. --check changes nothing and fails when a constant differs from the file
# (the launcher build runs it).
set -eu
. "$(dirname "$0")/common.sh"

check=0
if [ "${1:-}" = --check ]; then check=1; shift; fi
desktop="${1:-${ANYPS5_DESKTOP:-$release_root/../../AnyPS5-Desktop}}"
[ -f "$release_keys" ] || { echo "no $release_keys (tools/release/keygen.sh makes it)" >&2; exit 1; }

lines="$(grep '^ed25519 ' "$release_keys" || true)"
[ -n "$lines" ] || { echo "$release_keys lists no key" >&2; exit 1; }
printf '%s\n' "$lines" | while read -r kind public name rest; do
    [ -n "$name" ] && [ -z "$rest" ] && [ "$(printf '%s' "$public" | base64 -d 2>/dev/null | wc -c | tr -d ' ')" = 32 ] || {
        echo "$release_keys: not a key line: $kind $public $name $rest" >&2
        exit 1
    }
done

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
{
    echo "// Written by tools/release/embed_keys.sh from tools/release/release-signing.pub: change that"
    echo "// file and run the script rather than editing this one."
    echo
    echo "/// The Ed25519 public keys AnyPS5 releases are signed with, \"ed25519 <base64> <name>\" a line"
    echo "/// (docs/dev/SIGNED_UPDATES.md in AnyPS5-ARM)."
    echo "enum ReleaseKeys {"
    echo '    static let list = """'
    printf '%s\n' "$lines" | sed 's/^/    /'
    echo '    """'
    echo "}"
} > "$scratch/swift"
{
    echo "// Written by tools/release/embed_keys.sh in AnyPS5-ARM from tools/release/release-signing.pub:"
    echo "// change that file and run the script rather than editing this one."
    echo
    echo "/// The Ed25519 public keys AnyPS5 releases are signed with, \"ed25519 <base64> <name>\" a line"
    echo "/// (docs/dev/SIGNED_UPDATES.md in AnyPS5-ARM)."
    echo "const releaseKeys = '''"
    printf '%s\n' "$lines"
    echo "''';"
} > "$scratch/dart"

status=0
place() {
    if [ "$check" = 1 ]; then
        cmp -s "$1" "$2" || { echo "$2 does not match $release_keys: run tools/release/embed_keys.sh" >&2; status=1; }
    elif ! cmp -s "$1" "$2"; then
        cp "$1" "$2"
        echo "wrote $2"
    fi
}
place "$scratch/swift" "$release_root/tools/macos/launcher/Sources/AnyPS5Core/ReleaseKeys.swift"
if [ -d "$desktop/lib/core" ]; then
    place "$scratch/dart" "$desktop/lib/core/release_keys.dart"
elif [ $# -gt 0 ] || [ -n "${ANYPS5_DESKTOP:-}" ]; then
    echo "$desktop is no AnyPS5 Desktop folder" >&2
    status=1
fi
exit $status
