import os
import platform
import stat
import subprocess
import sys
from pathlib import Path


def _binary_path() -> Path:
    bin_dir = Path(__file__).parent / "bin"
    system = platform.system().lower()
    machine = platform.machine().lower()

    if machine in ("x86_64", "amd64"):
        arch = "amd64"
    elif machine in ("aarch64", "arm64"):
        arch = "arm64"
    else:
        raise RuntimeError(f"Unsupported architecture: {platform.machine()}")

    if system == "windows":
        name = f"devkit-server-windows-{arch}.exe"
    elif system == "linux":
        name = f"devkit-server-linux-{arch}"
    else:
        raise RuntimeError(
            f"Unsupported platform: {platform.system()}. "
            "airgap-devkit supports Windows and Linux only."
        )

    binary = bin_dir / name
    if not binary.exists():
        raise FileNotFoundError(
            f"DevKit server binary not found: {binary}\n"
            "Re-install the package or rebuild from source with: bash launch.sh --rebuild"
        )

    # Ensure executable bit is set (may be lost after pip install on Linux)
    if system != "windows":
        binary.chmod(binary.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    return binary


def main() -> None:
    binary = _binary_path()
    args = [str(binary)] + sys.argv[1:]

    if platform.system().lower() == "windows":
        # os.execv is unreliable on Windows; use subprocess and propagate the exit code
        result = subprocess.run(args)
        sys.exit(result.returncode)
    else:
        os.execv(str(binary), args)


if __name__ == "__main__":
    main()
