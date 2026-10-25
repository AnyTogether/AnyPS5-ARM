#!/bin/sh
# Checks a signed release as the launchers do (docs/dev/SIGNED_UPDATES.md):
#
#     tools/release/verify.sh [--signature-only] <folder or SHA256SUMS>
#
# SHA256SUMS.sig must hold an Ed25519 signature of SHA256SUMS by a key in
# tools/release/release-signing.pub; then every file SHA256SUMS lists that lies beside it must
# match (files not there are named, not failed).
set -eu
. "$(dirname "$0")/common.sh"
openssl="$(release_openssl)"

files=1
if [ "${1:-}" = --signature-only ]; then files=0; shift; fi
[ $# -eq 1 ] || { echo "usage: $0 [--signature-only] <folder or SHA256SUMS>" >&2; exit 2; }
sums="$1"
[ -d "$sums" ] && sums="$sums/SHA256SUMS"
folder="$(dirname "$sums")"
[ -f "$sums" ] || { echo "no $sums" >&2; exit 1; }
[ -f "$sums.sig" ] || { echo "no $sums.sig: the release is not signed" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
good=""
while read -r kind id signature; do
    [ "$kind" = ed25519 ] || continue
    while read -r keykind public name; do
        [ "$keykind" = ed25519 ] && [ "$(release_key_id "$public")" = "$id" ] || continue
        printf '%s' "$signature" | base64 -d > "$scratch/signature" 2>/dev/null || continue
        { printf '302a300506032b6570032100' | xxd -r -p; printf '%s' "$public" | base64 -d; } > "$scratch/public.der"
        if "$openssl" pkeyutl -verify -pubin -keyform DER -inkey "$scratch/public.der" -rawin \
            -in "$sums" -sigfile "$scratch/signature" >/dev/null 2>&1; then
            echo "signature good: key $id ($name)"
            echo "$id" >> "$scratch/good"
        fi
    done < "$release_keys"
done < "$sums.sig"
[ -s "$scratch/good" ] || { echo "SHA256SUMS.sig is no good signature by a release key" >&2; exit 1; }
[ "$files" = 1 ] || exit 0

status=0
while read -r expected name; do
    if [ ! -f "$folder/$name" ]; then
        echo "not here: $name"
        continue
    fi
    if [ "$(shasum -a 256 "$folder/$name" | cut -d' ' -f1)" = "$expected" ]; then
        echo "ok: $name"
    else
        echo "DOES NOT MATCH: $name" >&2
        status=1
    fi
done < "$sums"
exit $status
