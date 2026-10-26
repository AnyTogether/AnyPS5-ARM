"""Packs AnyPS5-ARM's Windows or Linux engine as one archive for AnyPS5 Desktop.

    python tools/package_arm_toolkit.py --platform windows|linux --build build --output dist [--commit <sha>]

The files are the ones upstream's release packaging (package_release.py) collects and checks:
every patched .prx, the MinGW runtime and mimalloc DLLs on Windows, the third-party licences and
the relinker. They are laid out as the launcher's toolkit folder:

    relinker[.exe]
    libs/            the .prx files, DLLs and licenses/
    version.txt      arm-<commit>

and written as AnyPS5-toolkit-<platform>-<commit>.zip, plus a .tar.gz on Linux (the launcher's
first choice there; it keeps the relinker executable). AnyPS5 Desktop finds them on an
AnyPS5-ARM release by that name and checks them against the release's signed SHA256SUMS
(docs/dev/WINDOWS_LINUX_ENGINE.md).
"""
import argparse
import io
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_release  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def windows_runtime(build):
    """The MinGW runtime folder: the compiler's, found on PATH when CMake kept a bare g++."""
    folder = package_release_windows_runtime(build)
    if folder.is_absolute():
        return folder
    compiler = shutil.which("g++")
    if compiler is None:
        raise RuntimeError("CMake names the compiler g++ without a folder and no g++ is on PATH")
    return Path(compiler).resolve().parent


package_release_windows_runtime = package_release.windows_runtime
package_release.windows_runtime = windows_runtime


def current_commit():
    return subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short=9", "HEAD"], check=True, capture_output=True,
                          text=True).stdout.strip()


def pack(platform, build, output, commit):
    output.mkdir(parents=True, exist_ok=True)
    relinker = "relinker.exe" if platform == "windows" else "relinker"
    version = f"arm-{commit}"
    names = [f"AnyPS5-toolkit-{platform}-{commit}.zip"]
    if platform == "linux":
        names.append(f"AnyPS5-toolkit-{platform}-{commit}.tar.gz")
    with tempfile.TemporaryDirectory(prefix=".arm-toolkit-", dir=output) as temporary:
        staging = Path(temporary)
        # Upstream's packaging collects and checks the files; its tag only names its own archives.
        package_release.package(platform, build, staging, "v0")
        with zipfile.ZipFile(staging / f"prx-{platform}-v0.zip") as libraries:
            members = [(info.filename, libraries.read(info)) for info in libraries.infolist() if not info.is_dir()]
        binary = (staging / ("relinker-v0.exe" if platform == "windows" else "relinker-v0")).read_bytes()
        stamp = (version + "\n").encode()

        archive = staging / names[0]
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as out:
            executable = zipfile.ZipInfo(relinker, date_time=(2026, 1, 1, 0, 0, 0))
            executable.external_attr = (0o100755 << 16)
            executable.compress_type = zipfile.ZIP_DEFLATED
            out.writestr(executable, binary)
            for name, data in members:
                out.writestr(zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0)), data, compress_type=zipfile.ZIP_DEFLATED)
            out.writestr(zipfile.ZipInfo("version.txt", date_time=(2026, 1, 1, 0, 0, 0)), stamp)
        if platform == "linux":
            with tarfile.open(staging / names[1], "w:gz", compresslevel=9) as out:
                def add(name, data, mode=0o644):
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    info.mode = mode
                    info.mtime = 1767225600
                    out.addfile(info, io.BytesIO(data))
                add(relinker, binary, 0o755)
                for name, data in members:
                    add(name, data)
                add("version.txt", stamp)
        for name in names:
            (staging / name).replace(output / name)
    return [output / name for name in names]


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("linux", "windows"), required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--commit", help="the engine's commit (default: HEAD, 9 digits)")
    args = parser.parse_args(argv)
    commit = args.commit or current_commit()
    try:
        for file in pack(args.platform, args.build, args.output, commit):
            print(f"{file} {file.stat().st_size}")
    except (RuntimeError, ValueError, OSError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    sys.exit(main())
