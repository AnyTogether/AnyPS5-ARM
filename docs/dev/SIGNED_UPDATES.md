# Signed updates

The macOS launcher's self-update and engine downloads, and AnyPS5 Desktop's own updates and
downloads from our repositories, are signed with one Ed25519 release key. The apps check the
signature with keys built into them before they replace themselves or use an engine, so a
compromised GitHub account, release or download path cannot push code to installed launchers
unless it also has the key, which never leaves the release Mac.

Trust starts with the first install ("trust the first update-signing key"): `install.sh` and a
browser download trust GitHub over HTTPS, and from then on every update must be signed by a key
that the installed launcher already trusts.

## Files

| What | Where |
| --- | --- |
| Private key | `~/.config/anyps5/release-signing.key` on the release Mac (mode 600, folder 700). Never committed, never printed, never copied into CI. |
| Next key (during a rotation) | `~/.config/anyps5/release-signing-next.key` |
| Public keys | `tools/release/release-signing.pub`, one per line: `ed25519 <raw 32-byte public key, base64> <name>` |
| Built-in keys, macOS | `tools/macos/launcher/Sources/AnyPS5Core/ReleaseKeys.swift` (generated) |
| Built-in keys, Desktop | `AnyPS5-Desktop/lib/core/release_keys.dart` (generated) |
| Scripts | `tools/release/keygen.sh`, `sign.sh`, `verify.sh`, `embed_keys.sh` (OpenSSL 3, Homebrew's `openssl@3`; macOS's own `openssl` is LibreSSL without Ed25519) |

`embed_keys.sh` writes both constants from the `.pub` file. `build_launcher_app.sh` runs
`embed_keys.sh --check --swift-only` and stops if the Swift constant differs from the file.

## What a release carries

Next to its files, every release has:

- `SHA256SUMS`: `<sha256>  <file name>` for each file, sorted by name, as `shasum -a 256` prints
  it (so `shasum -a 256 -c SHA256SUMS` works too).
- `SHA256SUMS.sig`: one line per signing key, `ed25519 <key ID> <signature, base64>`. The
  signature is pure Ed25519 over the exact bytes of `SHA256SUMS`, and the key ID is the first 16
  hex digits of the sha256 of the raw public key.

The file name is in the signed sums. A toolkit's name carries its version, so the signature also
binds the version. A self-update's version is checked against the unpacked app's `Info.plist`.

## Signing a release

```sh
# once, on the release Mac (already done: key ID f8fe0d55df962105, "release-2026-10")
tools/release/keygen.sh

# every release: put all of its files in one folder, then
tools/release/sign.sh out/AnyPS5-macOS.zip out/AnyPS5-toolkit-macos-<version>.zip \
    out/install.sh out/AnyPS5-Remote.apk out/AnyPS5-Remote.ipa ...   # every file of the release
tools/release/verify.sh out                                          # what the launchers will see
gh release create <tag> out/* ...                                    # SHA256SUMS + SHA256SUMS.sig included
```

`sign.sh` refuses a key that other users can read, a key that is not listed in
`release-signing.pub` (no launcher would trust it), and two files with the same name. It checks
its own result with `verify.sh` before it writes anything. `tools/macos/publish_nightly.sh` signs
nightlies this way. With `ANYPS5_SKIP_SIGN=1` it publishes unsigned, and new launchers then
refuse that nightly.

AnyPS5 Desktop releases are signed the same way, on this Mac, once the Windows and Linux builds
are collected: `AnyPS5-Desktop/packaging/sign-release.sh <files…>` calls this repository's
`sign.sh`. When Desktop files are also attached to an AnyPS5-ARM release, they go into that
release's `SHA256SUMS` too.

To add files to a release that is already signed, sign all of them again and replace both
`SHA256SUMS` and `SHA256SUMS.sig`.
The Windows and Linux engine archives AnyPS5 Desktop downloads are added this way; how they are
built is in [WINDOWS_LINUX_ENGINE.md](WINDOWS_LINUX_ENGINE.md).

## What the launchers check

### macOS launcher (`ReleaseSigning.swift`, CryptoKit)

Self-update (`Updates.prepare`):

1. The release must list `SHA256SUMS` and `SHA256SUMS.sig`. If it doesn't, the launcher refuses
   and says so before downloading anything: "AnyPS5 X is not signed, so it was not installed; get
   it from <release page> only if you trust it".
