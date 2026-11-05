#!/bin/sh
# Signs a nightly that CI published unsigned (.github/workflows/engine-nightly.yml), on the
# release Mac, where the key is (docs/dev/SIGNED_UPDATES.md):
#
#     tools/release/sign_nightly.sh [-k <private key>]... <tag>
#
# It downloads every file of the pre-release <tag> from AnyTogether/AnyPS5-ARM, signs them with
# sign.sh (-k is passed on), checks the result with verify.sh and uploads SHA256SUMS and
# SHA256SUMS.sig to the release, replacing older ones. The launchers offer the nightly's engine
# once these are there. <tag> is an AnyPS5-ARM nightly (v<next>-arm-nightly.<YYYYMMDD>.<n>) or an
# upstream nightly (upstream-nightly.<YYYYMMDD>.<upstream commit>, upstream's main built
# unmodified by engine-nightly.yml).
set -eu
repo="AnyTogether/AnyPS5-ARM"
here="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "usage: $0 [-k <private key>]... <tag>" >&2; exit 2; }
keys=""
while getopts k: option; do
    case "$option" in
        k) keys="$keys -k $OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
tag="$1"
case "$tag" in
    v*-arm-nightly.*) ;;
    upstream-nightly.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].*) ;;
    *) echo "sign_nightly: $tag is not a nightly tag (v<next>-arm-nightly.<YYYYMMDD>.<n> or upstream-nightly.<YYYYMMDD>.<commit>)" >&2; exit 1 ;;
esac

command -v gh >/dev/null || { echo "sign_nightly: gh is needed" >&2; exit 1; }
[ "$(gh release view "$tag" --repo "$repo" --json isPrerelease --jq .isPrerelease)" = true ] ||
    { echo "sign_nightly: $tag is not a pre-release" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/files" "$scratch/signed"
gh release download "$tag" --repo "$repo" --dir "$scratch/files"
rm -f "$scratch/files/SHA256SUMS" "$scratch/files/SHA256SUMS.sig"
set -- "$scratch"/files/*
[ -f "$1" ] || { echo "sign_nightly: $tag has no files" >&2; exit 1; }
echo "signing $# files of $tag:"
for file in "$@"; do echo "  $(basename "$file")"; done

# shellcheck disable=SC2086
"$here/sign.sh" $keys -o "$scratch/signed" "$@"
cp "$scratch/signed/SHA256SUMS" "$scratch/signed/SHA256SUMS.sig" "$scratch/files/"
"$here/verify.sh" "$scratch/files"
gh release upload "$tag" "$scratch/signed/SHA256SUMS" "$scratch/signed/SHA256SUMS.sig" --repo "$repo" --clobber
echo "signed $tag: https://github.com/$repo/releases/tag/$tag"
