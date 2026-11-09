#!/bin/sh
# Adds the macOS app and engine to a nightly that CI published (.github/workflows/engine-nightly.yml)
# and signs it, on the release Mac, where the signing key is (docs/dev/SIGNED_UPDATES.md):
#
#     tools/release/nightly_mac.sh [--dry-run] [<tag>]
#     tools/release/nightly_mac.sh --install
#
# Without <tag> it takes the newest nightly pre-release of today or yesterday (UTC); with none it
# exits quietly. It checks out the nightly's commit in a worktree of its own (detached, reused
# from day to day so the builds are incremental), builds the engine (ninja all libs), AnyPS5.app
# (build_launcher_app.sh) zipped as AnyPS5-macOS.zip and the engine toolkit (package_toolkit.sh),
# as tools/macos/publish_nightly.sh and the releases do, and uploads them to the pre-release. The
# phone app (AnyPS5-Remote.apk, unsigned AnyPS5-Remote.ipa) is built only when mobile/ changed
# since the last release; otherwise the release's phone app is the current one. Then
# sign_nightly.sh signs every file of the pre-release, and verify.sh checks the signature.
#
# Run again, it does only what is missing: with the Mac files there it only signs again, when
# SHA256SUMS does not list every file.
#
# First it signs the upstream nightlies of today or yesterday (UTC) that are not signed yet
# (upstream-nightly.<YYYYMMDD>.<commit>: upstream's main, built unmodified by engine-nightly.yml)
# and AnyPS5 Desktop's (AnyTogether/AnyPS5-Desktop, v<next>-nightly.<YYYYMMDD>.<n>, built by CI in
# that repository), with sign_nightly.sh and verify.sh as they are on origin/main; nothing is
# built for them, and they get no Mac files. With such a <tag> it signs only that one.
#
# It does nothing (and exits 0, so the next day tries again) when less than 6 GB of disk is free
# or a game is running (an eboot under <games>/.AnyPS5/Games). A game started during the build
# holds back the upload and the signing, up to 4 hours.
#
# --dry-run prints the tag, the commit and what it would build and upload; it builds, uploads
# and changes nothing.
# --install installs the daily launchd agent net.anytogether.anyps5.nightly-mac: a copy of this
# script in ~/Library/Application Support/AnyPS5/nightly-mac (refreshed from each nightly's
# commit), run at 04:45 UTC (the hour is converted to the Mac's time zone when installing) under
# `taskpolicy -b`, logging to ~/Library/Logs/AnyPS5/nightly-mac.log.
#
# Environment:
#   ANYPS5_NIGHTLY_REPO      the repository the worktree belongs to (default: the main checkout
#                            of the repository this script is in)
#   ANYPS5_NIGHTLY_WORKTREE  the worktree (default: AnyPS5-nightly beside the repository)
#   ANYPS5_VULKAN_SDK        the Vulkan SDK's macOS folder (default: ~/VulkanSDK/1.4.363.0/macOS)
#   ANYPS5_NIGHTLY_PHONE     1: always build the phone app, 0: never (default: when mobile/ changed)
#   ANYPS5_SIGN_IDENTITY, ANYPS5_NOTARY_PROFILE  as for build_launcher_app.sh (without them the app
#                            is signed ad hoc, as the releases are now)
set -eu
slug="AnyTogether/AnyPS5-ARM"
desktop_slug="AnyTogether/AnyPS5-Desktop"
label="net.anytogether.anyps5.nightly-mac"
min_free_kb=$((6 * 1024 * 1024))
self="$0"
here="$(cd "$(dirname "$0")" && pwd)"
support="$HOME/Library/Application Support/AnyPS5/nightly-mac"
logs="$HOME/Library/Logs/AnyPS5"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] nightly_mac: $*"; }
die() { log "error: $*" >&2; exit 1; }

dry=0
install=0
tag=""
for argument in "$@"; do
    case "$argument" in
        --dry-run) dry=1 ;;
        --install) install=1 ;;
        -*) echo "usage: $0 [--dry-run] [<tag>] | --install" >&2; exit 2 ;;
        *) [ -z "$tag" ] || { echo "usage: $0 [--dry-run] [<tag>] | --install" >&2; exit 2; }; tag="$argument" ;;
    esac
