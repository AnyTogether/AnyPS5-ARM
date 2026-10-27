# Windows and Linux engine for AnyPS5 Desktop

AnyPS5 Desktop (AnyTogether/AnyLauncher-Port) can run games with AnyPS5-ARM's engine instead of
upstream's. It looks for it on AnyPS5-ARM's releases, by name:

    AnyPS5-toolkit-windows-<commit>.zip
    AnyPS5-toolkit-linux-<commit>.tar.gz   (first choice on Linux)
    AnyPS5-toolkit-linux-<commit>.zip

and checks the archive against the release's signed `SHA256SUMS` ([SIGNED_UPDATES.md](SIGNED_UPDATES.md)).
Of the releases GitHub lists (newest first), the first one that carries an archive for the system
wins; inside a release, the newest upload (GitHub's `updated_at`) wins, so an older engine can stay
on a release for the launchers that already have it.

Each archive is a whole toolkit folder:

    relinker[.exe]
    libs/            every patched .prx; on Windows also libgcc_s_seh-1.dll, libstdc++-6.dll,
                     libwinpthread-1.dll, mimalloc.dll, mimalloc-redirect.dll; licenses/
    version.txt      arm-<commit>

`tools/package_arm_toolkit.py` writes it from a build folder. It lets upstream's release packaging
(`tools/package_release.py`, the one the Release workflow uses) collect and check the files, so a
missing library stops it.

Every AnyPS5-ARM release should carry both archives, built from the release's commit. The Mac
nightly script (`tools/macos/publish_nightly.sh`) cannot build them; they come from a Windows
machine with WSL, as below, and are added to the release afterwards, then the whole release is
signed again.

## Windows (WinLibs GCC 15.2, the Release workflow's toolchain)

WinLibs `15.2.0posix-14.0.0-ucrt-r7` unpacked so that `C:\dev\winlibs\mingw64\bin\g++.exe`
exists, Git for Windows, Python 3 and CMake/Ninja (WinLibs has both). In PowerShell:

```powershell
$env:PATH = "C:\dev\winlibs\mingw64\bin;" + $env:PATH
git clone --recurse-submodules https://github.com/AnyTogether/AnyPS5-ARM.git C:\dev\AnyPS5-ARM
Set-Location C:\dev\AnyPS5-ARM
git checkout <release commit>; git submodule update --init --recursive
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++
cmake --build build --target relinker libs
python tools\package_arm_toolkit.py --platform windows --build build --output C:\dev\dist
```

`ctest --test-dir build -R "online|remote_pad|guest_net_ctl"` checks the online bridge and the
phone pad's Winsock code (build those test targets first, or `cmake --build build` for all).

## Linux (WSL Ubuntu 22.04, GCC 12)

Built on Ubuntu 22.04 so the engine asks for glibc 2.35 at most (AnyPS5 Desktop warns when a
Linux engine needs a newer glibc than the system has) and for no newer libstdc++ than 22.04's
(GCC 12's). Ubuntu 22.04's own `g++-12` builds the tree.

```sh
sudo apt-get install -y g++-12 cmake ninja-build pkg-config python3 git zip \
    libpipewire-0.3-dev libdecor-0-dev libvulkan-dev libx11-dev libxext-dev libxrandr-dev \
    libwayland-dev libxkbcommon-dev libegl-dev libpulse-dev libasound2-dev
git clone --recurse-submodules https://github.com/AnyTogether/AnyPS5-ARM.git ~/AnyPS5-ARM && cd ~/AnyPS5-ARM
git checkout <release commit> && git submodule update --init --recursive
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DCMAKE_C_COMPILER=gcc-12 -DCMAKE_CXX_COMPILER=g++-12
cmake --build build --target relinker libs
python3 tools/package_arm_toolkit.py --platform linux --build build --output ~/dist
```

Check the glibc floor of the result before publishing it (CI's `Engine (Linux build, Ubuntu 22.04,
GCC 12)` job runs the same check on every pull request that touches the engine):

```sh
objdump -T build/core/libs/libs/*.prx build/core/relinker/relinker | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1
objdump -T build/core/libs/libs/*.prx | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -1
```

## Headless check

With AnyPS5 Desktop's command line (`dart run tool/anyps5_tool.dart`, from its repository), the
new toolkit must install a game without starting it:

```sh
ANYPS5_TOOLKIT=<unpacked toolkit folder> dart run tool/anyps5_tool.dart install <game folder> <games folder>
```

## Publishing

1. Download every file of the release into one folder (`gh release download <tag> -R AnyTogether/AnyPS5-ARM`),
   drop the old `SHA256SUMS` and `SHA256SUMS.sig`, add the new archives.
2. `tools/release/sign.sh <every file>` (the release key is on the release Mac), then
   `tools/release/verify.sh <folder>`.
3. `gh release upload <tag> <archives> -R AnyTogether/AnyPS5-ARM`, compare the sizes GitHub lists
   with the local ones, then `gh release upload <tag> SHA256SUMS SHA256SUMS.sig --clobber`.

Keep an engine archive that launchers already downloaded on the release: its sum stays in the
signed list, and the newer upload beside it is the one new checks offer.
