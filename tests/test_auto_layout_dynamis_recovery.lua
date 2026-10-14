local defaults = require('ui.defaults')
local history = require('ui.history')
local rules = require('data.phoenix_rules')
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
require('ui.hud').draw = function() return false end
require('ui.settings_window').draw = function() return false end
local function load(initial, earning)
    local settings = defaults.make()
    settings.display.auto_layout = true
    settings.modes.layout_version, settings.modes.active = 1, initial
    settings.modes.auto = { mode = 'auto', auto_layout = true }
    settings.modes.exp = history.copy(settings.display)
    settings.modes.exp.labels.food = 'My EXP food'
    settings.modes.exp.enabled.food = true
    settings.modes.merits = history.copy(settings.display)
    defaults.apply_starter({ display = settings.modes.merits }, 'Merits')
    settings.modes.merits.labels.lp_rate = 'My LP'
    settings.modes.merits.enabled.job = true
    settings.display = history.copy(settings.modes[initial])
    MOCK.settings_file = settings
    MOCK.player.main_level, MOCK.player.exp_needed = 75, rules.tnl[75]
    MOCK.player.mode, MOCK.player.merit_cap, MOCK.player.exp = earning, 30, 1000
    MOCK.player.zone = 185
    MOCK.load_addon()
    MOCK.frame(0.25)
    return MOMENTUM_TEST
end

local app = load('exp', 'lp')
equal(app.settings().dynamis.layout_active, true, 'Cold load inside Dynamis selects Dynamis')
equal(app.settings().modes.active, 'exp', 'Hidden normal bank has not switched yet')
equal(app.state.auto_layout.mode, 'lp', 'Dynamis observes LP before exit')
MOCK.player.zone = 102
MOCK.frame(0.25)
equal(app.settings().dynamis.layout_active, false, 'Leaving Dynamis restores normal bar')
equal(app.settings().modes.active, 'merits', 'Exit selects Merits even when LP was already cached')
equal(app.settings().display.labels.lp_rate, 'My LP', 'Exit restores saved Merits label')
equal(app.settings().display.enabled.job, true, 'Exit restores extra Merits readouts')
MOCK.fire('unload')

app = load('merits', 'exp')
equal(app.settings().dynamis.layout_active, true, 'Second cold load selects Dynamis')
equal(app.settings().modes.active, 'merits', 'Second hidden bank starts on Merits')
equal(app.state.auto_layout.mode, 'exp', 'Dynamis observes EXP before exit')
MOCK.player.zone = 102
MOCK.frame(0.25)
equal(app.settings().modes.active, 'exp', 'Exit selects EXP even when EXP was already cached')
equal(app.settings().display.labels.food, 'My EXP food', 'Exit restores saved EXP label')
equal(app.settings().display.enabled.food, true, 'Exit restores extra EXP readouts')

app.settings().modes.active = 'merits'
app.settings().display = history.copy(app.settings().modes.merits)
MOCK.frame(0.25)
equal(app.settings().modes.active, 'exp', 'Stale earning cache cannot hide a mismatched layout bank')
equal(app.settings().display.labels.food, 'My EXP food', 'Cache recovery keeps the customized EXP layout')
local automatic = require('ui.modes').automatic
local calls = 0
require('ui.modes').automatic = function(...)
    calls = calls + 1
    return automatic(...)
end
for _ = 1, 60 do MOCK.frame(1 / 60) end
equal(calls, 0, 'Matching layout and earning cache keeps the idle fast path')
equal(app.state.broken, false, 'Recovery stays drawable')
return checks .. ' assertions'