done

if [ -n "${ANYPS5_NIGHTLY_REPO:-}" ]; then
    repo="$ANYPS5_NIGHTLY_REPO"
else
    # The repository's main checkout, also when this script runs from another worktree of it.
    repo="$(git -C "$here" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
    [ -n "$repo" ] || die "not in a checkout: set ANYPS5_NIGHTLY_REPO"
fi
repo="$(cd "$repo" && pwd)"
wt="${ANYPS5_NIGHTLY_WORKTREE:-$(dirname "$repo")/AnyPS5-nightly}"
vulkan="${ANYPS5_VULKAN_SDK:-$HOME/VulkanSDK/1.4.363.0/macOS}"

# --install: the launchd agent, from this checkout.
if [ "$install" = 1 ]; then
    [ "$dry" = 0 ] && [ -z "$tag" ] || { echo "usage: $0 --install" >&2; exit 2; }
    mkdir -p "$support" "$logs" "$HOME/Library/LaunchAgents"
    cp "$self" "$support/nightly_mac.sh.new" && chmod 755 "$support/nightly_mac.sh.new"
    mv -f "$support/nightly_mac.sh.new" "$support/nightly_mac.sh"
    # launchd counts in local time: 04:45 UTC in this Mac's offset now (a summer-time change
    # moves it by an hour until --install runs again).
    offset="$(date +%z)"
    sign=1; case "$offset" in -*) sign=-1 ;; esac
    offset_hours="$(echo "$offset" | cut -c2-3 | sed 's/^0//')"
    offset_minutes="$(echo "$offset" | cut -c4-5 | sed 's/^0//')"
    minutes=$(( (4 * 60 + 45 + sign * (${offset_hours:-0} * 60 + ${offset_minutes:-0}) + 24 * 60) % (24 * 60) ))
    hour=$((minutes / 60)); minute=$((minutes % 60))
    path="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    flutter="$(command -v flutter 2>/dev/null || true)"
    [ -z "$flutter" ] || path="$(dirname "$flutter"):$path"
    plist="$HOME/Library/LaunchAgents/$label.plist"
    {
        cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/sbin/taskpolicy</string>
        <string>-b</string>
        <string>/bin/sh</string>
        <string>$support/nightly_mac.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>
    <key>StandardOutPath</key><string>$logs/nightly-mac.log</string>
    <key>StandardErrorPath</key><string>$logs/nightly-mac.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$path</string>
        <key>ANYPS5_NIGHTLY_REPO</key><string>$repo</string>
        <key>ANYPS5_NIGHTLY_WORKTREE</key><string>$wt</string>
EOF
        for name in ANYPS5_VULKAN_SDK ANYPS5_NIGHTLY_PHONE ANYPS5_SIGN_IDENTITY ANYPS5_NOTARY_PROFILE; do
            eval "value=\${$name:-}"
            # shellcheck disable=SC2154
            [ -z "$value" ] || echo "        <key>$name</key><string>$value</string>"
        done
        cat <<EOF
    </dict>
</dict>
</plist>
EOF
    } > "$plist"
    plutil -lint "$plist" >/dev/null
    domain="gui/$(id -u)"
    launchctl bootout "$domain/$label" 2>/dev/null || true
    launchctl bootstrap "$domain" "$plist"
    log "installed $plist: daily at $(printf '%02d:%02d' "$hour" "$minute") local time (04:45 UTC), log $logs/nightly-mac.log"
    exit 0
fi

# What would stop a run; a dry run only reports it.
skip() {
    if [ "$dry" = 1 ]; then log "a real run would skip now: $1"; else log "skipped: $1"; exit 0; fi
}
game_running() {
    # shellcheck disable=SC2009
    ps -axww -o stat= -o args= | grep -v '^Z' | grep -q '/\.AnyPS5/Games/[^ ]*/eboot'
}
free_kb="$(df -k "$(dirname "$wt")" | awk 'NR == 2 { print $4 }')"
[ "$free_kb" -ge "$min_free_kb" ] || skip "only $((free_kb / 1024 / 1024)) GB of disk free, 6 GB needed"
! game_running || skip "a game is running"

