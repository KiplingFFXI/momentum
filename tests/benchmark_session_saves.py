"""Compare real-file session checkpoint costs without a game client.

Times are local single-run observations, not FPS or long-session guarantees.
The baseline uses the requested Git revision's session implementation, with
the same current tracker, JSON library, fixture, and atomic file writer.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

import run


def measure(source, count, items):
    with tempfile.TemporaryDirectory(prefix='momentum_session_benchmark_') as folder:
        lua = run.runtime(folder)
        if source is not None:
            lua.globals().SESSION_BENCH_SOURCE = source
            lua.execute("package.preload['core.sessions']=function() return assert(loadstring(SESSION_BENCH_SOURCE))() end")
        lua.execute("""
            local count, items = ...
            local json = require('json')
            local seed = require('core.tracker').new()
            BENCH_SNAPSHOT = { valid=true, id=1001, job=1, level=32, exp=100,
                exp_needed=require('data.phoenix_rules').tnl[32],zone=100,job_name='WAR' }
            seed:observe(BENCH_SNAPSHOT,0)
            seed:award({kind='exp',amount=100,source='battle'},1)
            for id=1,items do assert(seed.farming:received(id,1,1,{})) end
            local fixture={version=1,next_id=count+1,entries={}}
            local payload=seed:export(3600)
            for id=1,count do
                fixture.entries[id]={id=tostring(id),name='WAR session',job_name='WAR',
                    created=id,saved=id,closed=true,payload=payload}
            end
            BENCH_PATH=MOCK_INSTALL_PATH .. '/config/addons/momentum/bench.json'
            BENCH_FILE=MOCK_INSTALL_PATH .. '/config/addons/momentum/bench-1001.json'
            local file=assert(io.open(BENCH_FILE,'wb'))
            assert(file:write(json.encode(fixture)));assert(file:close())
            BENCH_SETTINGS={sessions={retention=count}}
        """, count, items)
        path = Path(lua.globals().BENCH_FILE)
        before_bytes = path.stat().st_size
        started = time.perf_counter()
        lua.execute("""
            BENCH_MANAGER=require('core.sessions').new(BENCH_PATH)
            local current,_,ready=BENCH_MANAGER:select(BENCH_SNAPSHOT,3600,BENCH_SETTINGS)
            assert(ready)
            assert(not BENCH_MANAGER:problem())
            current:award({kind='exp',amount=7},3601)
            assert(current.farming:received(1,3,3601,{}))
        """)
        select_ms = (time.perf_counter() - started) * 1000
        lua.execute("""
            local json=require('json')
            local encode,decode=json.encode,json.decode
            BENCH_OPS={encodes=0,decodes=0,encoded_records=0}
            json.encode=function(value)
                BENCH_OPS.encodes=BENCH_OPS.encodes+1
                BENCH_OPS.encoded_records=BENCH_OPS.encoded_records+(value.entries and #value.entries or 1)
                return encode(value)
            end
            json.decode=function(value)
                BENCH_OPS.decodes=BENCH_OPS.decodes+1
                return decode(value)
            end
        """)
        started = time.perf_counter()
        lua.execute('assert(BENCH_MANAGER:checkpoint(3630,true))')
        checkpoint_ms = (time.perf_counter() - started) * 1000
        written = json.loads(path.read_text())
        assert len(written['entries']) == count
        assert written['entries'][0]['payload']['session_exp'] == 7
        assert written['entries'][0]['payload']['farming']['total'] == 3
        for record in written['entries'][1:]:
            assert record['payload']['session_exp'] == 100
            assert record['payload']['farming']['total'] == items
        return {
            'sessions': count, 'item_types_per_archive': items, 'archive_json_bytes': before_bytes,
            'select_and_initial_save_ms': round(select_ms, 3),
            'checkpoint_ms': round(checkpoint_ms, 3),
            'checkpoint_operations': dict(lua.globals().BENCH_OPS.items()),
            'written_json_bytes': path.stat().st_size,
            'durable_totals_checked': True,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-ref', default='HEAD')
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    source = subprocess.check_output(
        ['git', 'show', args.baseline_ref + ':momentum/core/sessions.lua'],
        cwd=run.HERE.parent, text=True, encoding='utf-8')
    rows = []
    for count, items in ((5, 20), (30, 100), (100, 1024)):
        rows.append({'baseline': measure(source, count, items), 'current': measure(None, count, items)})
    result = {'evidence': 'offline LuaJIT, real temporary files, one run per case',
              'baseline_ref': args.baseline_ref, 'cases': rows}
    text = json.dumps(result, indent=2)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    print(text)


if __name__ == '__main__':
    main()
