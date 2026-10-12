"""Run Momentum's Lua tests in a fresh LuaJIT runtime for each file."""
from pathlib import Path
import os
import re
import sys
import tempfile

from lupa import luajit21

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent / 'momentum'
ASHITA_LIBS = Path(os.environ.get('ASHITA_LIBS', 'C:/Games/PhoenixXI/addons/libs'))
FAILED_LINE = re.compile(r'^\d+ FAILED$', re.M)


def runtime(install):
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path = ... .. package.path',
                ';'.join((ADDON.as_posix() + '/?.lua', HERE.as_posix() + '/?.lua',
                          ASHITA_LIBS.as_posix() + '/?.lua', '')))
    lua.globals().MOCK_INSTALL_PATH = str(install).replace('\\', '/')
    lua.globals().ADDON_DIR = ADDON.as_posix()
    lua.globals().ASHITA_LIBS = ASHITA_LIBS.as_posix()
    lua.globals().MOMENTUM_TEST_MODE = True
    (Path(install) / 'config/addons/momentum').mkdir(parents=True, exist_ok=True)
    lua.execute((HERE / 'mock_ashita.lua').read_text(encoding='utf-8'))
    return lua


def main(names):
    tests = [HERE / name for name in names] if names else sorted(HERE.glob('test_*.lua'))
    failures = 0
    with tempfile.TemporaryDirectory(prefix='momentum_syntax_') as folder:
        lua = runtime(folder)
        compile_lua = lua.eval('function(path) local f, err = loadfile(path); return f ~= nil, err end')
        sources = sorted(ADDON.rglob('*.lua'))
        for source in sources:
            valid, error = compile_lua(source.as_posix())
            if not valid:
                print('FAIL syntax %s: %s' % (source.relative_to(ADDON), error))
                failures += 1
        print('Compiled %d runtime Lua files.' % len(sources))
    for test in tests:
        with tempfile.TemporaryDirectory(prefix='momentum_test_') as folder:
            lua = runtime(folder)
            try:
                result = lua.execute(test.read_text(encoding='utf-8'))
                if luajit21.lua_type(result) == 'table' and result['count'] is not None:
                    result = '%d assertions' % result['count']
                output = '\n'.join(str(v) for v in lua.globals().MOCK.printed.values())
                if result is not None:
                    output += '\n' + str(result)
                if FAILED_LINE.search(output):
                    raise AssertionError(output.strip())
                print('PASS %s%s' % (test.name, ': ' + str(result) if result else ''))
            except Exception as error:
                failures += 1
                print('FAIL %s: %s' % (test.name, error))
    if not tests:
        print('FAIL no test files found.')
        failures += 1
    print('%d test files, %d failures.' % (len(tests), failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
