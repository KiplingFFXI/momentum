local tracker = require('core.tracker')
local notifications = require('core.notifications')
local rules = require('data.phoenix_rules')
local count = 0
local function equal(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function fixture(quiet)
    local result = {
        tracker = tracker.new(), alerts = notifications.new(), now = 0,
        snapshot = { valid = true, id = 100, job = 1, job_name = 'WAR', zone = 1,
            level = 75, effective_level = 20, exp = 43000, exp_needed = rules.tnl[75],
            lp = 9900, merits = 2, merit_cap = 10, limit_mode = true },
        settings = { alerts = { quiet_paused = quiet, events = {
            merit = { visual = true, sound = true, file = 'example.wav', cooldown = 0 },
        } } },
    }
    function result:sample(seconds, quiet_now)
        self.now = self.now + (seconds or 0.25)
        self.tracker:observe(self.snapshot, self.now)
        local view = self.tracker:view(self.now)
        self.alerts:observe(view, self.snapshot, self.now, self.settings, quiet_now)
        return self.alerts:take(self.now), view
    end
    result.tracker:observe(result.snapshot, 0)
    result.tracker:pause(0, true)
    result:sample()
    return result
end

for _, quiet in ipairs({ false, true }) do
    local state = fixture(quiet)
    state.snapshot.merits, state.snapshot.lp = 3, 100
    local events, view = state:sample()
    equal(view.merits, 3, 'Paused current merit balance still updates')
    equal(view.merits_gained, 0, 'Paused merit gain stays out of session totals')
    equal(view.session_lp, 0, 'Paused alert does not manufacture an LP award')
    equal(view.net_lp, 0, 'Paused alert does not change retained LP totals')
    equal(#events, quiet and 0 or 1, 'Paused merit alert respects the mute choice')
    if not quiet then
        equal(events[1].id, 'merit', 'Observed stored-merit increase produces a merit alert')
        equal(events[1].sound, true, 'The merit alert retains the selected sound option')
    end
    equal(#state:sample(), 0, 'Unchanged balance cannot repeat the merit alert')
    state.tracker:pause(state.now, false)
    state.alerts:set_paused(false)
    equal(#state:sample(), 0, 'Resuming does not replay a paused merit gain')
    state.snapshot.merits, state.snapshot.lp = 4, 200
    events, view = state:sample()
    equal(view.merits_gained, 1, 'A later unpaused merit gain enters session totals')
    equal(#events, 1, 'Stored and session merit increases produce one alert together')
    state.snapshot.merits = 2
    equal(#state:sample(), 0, 'Spending stored merits never produces a gain alert')
    state.snapshot.merits, state.snapshot.lp, state.snapshot.merit_cap = nil, nil, nil
    equal(#state:sample(), 0, 'Unknown merit values remain quiet')
    state.snapshot.merits, state.snapshot.lp, state.snapshot.merit_cap = 5, 100, 10
    equal(#state:sample(), 0, 'Loading an unknown balance cannot invent a merit gain')
end

local state = fixture(false)
state.settings.alerts.events.merit.visual, state.settings.alerts.events.merit.sound = false, false
state:sample()
state.settings.alerts.events.merit.visual = true
state.snapshot.merits, state.snapshot.lp = 3, 100
equal(#state:sample(), 0, 'Enabling the alert during a balance change stays quiet')
state.snapshot.merits, state.snapshot.lp = 4, 200
equal(#state:sample(), 1, 'The next observed merit gain uses the newly armed alert')

state = fixture(false)
state.snapshot.merits, state.snapshot.lp = 3, 100
equal(#state:sample(0.25, true), 0, 'Other mute conditions still silence paused merit alerts')
equal(#state:sample(), 0, 'A muted merit gain is consumed rather than delayed')
state.snapshot.merits = 4
equal(#state:sample(3), 0, 'A stale observation cannot produce a merit alert')
state.snapshot.merits, state.snapshot.zone = 5, 2
equal(#state:sample(), 0, 'Changing zones cannot produce a merit alert')
state.snapshot.merits, state.snapshot.dead = 6, true
equal(#state:sample(), 0, 'Death still suppresses merit alerts')

state = fixture(false)
state.settings.alerts.events.merit.cooldown = 30
state.snapshot.merits = 3
equal(#state:sample(), 1, 'The first paused gain can alert')
state.snapshot.merits = 4
equal(#state:sample(), 0, 'Paused merit gains still respect the alert cooldown')

return count .. ' assertions'
