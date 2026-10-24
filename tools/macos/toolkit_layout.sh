# The engine toolkit's layout, shared by build_launcher_app.sh (the toolkit inside AnyPS5.app),
# package_toolkit.sh (the toolkit as a release download the launcher can switch to) and
# sign_launcher_app.sh. Sourced, not run:
#
#     . tools/macos/toolkit_layout.sh
#
# A toolkit folder holds:
#     relinker                 the relinker
#     libs/*.prx               the system libraries every unlocked game carries
#     vulkan/                  the Vulkan loader, MoltenVK (patched) and its driver manifest
#     patches/*.json           the per-title patches
#     version.txt              "<release version>-<fingerprint of relinker, libs and patches>"
#     toolkit.json             (downloads only) what it is and every file's sha256

# The release version of the checkout: the tag without its v (0.2.14-arm), or git describe's
# longer form between releases.
toolkit_release_version() {
    git -C "$1" describe --tags --always 2>/dev/null | sed "s/^v//" || echo 0.0.0
}

# make_toolkit <repository root> <build dir> <Vulkan SDK macOS dir> <toolkit dir> <release version>
#
# Fills <toolkit dir> from a finished `ninja all libs` build and the Vulkan SDK; MoltenVK is
# patched here (tools/macos/moltenvk_patches.py). Prints nothing; the version is in version.txt.
make_toolkit() {
    _tk_root="$1"
    _tk_build="$2"
    _tk_vulkan="$3"
    _tk_out="$4"
    _tk_version="$5"
    mkdir -p "$_tk_out/libs" "$_tk_out/vulkan" "$_tk_out/patches"
    cp "$_tk_build/core/relinker/relinker" "$_tk_out/relinker"
    cp "$_tk_build"/core/libs/libs/*.prx "$_tk_out/libs/"
    cp -L "$_tk_vulkan/lib/libvulkan.1.dylib" "$_tk_vulkan/lib/libMoltenVK.dylib" "$_tk_out/vulkan/"
    chmod u+w "$_tk_out/vulkan/"*.dylib
    python3 "$_tk_root/tools/macos/moltenvk_patches.py" "$_tk_out/vulkan/libMoltenVK.dylib"
    sed 's#"library_path": "[^"]*"#"library_path": "../../../MacOS/libs/libMoltenVK.dylib"#' "$_tk_vulkan/share/vulkan/icd.d/MoltenVK_icd.json" > "$_tk_out/vulkan/MoltenVK_icd.json"
    cp "$_tk_root"/tools/macos/patches/*.json "$_tk_out/patches/"
    # An installed game made by another toolkit can be installed again (the launcher offers it).
    _tk_fingerprint="$(cat "$_tk_out/relinker" "$_tk_out"/libs/*.prx "$_tk_out"/patches/*.json | shasum -a 256 | cut -c1-12)"
    echo "$_tk_version-$_tk_fingerprint" > "$_tk_out/version.txt"
}

# sign_toolkit <toolkit dir> <identity>
#
# Signs the toolkit's code from the inside out: its prx libraries and the Vulkan loader with
# MoltenVK (games copy these unchanged), then the relinker with the hardened runtime. identity -
# signs ad hoc. Games the launcher unlocks later are never signed.
sign_toolkit() {
    _tk_dir="$1"
    _tk_identity="$2"
    # xargs cannot call a shell function, so the libraries go through codesign directly.
    if [ "$_tk_identity" = "-" ]; then
        find "$_tk_dir/libs" "$_tk_dir/vulkan" -type f \( -name '*.prx' -o -name '*.dylib' \) -print0 | xargs -0 -n 64 codesign --force --sign -
        codesign --force --sign - --options runtime "$_tk_dir/relinker"
    else
        find "$_tk_dir/libs" "$_tk_dir/vulkan" -type f \( -name '*.prx' -o -name '*.dylib' \) -print0 | xargs -0 -n 64 codesign --force --timestamp --sign "$_tk_identity"
        codesign --force --timestamp --sign "$_tk_identity" --options runtime "$_tk_dir/relinker"
    fi
}

# write_toolkit_manifest <repository root> <toolkit dir> <minimum launcher version>
#
# toolkit.json: the toolkit's version (version.txt), the engine commit it was built from, where
# that commit left upstream (when an `upstream` remote is known), the build date, the launcher
# version it needs at least and the sha256 of every other file in it. The launcher refuses a
# download whose files do not match.
write_toolkit_manifest() {
    _tk_root="$1"
    _tk_dir="$2"
    _tk_minimum="$3"
    _tk_commit="$(git -C "$_tk_root" rev-parse HEAD 2>/dev/null || echo "")"
    _tk_base=""
    for _tk_ref in upstream/main upstream/master; do
        if git -C "$_tk_root" rev-parse --verify --quiet "$_tk_ref" >/dev/null; then
            _tk_base="$(git -C "$_tk_root" merge-base HEAD "$_tk_ref" 2>/dev/null || echo "")"
            [ -z "$_tk_base" ] || break
        fi
    done
    python3 - "$_tk_dir" "$_tk_commit" "$_tk_base" "$_tk_minimum" <<'EOF'
import datetime
import hashlib
import json
import os
import sys

folder, commit, base, minimum = sys.argv[1:5]
files = {}
for directory, folders, names in os.walk(folder):
    folders.sort()
    for name in sorted(names):
        path = os.path.join(directory, name)
        relative = os.path.relpath(path, folder)
        if relative == "toolkit.json":
            continue
        if os.path.islink(path):
            sys.exit(f"toolkit: {relative} is a link; a toolkit holds only plain files")
        digest = hashlib.sha256()
        with open(path, "rb") as handle:
            for block in iter(lambda: handle.read(1 << 20), b""):
                digest.update(block)
        files[relative] = digest.hexdigest()
with open(os.path.join(folder, "version.txt")) as handle:
    version = handle.read().strip()
manifest = {
    "format": 1,
    "version": version,
    "engineCommit": commit or None,
    "upstreamBase": base or None,
    "buildDate": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "minimumLauncher": minimum,
    "files": files,
}
with open(os.path.join(folder, "toolkit.json"), "w") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
EOF
}
