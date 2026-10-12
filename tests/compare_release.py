"""Compare tracking and readout results with a previous release under the same trace."""
import argparse
from pathlib import Path
import tempfile
import zipfile

from lupa import luajit21
import run


TRACE = r'''
local tracker = require('core.tracker')
local defaults = require('ui.defaults')
local readouts = require('ui.readouts')
local rules = require('data.phoenix_rules')
local seed, rows = 24601, {}
local function random(limit)
    seed = seed * 48271 % 2147483647
    return seed % limit
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
for _, level in ipairs({ 30, 75 }) do
    local s, t, now = defaults.make(), tracker.new(), 0
    for id in pairs(s.display.enabled) do s.display.enabled[id] = true end
    local p = { valid = true, id = 1001, job = 1, job_name = 'WAR', level = level,
        effective_level = level, zone = 102, exp = 1000, exp_needed = rules.tnl[level], lp = 9000,
        merits = 2, merit_cap = 10, limit_mode = level == 75, limit_breaker = level == 75,
        exp_locked = false, dead = false, dedication = false }
    t:observe(p, now)
    for step = 1, 360 do
        now = now + 1 + random(14)
        if step % 83 == 0 then t:reset(now) end
        if step % 47 == 0 then t:pause(now, not t.paused) end
        if step % 61 == 0 then p.zone = p.zone == 102 and 103 or 102; t:discontinuity(now) end
        if step % 71 == 0 then
            local saved = t:export(now)
            t = tracker.new()
            assert(t:restore(saved, now, { id = p.id, job = p.job }), 'Trace restore failed')
        end
        if step % 41 == 0 then p.dead = true; p.exp = math.max(0, p.exp - 150)
        elseif p.dead then p.dead = false; p.exp = math.min(p.exp_needed - 1, p.exp + 90) end
        if step % 97 == 0 then p.job = p.job == 1 and 2 or 1; p.job_name = p.job == 1 and 'WAR' or 'MNK' end
        p.effective_level = step % 13 == 0 and 19 or level
        t:observe(p, now)
        if random(3) ~= 0 then
            local amount = 20 + random(480)
            local kind = level == 75 and random(2) == 0 and 'lp' or 'exp'
            local event = { kind = kind, amount = amount, chain = random(8), token = tostring(step),
                source = step % 9 == 0 and 'item' or 'battle' }
            t:award(event, now + 0.05)
            if step % 7 == 0 then t:award(event, now + 0.06) end
            if kind == 'lp' then
                p.lp = p.lp + amount
                if p.lp >= 10000 then
                    if p.merits < p.merit_cap then p.lp = p.lp - 10000; p.merits = p.merits + 1
                    else p.lp = 9999 end
                end
            else p.exp = math.min(p.exp_needed - 1, p.exp + amount) end
            t:observe(p, now + 0.1)
        end
        if step % 29 == 0 then p.merits = math.max(0, p.merits - 2); t:observe(p, now + 0.15) end
        s.tracking.average_count = ({ 1, 3, 10, 37, 100 })[step % 5 + 1]
        s.tracking.rate_basis = step % 2 == 0 and 'earned' or 'net'
        s.display.mode = ({ 'auto', 'exp', 'lp' })[step % 3 + 1]
        s.tracking.goal_type = ({ 'stored_merits', 'level', 'session_exp', 'session_merits', 'buffer' })[step % 5 + 1]
        s.display.short = step % 2 == 0
        for _, window in ipairs({ 0, 300, 900, 1800 }) do
            s.tracking.window = window
            local view = t:view(now + 0.2, s)
            rows[#rows + 1] = { view = copy(view), readouts = copy((readouts.cached or readouts.build)(s, view)) }
        end
    end
end
return rows
'''


def plain(value):
    if luajit21.lua_type(value) == 'table':
        return {key: plain(child) for key, child in value.items()}
    return value


def trace(addon):
    previous = run.ADDON
    run.ADDON = addon
    try:
        with tempfile.TemporaryDirectory(prefix='momentum_trace_') as folder:
            return plain(run.runtime(folder).execute(TRACE))
    finally:
        run.ADDON = previous


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    args = parser.parse_args()
    current = trace(run.ADDON)
    with tempfile.TemporaryDirectory(prefix='momentum_previous_') as folder:
        root = Path(folder)
        with zipfile.ZipFile(args.baseline) as archive:
            for member in archive.infolist():
                if not (root / member.filename).resolve().is_relative_to(root) or not member.filename.startswith('momentum/'):
                    raise ValueError('Unexpected archive path: ' + member.filename)
            archive.extractall(root)
        baseline = trace(root / 'momentum')
    for index, expected in baseline.items():
        if current[index] != expected:
            differing = [key for key in expected if current[index][key] != expected[key]]
            raise AssertionError('Release behavior differs at trace view %d: %s' % (index, differing))
    assert len(current) == len(baseline)
    print('PASS: %d tracking views and readout sets match the previous release.' % len(current))


if __name__ == '__main__':
    main()