2. Both files are downloaded (at most 1 MB each). At least one signature line must verify with a
   built-in key. Lines from unknown keys are skipped. If no line comes from a known key, the error
   names the key IDs.
3. `AnyPS5-macOS.zip` is downloaded. Its sha256 must equal the signed sum, checked before
   `ditto` unpacks it.
4. As before: same bundle identifier, newer version, then the replacement script runs.

Engines (`ToolkitStore.download` → `expectedDigest`): every catalogue entry has a trust level.

| Release | Trust | Behaviour |
| --- | --- | --- |
| has `SHA256SUMS` + `.sig` | `signed` | The signature is checked, then the zip must match its signed sum, then the existing toolkit.json checks run. |
| unsigned, version ≤ `lastUnsignedRelease` (0.2.16) | `unsignedOlder` | Listed as "Unsigned (older release)" with a warning. Choosing it downloads it, and only GitHub's sha256 digest checks it. A release without that digest is refused. |
| unsigned, version > 0.2.16 (nightlies of 0.2.17 included) | `unsignedRefused` | Listed as "Not signed" and never downloaded. |

The cutoff is a version, not a date. Signatures can be stripped from new releases, but that
cannot turn a new release into a "trusted older" one. 0.2.16 is the cutoff because its draft was
built before signing existed. The first signed release can be 0.2.16 itself (signing its files
before publishing just makes it `signed`) or any later one, and every later one must be signed.

Older unsigned launchers (≤ 0.2.16) keep updating without checking, because they cannot be
changed. The first signed launcher reaches them through that last unchecked update.

### AnyPS5 Desktop (`lib/core/release_signing.dart`, pinenacl)

- `pinenacl` (MIT, a TweetNaCl port, no dependencies) verifies. `package:cryptography` is
  Apache-2.0, which GPL-2.0-only code cannot take, and `pointycastle` has no Ed25519.
- A `GitHubReleases` source with `signingKeys` (ours: `AnyTogether/AnyPS5-Desktop`, and
  `AnyTogether/AnyPS5-ARM` for our Windows engine) gets the same treatment as above. Signed
  downloads must match the signed sums, an unsigned release after 0.2.16 is refused, and an older
  unsigned one needs the user's OK (`allowUnsigned`).
- Desktop's own updates (`LauncherUpdates`) must always be signed. Every Desktop version newer
  than the first signing one (0.1.3) came out after signing began. The launcher says when a new
  version is out and downloads the installer for this system (Setup .exe, AppImage or .tar.gz)
  into its cache, checked against the signed sums. The user runs it.
- Upstream's toolkit (`boykopovar/AnyPS5`) isn't signed by us. It stays on GitHub's sha256
  digests, and the engine settings say so.

## Rotating the key

1. `tools/release/keygen.sh --next` makes `release-signing-next.key` and adds its public key to
   `release-signing.pub`. The launchers built from then on trust both keys.
2. Publish releases signed with the current key (or with both:
   `sign.sh -k ~/.config/anyps5/release-signing.key -k ~/.config/anyps5/release-signing-next.key …`).
   Each update installed this way brings the next key along: an update signed by the current key
   introduces the next one.
3. Once enough users run a launcher that knows the next key, sign with it alone. Then move it to
   `release-signing.key` (keep the old file offline) and remove the old line from
   `release-signing.pub`, followed by `embed_keys.sh`. Later launchers no longer accept the old key.

If the private key is lost and no next key exists, installed launchers can't take updates any
more. Users then reinstall with `install.sh`, which brings the new key ("trust the first key"
again). If the key leaks, rotate immediately and tell users to reinstall, because a leaked key
can sign updates for every launcher that still trusts it.

## Tests

- Swift: `ReleaseSigningTests` (OpenSSL-made fixture, CryptoKit round trip, tampered file and
  sums, wrong key, forged key ID, missing signature, rotation, the sums format, the cutoff, and
  built-in keys = `.pub`), `SignedUpdateTests` (self-update end to end over a local HTTP server:
  signed, tampered, other key, unsigned, missing files; engine trust levels; a catalogue cached
  before signing).
- Dart: `test/core/release_signing_test.dart` (the same OpenSSL fixture and cases), and the
  `signed source` group in `test/core/toolkit_download_test.dart`, plus the update tests.
