# Shared by the release-signing scripts (docs/dev/SIGNED_UPDATES.md); sourced, not run.

release_dir="$(cd "$(dirname "$0")" && pwd)"
release_root="$(cd "$release_dir/../.." && pwd)"
release_keys="$release_dir/release-signing.pub"
release_key_folder="${ANYPS5_RELEASE_KEY_DIR:-$HOME/.config/anyps5}"
release_key="$release_key_folder/release-signing.key"
release_next_key="$release_key_folder/release-signing-next.key"

# An OpenSSL 3 (Ed25519 with -rawin); macOS's own openssl is LibreSSL, which has no Ed25519.
release_openssl() {
    for candidate in "${ANYPS5_OPENSSL:-}" /opt/homebrew/opt/openssl@3/bin/openssl /opt/homebrew/bin/openssl \
        /usr/local/opt/openssl@3/bin/openssl "$(command -v openssl 2>/dev/null || true)"; do
        [ -n "$candidate" ] && [ -x "$candidate" ] || continue
        case "$("$candidate" version 2>/dev/null)" in
            "OpenSSL 3"*) echo "$candidate"; return 0 ;;
        esac
    done
    echo "release signing needs OpenSSL 3 (Homebrew's openssl@3, or ANYPS5_OPENSSL=<path>)" >&2
    return 1
}

# The raw 32-byte Ed25519 public key of a private key file, in base64.
release_public_key() {
    "$openssl" pkey -in "$1" -pubout -outform DER | tail -c 32 | base64 | tr -d '\n'
}

# The key ID: the first 16 hex digits of the sha256 of the raw public key (base64 in $1).
release_key_id() {
    printf '%s' "$1" | base64 -d | shasum -a 256 | cut -c1-16
}

# Fails unless the private key file is readable by its owner alone.
release_check_private() {
    [ -f "$1" ] || { echo "no signing key at $1 (tools/release/keygen.sh makes it)" >&2; return 1; }
    mode="$(stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1")"
    case "$mode" in
        600|400) ;;
        *) echo "$1 can be read by others (mode $mode): chmod 600 it first" >&2; return 1 ;;
    esac
}