# One run at a time.
lock="$HOME/Library/Caches/AnyPS5/nightly-mac.lock"
if [ "$dry" = 0 ]; then
    mkdir -p "$(dirname "$lock")"
    if ! mkdir "$lock" 2>/dev/null; then
        if kill -0 "$(cat "$lock/pid" 2>/dev/null || echo 0)" 2>/dev/null; then log "skipped: another run is going on"; exit 0; fi
        rm -rf "$lock"; mkdir "$lock"
    fi
    echo $$ > "$lock/pid"
fi
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"; [ "$dry" = 1 ] || rm -rf "$lock"' EXIT

command -v gh >/dev/null || die "gh is needed"
gh auth status >/dev/null 2>&1 || die "gh is not signed in"

# The repository assets and signed read: this one, or AnyPS5 Desktop's while its nightlies are signed.
release_repo="$slug"
assets() { gh release view "$tag" --repo "$release_repo" --json assets --jq '.assets[].name' > "$scratch/assets"; }

# Signed when SHA256SUMS(.sig) are there and SHA256SUMS names every other file.
signed() {
    grep -qx SHA256SUMS "$scratch/assets" && grep -qx SHA256SUMS.sig "$scratch/assets" || return 1
    rm -rf "$scratch/sums"; mkdir "$scratch/sums"
    gh release download "$tag" --repo "$release_repo" --dir "$scratch/sums" --pattern SHA256SUMS --pattern SHA256SUMS.sig || return 1
    awk '{ print $2 }' "$scratch/sums/SHA256SUMS" | sort > "$scratch/sums/listed"
    grep -vxE 'SHA256SUMS(\.sig)?' "$scratch/assets" | sort > "$scratch/sums/wanted"
    cmp -s "$scratch/sums/listed" "$scratch/sums/wanted"
}

