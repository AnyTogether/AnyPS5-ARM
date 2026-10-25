#!/bin/sh
# Makes the Ed25519 key that signs AnyPS5 releases (docs/dev/SIGNED_UPDATES.md):
#
#     tools/release/keygen.sh            the release key, ~/.config/anyps5/release-signing.key
#     tools/release/keygen.sh --next     the next key of a rotation, release-signing-next.key
#
# The private key stays in that file (mode 600; never committed, never printed). Its public half
# is added to tools/release/release-signing.pub and embedded in the launchers
# (tools/release/embed_keys.sh). An existing key is never overwritten.
set -eu
. "$(dirname "$0")/common.sh"
openssl="$(release_openssl)"

case "${1:-}" in
    "") key="$release_key"; name="release-$(date +%Y-%m)" ;;
    --next) key="$release_next_key"; name="next-$(date +%Y-%m)" ;;
    *) echo "usage: $0 [--next]" >&2; exit 2 ;;
esac
if [ -e "$key" ]; then
    echo "$key already exists; it is never replaced" >&2
    exit 1
fi
mkdir -p "$release_key_folder"
chmod 700 "$release_key_folder"
(umask 077 && "$openssl" genpkey -algorithm ed25519 -out "$key")
chmod 600 "$key"
public="$(release_public_key "$key")"
if [ ! -f "$release_keys" ]; then
    cat > "$release_keys" <<HEADER
# The Ed25519 keys AnyPS5 releases are signed with (docs/dev/SIGNED_UPDATES.md), one per line:
# "ed25519 <raw public key, base64> <name>". The launchers trust every key listed here; the
# private halves never leave the release Mac.
HEADER
fi
echo "ed25519 $public $name" >> "$release_keys"
"$release_dir/embed_keys.sh"
echo "made $key (key ID $(release_key_id "$public")); public key added to $release_keys"
