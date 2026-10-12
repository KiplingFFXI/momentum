"""Syntax-check the chain module with pinned Phoenix headers and an existing MSVC build."""

import argparse
import ctypes
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile


def split_windows(command):
    count = ctypes.c_int()
    parse = ctypes.windll.shell32.CommandLineToArgvW
    parse.argtypes = [ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_int)]
    parse.restype = ctypes.POINTER(ctypes.c_wchar_p)
    values = parse(command, ctypes.byref(count))
    try:
        return [values[index] for index in range(count.value)]
    finally:
        ctypes.windll.kernel32.LocalFree(values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2] / "Phoenix")
    parser.add_argument("--ref", default="071c401048bdb97bcbe12ad93651574fcf867407")
    args = parser.parse_args()
    source = args.source.resolve()
    commands = json.loads((source / "build/compile_commands.json").read_text(encoding="utf-8"))
    entry = next(row for row in commands if row["file"].replace("\\", "/").endswith("/player_count.cpp"))
    original = split_windows(entry["command"])
    module = Path(__file__).resolve().parent / "test_chain_native.cpp"
    data_files = subprocess.check_output(["git", "-C", str(source), "ls-tree", "-r", "--name-only", args.ref, "data"], text=True).splitlines()
    data_files = [path for path in data_files if path.endswith(".yaml") and not path.startswith(("data/zones/", "data/schemas/"))]
    archive = subprocess.check_output(["git", "-C", str(source), "archive", args.ref, "src", "tools/codegen", *data_files])
    with tempfile.TemporaryDirectory(prefix="momentum-chain-headers-") as folder:
        temp = Path(folder)
        with tarfile.open(fileobj=io.BytesIO(archive)) as files:
            files.extractall(temp, filter="data")
        generated = subprocess.run([sys.executable, "-m", "tools.codegen", "build"], cwd=temp, capture_output=True, text=True)
        if generated.returncode:
            print(generated.stdout, generated.stderr)
            raise SystemExit(generated.returncode)
        options = ["-I" + str(temp / "build/generated")]
        for option in original[1:]:
            lower = option.lower()
            if lower.startswith(("/yu", "/fp", "/fi", "/fo", "/fd")) or lower in ("/c", "/zi", "/fs", "/mp"):
                continue
            if option.replace("\\", "/").lower() == entry["file"].replace("\\", "/").lower():
                continue
            if option.startswith(("-I", "/I")):
                path = Path(option[2:])
                try:
                    relative = path.relative_to(source)
                except ValueError:
                    relative = None
                if relative is not None and (not relative.parts or relative.parts[0] == "src"):
                    option = option[:2] + str(temp / relative)
            options.append(option)
        print("Phoenix source headers:", args.ref, flush=True)
        print("Enum headers regenerated from the same pin; dependencies and build config:", source / "build", flush=True)
        result = subprocess.run([original[0], *options, "/Zs", "/Y-", str(module)], cwd=temp)
        if result.returncode:
            raise SystemExit(result.returncode)
    print("Chain C++ module and eight native snapshot assertions passed; no server binary was built or started.")


if __name__ == "__main__":
    main()