# Upstream nightlies and AnyPS5 Desktop's: signed only. This script's own folder may be the
# installed copy, with no signing scripts beside it, and these tags are in none of main's
# history: the scripts come from origin/main, unpacked into the scratch folder.
upstream_tools="$scratch/main/tools/release"
sign_only() {  # <tag> <repository>
    tag="$1"
    release_repo="$2"
    what="upstream nightly"
    [ "$release_repo" != "$desktop_slug" ] || what="AnyPS5 Desktop nightly"
    state="$(gh release view "$tag" --repo "$release_repo" --json isPrerelease,isDraft --jq '.isPrerelease and (.isDraft | not)')" ||
        { log "error: $tag has no release"; return 1; }
    [ "$state" = true ] || { log "error: $tag is not a published pre-release"; return 1; }
    assets || return 1
    if signed; then log "$what $tag is signed over every file"; return 0; fi
    if [ "$dry" = 1 ]; then
        echo "$what $tag: unsigned; would sign it with sign_nightly.sh from origin/main, then verify.sh --signature-only"
        return 0
    fi
    if game_running; then log "skipped signing $tag: a game is running (the next run tries again)"; return 0; fi
    if [ ! -x "$upstream_tools/sign_nightly.sh" ]; then
        git -C "$repo" fetch -q origin main || { log "error: cannot fetch origin/main for the signing scripts"; return 1; }
        mkdir -p "$scratch/main"
        git -C "$repo" archive origin/main tools/release | tar -x -C "$scratch/main" || return 1
    fi
    log "signing $what $tag (no Mac build for it)"
    "$upstream_tools/sign_nightly.sh" -R "$release_repo" "$tag" || { log "error: sign_nightly.sh $tag failed"; return 1; }
    assets || return 1
    signed || { log "error: SHA256SUMS of $tag does not list every file after signing"; return 1; }
    "$upstream_tools/verify.sh" --signature-only "$scratch/sums" || { log "error: the signature of $tag does not verify"; return 1; }
    log "signed $what: https://github.com/$release_repo/releases/tag/$tag"
}
case "$tag" in
    upstream-nightly.*)
        sign_only "$tag" "$slug" || exit 1
        exit 0 ;;
    v*-arm-nightly.*) ;;
    v*-nightly.*)
        sign_only "$tag" "$desktop_slug" || exit 1
        exit 0 ;;
    '')
        today="$(date -u +%Y%m%d)"
        yesterday="$(date -u -v-1d +%Y%m%d)"
        upstream_tags="$(gh api "repos/$slug/releases?per_page=40" --jq "
            [.[] | select(.draft | not) | select(.prerelease)
                 | select(.tag_name | test(\"^upstream-nightly\\\\.($today|$yesterday)\\\\.[0-9a-f]+\$\"))]
            | sort_by(.created_at) | .[].tag_name")" || upstream_tags=""
        [ -n "$upstream_tags" ] || log "no upstream nightly of $today or $yesterday (UTC) to sign"
        for upstream_tag in $upstream_tags; do
            sign_only "$upstream_tag" "$slug" || log "upstream nightly $upstream_tag is left unsigned; the next run tries again"
        done
        desktop_tags="$(gh api "repos/$desktop_slug/releases?per_page=40" --jq "
            [.[] | select(.draft | not) | select(.prerelease)
                 | select(.tag_name | test(\"^v[0-9.]+-nightly\\\\.($today|$yesterday)\\\\.[0-9]+\$\"))]
            | sort_by(.created_at) | .[].tag_name")" || desktop_tags=""
        [ -n "$desktop_tags" ] || log "no AnyPS5 Desktop nightly of $today or $yesterday (UTC) to sign"
        for desktop_tag in $desktop_tags; do
            sign_only "$desktop_tag" "$desktop_slug" || log "AnyPS5 Desktop nightly $desktop_tag is left unsigned; the next run tries again"
        done
        release_repo="$slug"
        tag="" ;;
esac

# The nightly.
if [ -z "$tag" ]; then
    today="$(date -u +%Y%m%d)"
    yesterday="$(date -u -v-1d +%Y%m%d)"
    tag="$(gh api "repos/$slug/releases?per_page=40" --jq "
        [.[] | select(.draft | not) | select(.prerelease)
             | select(.tag_name | test(\"^v[0-9.]+-arm-nightly\\\\.($today|$yesterday)\\\\.[0-9]+\$\"))]
        | sort_by(.created_at) | last | .tag_name // empty")"
    [ -n "$tag" ] || { log "no nightly of $today or $yesterday (UTC): nothing to do"; exit 0; }
    scheduled=1
else
    scheduled=0
fi
case "$tag" in
    v*-arm-nightly.*) ;;
    *) die "$tag is not a nightly tag (v<next>-arm-nightly.<YYYYMMDD>.<n>, upstream-nightly.<YYYYMMDD>.<commit> or AnyPS5 Desktop's v<next>-nightly.<YYYYMMDD>.<n>)" ;;
esac
version="${tag#v}"
state="$(gh release view "$tag" --repo "$slug" --json isPrerelease,isDraft --jq '.isPrerelease and (.isDraft | not)')" ||
    die "$tag has no release"
[ "$state" = true ] || die "$tag is not a published pre-release"
assets

git -C "$repo" fetch -q --tags origin
sha="$(git -C "$repo" rev-parse -q --verify "refs/tags/$tag^{commit}")" || die "no tag $tag in $repo"
release="$(git -C "$repo" describe --tags --abbrev=0 --match 'v*-arm' "$sha" 2>/dev/null || true)"

app_zip="AnyPS5-macOS.zip"
toolkit_zip="AnyPS5-toolkit-macos-$version.zip"
have_mac=0
grep -qx "$app_zip" "$scratch/assets" && grep -qx "$toolkit_zip" "$scratch/assets" && have_mac=1

phone=0
case "${ANYPS5_NIGHTLY_PHONE:-}" in
    1) phone=1; phone_why="ANYPS5_NIGHTLY_PHONE=1" ;;
    0) phone_why="ANYPS5_NIGHTLY_PHONE=0" ;;
    *) if [ -z "$release" ]; then phone=1; phone_why="no release before it"
       elif git -C "$repo" diff --quiet "$release" "$sha" -- mobile/; then phone_why="mobile/ is as in $release"
       else phone=1; phone_why="mobile/ changed since $release"
       fi ;;
esac

log "nightly $tag, commit $sha (release before it: ${release:-none})"
log "worktree $wt, build $wt/build-mac"
if [ "$dry" = 1 ]; then
    echo "release files now:"; sed 's/^/  /' "$scratch/assets"
    if signed; then echo "SHA256SUMS lists every file"; else echo "SHA256SUMS missing or does not list every file"; fi
    if [ "$have_mac" = 1 ]; then
        echo "the Mac files are there: no build, no upload; sign_nightly.sh only if SHA256SUMS is not up to date"
    else
        if [ -d "$wt" ]; then echo "would check out $sha in $wt (detached) and update its submodules"
        else echo "would make $wt: git -C $repo worktree add --detach $wt $sha, and its submodules"; fi
        [ -f "$wt/build-mac/CMakeCache.txt" ] || echo "would configure $wt/build-mac (Release, x86_64, BUILD_TESTING=ON, as docs/dev/MACOS_PORT.md)"
        echo "would build: ninja -C $wt/build-mac all libs"
        echo "would build: AnyPS5.app (build_launcher_app.sh, ${ANYPS5_SIGN_IDENTITY:+signed by $ANYPS5_SIGN_IDENTITY}${ANYPS5_SIGN_IDENTITY:-signed ad hoc}${ANYPS5_NOTARY_PROFILE:+, notarized}) -> $app_zip, version $version"
        echo "would build: $toolkit_zip (package_toolkit.sh)"
        if [ "$phone" = 1 ]; then echo "would build: AnyPS5-Remote.apk and AnyPS5-Remote.ipa ($phone_why)"
        else echo "no phone app: $phone_why"; fi
        echo "would upload to $tag: $app_zip $toolkit_zip$( [ "$phone" = 0 ] || echo ' AnyPS5-Remote.apk AnyPS5-Remote.ipa')"
        echo "would run: tools/release/sign_nightly.sh $tag (SHA256SUMS over every file), then verify.sh --signature-only"
    fi
    echo "vulkan SDK: $vulkan $( [ -d "$vulkan" ] && echo '(found)' || echo '(MISSING)')"
    echo "dry run: nothing built, uploaded or changed"
    exit 0
fi

# The worktree at the nightly's commit (also for signing alone: its tools match the nightly).
common() { (cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd); }
if [ -e "$wt" ]; then
    [ "$(common "$wt" 2>/dev/null || true)" = "$(common "$repo")" ] || die "$wt is not a worktree of $repo"
    git -C "$wt" checkout -q --force --detach "$sha"
else
    git -C "$repo" worktree add -q --detach "$wt" "$sha"
fi
tools="$wt/tools/release"
# The installed copy (--install) follows main: the newest nightly's script replaces it for the next run.
if [ "$scheduled" = 1 ] && [ "$self" = "$support/nightly_mac.sh" ] && [ -f "$tools/nightly_mac.sh" ] &&
    ! cmp -s "$tools/nightly_mac.sh" "$self"; then
    cp "$tools/nightly_mac.sh" "$support/nightly_mac.sh.new" && mv -f "$support/nightly_mac.sh.new" "$support/nightly_mac.sh"
    log "updated the installed script from $tag for the next run"
fi

upload=""
if [ "$have_mac" = 0 ]; then
    for need in cmake ninja swift python3; do command -v "$need" >/dev/null || die "$need is needed"; done
    [ -d "$vulkan" ] || die "no Vulkan SDK at $vulkan (ANYPS5_VULKAN_SDK)"
    build="$wt/build-mac"
    out="$wt/build-nightly/$tag"
    steps="$logs/nightly-mac-build.log"
    mkdir -p "$logs"
    : > "$steps"
    step() {
        log "$1"; shift
        if ! "$@" >> "$steps" 2>&1; then tail -n 40 "$steps"; die "failed: $* (whole output: $steps)"; fi
    }
    if [ -f "$out/.built" ] && [ "$(cat "$out/.built")" = "$sha" ]; then
        log "already built in $out"
    else
        # Only the newest nightly's files are kept.
        rm -rf "$wt/build-nightly"
        mkdir -p "$out"
        # The main checkout's submodule URLs can be its own .git/modules folders (a local clone);
        # git refuses the file transport for submodules unless it is allowed for this command.
        # --force puts back tracked files that went missing inside a submodule (an interrupted
        # clone, a cleanup tool); without it the -dirty check below stops the run.
        step "submodules" git -c protocol.file.allow=always -C "$wt" submodule update --init --recursive --force --jobs 4
        actual="$(git -C "$wt" describe --tags --dirty)"
        [ "$actual" = "$tag" ] || die "git describe in $wt gives $actual, not $tag (another tag on $sha?)"
        [ -f "$build/CMakeCache.txt" ] ||
            step "configuring $build" cmake -S "$wt" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_OSX_ARCHITECTURES=x86_64 -DBUILD_TESTING=ON
        step "engine (ninja all libs)" ninja -C "$build" all libs
        step "AnyPS5.app" "$wt/tools/macos/build_launcher_app.sh" "$build" "$vulkan" "$out"
        built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$out/AnyPS5.app/Contents/Info.plist")"
        [ "$built" = "$version" ] || die "the app says $built, not $version"
        step "$app_zip" ditto -c -k --keepParent "$out/AnyPS5.app" "$out/$app_zip"
        rm -rf "$out/AnyPS5.app"
        step "$toolkit_zip" "$wt/tools/macos/package_toolkit.sh" "$build" "$vulkan" "$out"
        [ -s "$out/$toolkit_zip" ] || die "package_toolkit.sh made no $toolkit_zip"
        if [ "$phone" = 1 ]; then
            # The phone app is extra: when it cannot be built the nightly goes out without it.
            log "phone app ($phone_why)"
            if (cd "$wt/mobile" && flutter build apk --release && flutter build ios --release --no-codesign) >> "$steps" 2>&1; then
                cp "$wt/mobile/build/app/outputs/flutter-apk/app-release.apk" "$out/AnyPS5-Remote.apk"
                mkdir "$scratch/Payload"
                ditto "$wt/mobile/build/ios/iphoneos/Runner.app" "$scratch/Payload/Runner.app"
                (cd "$scratch" && zip -qry "$out/AnyPS5-Remote.ipa" Payload)
            else
                tail -n 20 "$steps"
                log "the phone app did not build; the nightly goes out without it"
                rm -f "$out/AnyPS5-Remote.apk" "$out/AnyPS5-Remote.ipa"
            fi
        else
            log "no phone app: $phone_why"
        fi
        echo "$sha" > "$out/.built"
    fi
    upload="$out/$app_zip $out/$toolkit_zip"
    for file in AnyPS5-Remote.apk AnyPS5-Remote.ipa; do [ ! -f "$out/$file" ] || upload="$upload $out/$file"; done
fi
sign=1
[ -n "$upload" ] || ! signed || { sign=0; log "$tag already has the Mac files and is signed over every file"; }

if [ "$sign" = 1 ]; then
    # No uploads or downloads while a game runs.
    waited=0
    while game_running; do
        [ "$waited" -lt 240 ] || { log "skipped: a game has been running for 4 hours; the files stay in $wt/build-nightly"; exit 0; }
        [ "$waited" -gt 0 ] || log "a game is running: waiting to upload and sign"
        sleep 600
        waited=$((waited + 10))
    done
    if [ -n "$upload" ]; then
        log "uploading to $tag:$(for file in $upload; do printf ' %s' "$(basename "$file")"; done)"
        # shellcheck disable=SC2086
        gh release upload "$tag" $upload --repo "$slug" --clobber
        assets
    fi
    log "signing $tag"
    "$tools/sign_nightly.sh" "$tag"
    assets
    signed || die "SHA256SUMS of $tag does not list every file after signing"
fi
"$tools/verify.sh" --signature-only "$scratch/sums"
log "done: https://github.com/$slug/releases/tag/$tag"
