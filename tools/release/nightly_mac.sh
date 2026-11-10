#!/bin/sh
# Signs the nightlies CI published, on the release Mac, where the signing key is
# (docs/dev/SIGNED_UPDATES.md). CI builds everything (.github/workflows/engine-nightly.yml, the
# macOS app and engine included); nothing is built here.
#
#     tools/release/nightly_mac.sh [--dry-run] [<tag>]
#     tools/release/nightly_mac.sh --install
#
# Without <tag> it signs what is not signed yet of:
#   - the upstream nightlies of today or yesterday (UTC): upstream-nightly.<YYYYMMDD>.<commit>
#   - AnyPS5 Desktop's of today or yesterday (AnyTogether/AnyPS5-Desktop,
#     v<next>-nightly.<YYYYMMDD>.<n>)
#   - the newest AnyPS5-ARM nightly of today or yesterday (v<next>-arm-nightly.<YYYYMMDD>.<n>)
# With a <tag> of any of these it signs only that one. A nightly is signed when SHA256SUMS lists
# every file of it; otherwise sign_nightly.sh signs it and verify.sh checks the signature. An
# AnyPS5-ARM nightly without the Mac files (CI's macOS job failed) is signed as it is, for Windows
# and Linux; when the files are added later, the next run signs it again.
#
# It needs nothing of a checkout, and nothing under ~/Desktop (launchd agents are refused access
# there): sign_nightly.sh, sign.sh and verify.sh come from origin/main of a small clone of its own
# in ~/Library/Application Support/AnyPS5/nightly-mac/repo (tools/release only), brought up to
# date at each run.
#
# It does nothing (and exits 0, so the next day tries again) when less than 6 GB of disk is free
# or a game is running (an eboot under <games>/.AnyPS5/Games). A game started during a run stops
# the signing of the nightlies after it.
#
# --dry-run brings the clone up to date and prints what it would sign, and changes nothing on
# GitHub.
# --install installs the daily launchd agent net.anytogether.anyps5.nightly-mac: a copy of this
# script in ~/Library/Application Support/AnyPS5/nightly-mac (replaced by origin/main's at each
# scheduled run), run at 04:45 UTC (the hour is converted to the Mac's time zone when installing)
# under `taskpolicy -b`, logging to ~/Library/Logs/AnyPS5/nightly-mac.log.
set -eu
slug="AnyTogether/AnyPS5-ARM"
desktop_slug="AnyTogether/AnyPS5-Desktop"
label="net.anytogether.anyps5.nightly-mac"
min_free_kb=$((6 * 1024 * 1024))
self="$0"
support="$HOME/Library/Application Support/AnyPS5/nightly-mac"
logs="$HOME/Library/Logs/AnyPS5"
clone="$support/repo"
tools="$clone/tools/release"

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

# --install: the launchd agent.
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
    agent_path="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    plist="$HOME/Library/LaunchAgents/$label.plist"
    cat > "$plist" <<EOF
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
    <key>WorkingDirectory</key><string>$support</string>
    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>
    <key>StandardOutPath</key><string>$logs/nightly-mac.log</string>
    <key>StandardErrorPath</key><string>$logs/nightly-mac.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$agent_path</string>
    </dict>
</dict>
</plist>
EOF
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
free_kb="$(df -k "$HOME" | awk 'NR == 2 { print $4 }')"
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
command -v git >/dev/null || die "git is needed"
gh auth status >/dev/null 2>&1 || die "gh is not signed in"

# The signing scripts, as they are on origin/main.
mkdir -p "$support"
if [ -d "$clone/.git" ]; then
    git -C "$clone" fetch -q --depth 1 origin main || die "cannot fetch origin/main for the signing scripts"
    git -C "$clone" checkout -q --force --detach FETCH_HEAD || die "cannot check out origin/main for the signing scripts"
else
    rm -rf "$clone"
    git clone -q --depth 1 --filter=blob:none --sparse --branch main "https://github.com/$slug.git" "$clone" ||
        die "cannot clone $slug for the signing scripts"
    git -C "$clone" sparse-checkout set tools/release || die "cannot check out the signing scripts"
fi
[ -x "$tools/sign_nightly.sh" ] && [ -x "$tools/verify.sh" ] || die "no signing scripts in $tools"
log "signing scripts: origin/main at $(git -C "$clone" rev-parse --short=12 HEAD)"

# The installed copy follows main: origin/main's script replaces it for the next run.
if [ "$dry" = 0 ] && [ -z "$tag" ] && [ "$self" = "$support/nightly_mac.sh" ] && [ -f "$tools/nightly_mac.sh" ] &&
    ! cmp -s "$tools/nightly_mac.sh" "$self"; then
    cp "$tools/nightly_mac.sh" "$support/nightly_mac.sh.new" && chmod 755 "$support/nightly_mac.sh.new"
    mv -f "$support/nightly_mac.sh.new" "$support/nightly_mac.sh"
    log "updated the installed script from origin/main for the next run"
