#!/bin/sh
# Signs the files of a release (docs/dev/SIGNED_UPDATES.md):
#
#     tools/release/sign.sh [-k <private key>]... [-o <folder>] <file>...
#
# Writes SHA256SUMS ("<sha256>  <file name>" for each file, sorted by name, as shasum prints it)
# and SHA256SUMS.sig (one line per key: "ed25519 <key ID> <Ed25519 signature of SHA256SUMS,
# base64>") into <folder>, by default the first file's folder; attach both to the release with
# the files. The key is ~/.config/anyps5/release-signing.key unless -k names others (during a
# rotation: -k for the current key and -k for the next one). Every key must be listed in
# tools/release/release-signing.pub; the result is checked with verify.sh before it is kept.
set -eu
. "$(dirname "$0")/common.sh"
openssl="$(release_openssl)"

usage() { echo "usage: $0 [-k <private key>]... [-o <folder>] <file>..." >&2; exit 2; }
keys=""
out=""
while getopts k:o: option; do
    case "$option" in
        k) keys="$keys$OPTARG
" ;;
        o) out="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || usage
[ -n "$keys" ] || keys="$release_key
"
[ -n "$out" ] || out="$(dirname "$1")"
mkdir -p "$out"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
names=""
for file in "$@"; do
    [ -f "$file" ] || { echo "$file is not a file" >&2; exit 1; }
    name="$(basename "$file")"
    case "$name" in
        SHA256SUMS|SHA256SUMS.sig) echo "$file: the sums are not signed as a release file" >&2; exit 1 ;;
        *[[:space:]]*) echo "$file: release file names have no spaces" >&2; exit 1 ;;
    esac
    case "
$names" in
        *"
$name
"*) echo "two files are named $name" >&2; exit 1 ;;
    esac
    names="$names$name
"
    echo "$(shasum -a 256 "$file" | cut -d' ' -f1)  $name" >> "$scratch/unsorted"
done
LC_ALL=C sort -k2 "$scratch/unsorted" > "$scratch/SHA256SUMS"

: > "$scratch/SHA256SUMS.sig"
printf '%s' "$keys" | while IFS= read -r key; do
    [ -n "$key" ] || continue
    release_check_private "$key"
    public="$(release_public_key "$key")"
    grep -q "^ed25519 $public " "$release_keys" || {
        echo "$key is not listed in $release_keys; the launchers would not trust it" >&2
        exit 1
    }
    "$openssl" pkeyutl -sign -inkey "$key" -rawin -in "$scratch/SHA256SUMS" -out "$scratch/signature"
    echo "ed25519 $(release_key_id "$public") $(base64 < "$scratch/signature" | tr -d '\n')" >> "$scratch/SHA256SUMS.sig"
done
[ -s "$scratch/SHA256SUMS.sig" ] || { echo "nothing was signed" >&2; exit 1; }
"$release_dir/verify.sh" --signature-only "$scratch/SHA256SUMS" >/dev/null
mv "$scratch/SHA256SUMS" "$out/SHA256SUMS"
mv "$scratch/SHA256SUMS.sig" "$out/SHA256SUMS.sig"
cat "$out/SHA256SUMS"
echo "signed: $out/SHA256SUMS and $out/SHA256SUMS.sig"
