"""Run the offline Lua, client-settings and release checks without a game client."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    for command in (
        [sys.executable, 'tests/run.py'],
        [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py', '-v'],
        [sys.executable, 'tools/check_repository.py'],
    ):
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            return result.returncode
    print('Offline verification passed. In-game checks are separate.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
