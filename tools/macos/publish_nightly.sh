#!/bin/sh
# Publishes a nightly build of main as a GitHub pre-release, for the launcher's Nightly update
# channel (Settings → About → Update Channel) and its engine picker:
#
#     tools/macos/publish_nightly.sh [--dry-run]
#
# From the main branch, up to date with origin/main and without uncommitted changes, it
#   1. names the build v<next>-arm-nightly.<YYYYMMDD>.<n>: <next> is the last release with its
#      last number raised (v0.2.16-arm → 0.2.17), <n> counts that day's nightlies from 1 (UTC);
#      Updates.Version in the launcher sorts these after the release before them and before the
#      release they lead to, so Stable never offers going back to an older release;
#   2. tags HEAD with it (git describe then gives the version the app and toolkit carry);
#   3. builds the engine (ninja all libs), AnyPS5.app (build_launcher_app.sh) zipped as
#      AnyPS5-macOS.zip, the engine toolkit (package_toolkit.sh) and the phone app
#      (AnyPS5-Remote.apk and an unsigned AnyPS5-Remote.ipa, as in mobile/README.md);
#   4. signs them with tools/release/sign.sh (SHA256SUMS and SHA256SUMS.sig), pushes the tag
#      and publishes the pre-release with those files and short notes: the commits since the
#      last release (git log).
#
# --dry-run prints the tag and the notes and stops: nothing is tagged, built or published.
#
# Environment:
#   ANYPS5_BUILD          the engine's CMake build folder (default: build-mac)
#   ANYPS5_VULKAN_SDK     the Vulkan SDK's macOS folder (default: ~/VulkanSDK/1.4.363.0/macOS)
#   ANYPS5_NIGHTLY_OUT    where the files are made (default: build-nightly/<tag>)
#   ANYPS5_SKIP_ENGINE=1  use the build folder as it is, without running ninja
#   ANYPS5_SKIP_PHONE=1   publish without the phone app
#   ANYPS5_SKIP_SIGN=1    publish without SHA256SUMS(.sig) (the release key is not on this Mac);
#                         launchers that check signatures then refuse its app and engine
#   ANYPS5_SIGN_IDENTITY, ANYPS5_NOTARY_PROFILE  as for build_launcher_app.sh
#   ANYPS5_ENGINE_ARCHIVES  the Windows and Linux engine archives for AnyPS5 Desktop
#                         (AnyPS5-toolkit-<windows|linux>-<commit>.zip/.tar.gz), built from this
#                         commit on a Windows machine and its WSL as in
#                         docs/dev/WINDOWS_LINUX_ENGINE.md; attached and signed with the rest.
#                         This Mac cannot build them; without them the release has no
#                         Windows/Linux engine of its own.
set -eu

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
repo="AnyTogether/AnyPS5-ARM"

# 1. Where we are.
branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = main ] || { echo "publish_nightly: on $branch, not main" >&2; exit 1; }
git fetch -q --tags origin main
if [ "$dry" = 0 ]; then
    [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "publish_nightly: uncommitted changes" >&2; exit 1; }
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "publish_nightly: HEAD is not origin/main (pull or push first)" >&2; exit 1; }
fi

# The last release: the highest vX.Y.Z-arm tag (nightly tags have more after -arm).
last="$(git tag -l 'v*-arm' | grep -E '^v[0-9]+(\.[0-9]+)*-arm$' | sed 's/^v//; s/-arm$//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
[ -n "$last" ] || { echo "publish_nightly: no release tag found" >&2; exit 1; }
next="$(echo "$last" | awk -F. '{ $NF = $NF + 1; print }' OFS=.)"
day="$(date -u +%Y%m%d)"
# The fetch above brought every tag on GitHub.
existing="$(git tag -l "v$next-arm-nightly.$day.*")"
# Run again after a failure: the day's tag already on HEAD and not yet pushed is used again.
tag=""
for candidate in $existing; do
    if [ "$(git rev-list -n 1 "$candidate" 2>/dev/null)" = "$(git rev-parse HEAD)" ] &&
        ! git ls-remote --exit-code --tags origin "$candidate" >/dev/null 2>&1; then
        tag="$candidate"
    fi
done
if [ -z "$tag" ]; then
    count=1
    for candidate in $existing; do
        n="${candidate##*.}"
        case "$n" in *[!0-9]*|'') continue ;; esac
        [ "$n" -ge "$count" ] && count=$((n + 1))
    done
    tag="v$next-arm-nightly.$day.$count"
fi
version="${tag#v}"

