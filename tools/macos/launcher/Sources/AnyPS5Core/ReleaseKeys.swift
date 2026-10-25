// Written by tools/release/embed_keys.sh from tools/release/release-signing.pub: change that
// file and run the script rather than editing this one.

/// The Ed25519 public keys AnyPS5 releases are signed with, "ed25519 <base64> <name>" a line
/// (docs/dev/SIGNED_UPDATES.md in AnyPS5-ARM).
enum ReleaseKeys {
    static let list = """
    ed25519 T+482y7DXfmE+OHR0IhD9WzkL2GNjMAY9RBVGboojKk= release-2026-10
    """
}