fi

# The repository assets and signed read.
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

sign_only() {  # <tag> <repository> <what it is>
    tag="$1"
    release_repo="$2"
    what="$3"
    state="$(gh release view "$tag" --repo "$release_repo" --json isPrerelease,isDraft --jq '.isPrerelease and (.isDraft | not)')" ||
        { log "error: $tag has no release"; return 1; }
    [ "$state" = true ] || { log "error: $tag is not a published pre-release"; return 1; }
    assets || return 1
    if [ "$what" = nightly ] && ! grep -qx AnyPS5-macOS.zip "$scratch/assets"; then
        log "$tag has no Mac files (CI's macOS job did not add them); it is signed as it is"
    fi
    if signed; then
        log "$what $tag is signed over every file"
        "$tools/verify.sh" --signature-only "$scratch/sums" || { log "error: the signature of $tag does not verify"; return 1; }
        return 0
    fi
    if [ "$dry" = 1 ]; then
        echo "$what $tag: not signed over every file; would sign it with sign_nightly.sh from origin/main, then verify.sh --signature-only"
        sed 's/^/  /' "$scratch/assets"
        return 0
    fi
    if game_running; then log "skipped signing $tag: a game is running (the next run tries again)"; return 0; fi
    log "signing $what $tag"
    "$tools/sign_nightly.sh" -R "$release_repo" "$tag" || { log "error: sign_nightly.sh $tag failed"; return 1; }
    assets || return 1
    signed || { log "error: SHA256SUMS of $tag does not list every file after signing"; return 1; }
    "$tools/verify.sh" --signature-only "$scratch/sums" || { log "error: the signature of $tag does not verify"; return 1; }
    log "signed $what: https://github.com/$release_repo/releases/tag/$tag"
}

case "$tag" in
    upstream-nightly.*)
        sign_only "$tag" "$slug" "upstream nightly" || exit 1 ;;
    v*-arm-nightly.*)
        sign_only "$tag" "$slug" nightly || exit 1 ;;
    v*-nightly.*)
        sign_only "$tag" "$desktop_slug" "AnyPS5 Desktop nightly" || exit 1 ;;
    '')
        today="$(date -u +%Y%m%d)"
        yesterday="$(date -u -v-1d +%Y%m%d)"
        upstream_tags="$(gh api "repos/$slug/releases?per_page=40" --jq "
            [.[] | select(.draft | not) | select(.prerelease)
                 | select(.tag_name | test(\"^upstream-nightly\\\\.($today|$yesterday)\\\\.[0-9a-f]+\$\"))]
            | sort_by(.created_at) | .[].tag_name")" || upstream_tags=""
        [ -n "$upstream_tags" ] || log "no upstream nightly of $today or $yesterday (UTC) to sign"
        for upstream_tag in $upstream_tags; do
            sign_only "$upstream_tag" "$slug" "upstream nightly" || log "upstream nightly $upstream_tag is left unsigned; the next run tries again"
        done
        desktop_tags="$(gh api "repos/$desktop_slug/releases?per_page=40" --jq "
            [.[] | select(.draft | not) | select(.prerelease)
                 | select(.tag_name | test(\"^v[0-9.]+-nightly\\\\.($today|$yesterday)\\\\.[0-9]+\$\"))]
            | sort_by(.created_at) | .[].tag_name")" || desktop_tags=""
        [ -n "$desktop_tags" ] || log "no AnyPS5 Desktop nightly of $today or $yesterday (UTC) to sign"
        for desktop_tag in $desktop_tags; do
            sign_only "$desktop_tag" "$desktop_slug" "AnyPS5 Desktop nightly" || log "AnyPS5 Desktop nightly $desktop_tag is left unsigned; the next run tries again"
        done
        nightly_tag="$(gh api "repos/$slug/releases?per_page=40" --jq "
            [.[] | select(.draft | not) | select(.prerelease)
                 | select(.tag_name | test(\"^v[0-9.]+-arm-nightly\\\\.($today|$yesterday)\\\\.[0-9]+\$\"))]
            | sort_by(.created_at) | last | .tag_name // empty")"
        [ -n "$nightly_tag" ] || { log "no nightly of $today or $yesterday (UTC): nothing to do"; exit 0; }
        sign_only "$nightly_tag" "$slug" nightly || exit 1 ;;
    *) die "$tag is not a nightly tag (v<next>-arm-nightly.<YYYYMMDD>.<n>, upstream-nightly.<YYYYMMDD>.<commit> or AnyPS5 Desktop's v<next>-nightly.<YYYYMMDD>.<n>)" ;;
esac
[ "$dry" = 0 ] || echo "dry run: nothing signed or uploaded"
log "done"