# The notes: what changed since the last release, stable or nightly, newest first.
previous="$(git tag -l 'v*-arm' 'v*-arm-nightly.*' --sort=-creatordate --merged HEAD | grep -vx "$tag" | head -n 1)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
notes="$scratch/notes.md"
{
    echo "Nightly build of main, $(date -u +%Y-%m-%d), $(git rev-parse --short=12 HEAD). It may have new bugs: the launcher offers it only on the Nightly update channel (Settings → About → Update Channel), and it never replaces a newer release."
    echo
    echo "Since ${previous:-the start}:"
    echo
    git log --no-merges --format='- %s' ${previous:+"$previous..HEAD"} | head -n 40
    total="$(git rev-list --no-merges --count ${previous:+"$previous..HEAD"})"
    [ "$total" -le 40 ] || echo "- … and $((total - 40)) more"
    echo
    echo "macOS: download AnyPS5-macOS.zip, or switch an installed launcher to the Nightly channel. Phone: AnyPS5-Remote.apk (Android), AnyPS5-Remote.ipa (iPhone, sideloaded with AltStore or Sideloadly)."
} > "$notes"

echo "tag: $tag"
echo "---"
cat "$notes"
echo "---"
[ "$dry" = 0 ] || exit 0

command -v gh >/dev/null || { echo "publish_nightly: gh is needed to publish" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "publish_nightly: gh is not signed in" >&2; exit 1; }

# 2. The tag, so that git describe names the build.
git rev-parse -q --verify "refs/tags/$tag" >/dev/null ||
    git -c user.name="Utku Halis" -c user.email="personal@utkuhalis.com.tr" tag -a "$tag" -m "Nightly $version"
[ "$(git describe --tags)" = "$tag" ] || { echo "publish_nightly: git describe does not give $tag" >&2; exit 1; }

# 3. The files.
build="${ANYPS5_BUILD:-build-mac}"
vulkan="${ANYPS5_VULKAN_SDK:-$HOME/VulkanSDK/1.4.363.0/macOS}"
out="${ANYPS5_NIGHTLY_OUT:-$root/build-nightly/$tag}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
[ "${ANYPS5_SKIP_ENGINE:-0}" = 1 ] || ninja -C "$build" all libs
"$root/tools/macos/build_launcher_app.sh" "$build" "$vulkan" "$out"
built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$out/AnyPS5.app/Contents/Info.plist")"
[ "$built" = "$version" ] || { echo "publish_nightly: the app says $built, not $version" >&2; exit 1; }
rm -f "$out/AnyPS5-macOS.zip"
ditto -c -k --keepParent "$out/AnyPS5.app" "$out/AnyPS5-macOS.zip"
"$root/tools/macos/package_toolkit.sh" "$build" "$vulkan" "$out"
files="$out/AnyPS5-macOS.zip $out/AnyPS5-toolkit-macos-$version.zip $out/AnyPS5-toolkit-macos-$version.zip.sha256"
if [ "${ANYPS5_SKIP_PHONE:-0}" != 1 ]; then
    (cd "$root/mobile" && flutter build apk --release && flutter build ios --release --no-codesign)
    cp "$root/mobile/build/app/outputs/flutter-apk/app-release.apk" "$out/AnyPS5-Remote.apk"
    rm -rf "$scratch/Payload" "$out/AnyPS5-Remote.ipa"
    mkdir "$scratch/Payload"
    ditto "$root/mobile/build/ios/iphoneos/Runner.app" "$scratch/Payload/Runner.app"
    (cd "$scratch" && zip -qry "$out/AnyPS5-Remote.ipa" Payload)
    files="$files $out/AnyPS5-Remote.apk $out/AnyPS5-Remote.ipa"
fi

for archive in ${ANYPS5_ENGINE_ARCHIVES:-}; do
    case "$(basename "$archive")" in
        AnyPS5-toolkit-windows-*.zip|AnyPS5-toolkit-linux-*.zip|AnyPS5-toolkit-linux-*.tar.gz) ;;
        *) echo "publish_nightly: $archive is not named AnyPS5-toolkit-<windows|linux>-<commit>.zip/.tar.gz" >&2; exit 1 ;;
    esac
    [ -s "$archive" ] || { echo "publish_nightly: $archive is missing or empty" >&2; exit 1; }
    cp "$archive" "$out/"
    files="$files $out/$(basename "$archive")"
done
[ -n "${ANYPS5_ENGINE_ARCHIVES:-}" ] || echo "publish_nightly: no Windows/Linux engine (ANYPS5_ENGINE_ARCHIVES, docs/dev/WINDOWS_LINUX_ENGINE.md)" >&2

# Signed as releases are (docs/dev/SIGNED_UPDATES.md), so the launcher's check accepts it.
if [ "${ANYPS5_SKIP_SIGN:-0}" != 1 ]; then
    # shellcheck disable=SC2086
    "$root/tools/release/sign.sh" -o "$out" $files
    files="$files $out/SHA256SUMS $out/SHA256SUMS.sig"
fi

# 4. Published as a pre-release, never as the latest release.
git push origin "refs/tags/$tag"
# shellcheck disable=SC2086
gh release create "$tag" $files --repo "$repo" --verify-tag --prerelease --latest=false \
    --title "AnyPS5-ARM $version (nightly)" --notes-file "$notes"
echo "published $tag: https://github.com/$repo/releases/tag/$tag"
