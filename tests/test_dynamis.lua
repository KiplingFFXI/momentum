local zone, other_zone = 186, 187
local mob = 16777216 + zone * 4096
local other_mob = 16777216 + other_zone * 4096
package.loaded['data.dynamis_rules'] = {
    lockout_seconds = 259200,
    zones = {
        [zone] = { name = 'Dynamis-Bastok', short_name = 'Bastok', starting_seconds = 3600,
            objectives = {
                { id = 'boss', name = 'Boss guards', mobs = { mob + 1, mob + 2 } },
                { id = 'choice', name = 'Boss', mobs = { mob + 3, mob + 4 }, any = true },
            }, weakening = { [mob + 5] = { name = 'Weaken the boss', help = 'Defeat this NM.' } } },
        [other_zone] = { name = 'Dynamis-Beaucedine', short_name = 'Beaucedine' },
    },
    items = {
        [1455] = { name = '1 Byne Bill', kind = 'currency', family = 'byne', value = 1 },
        [1456] = { name = '100 Byne Bill', kind = 'currency', family = 'byne', value = 100 },
        [1449] = { name = 'Tukuku Whiteshell', kind = 'currency', family = 'shell', value = 1 },
        [1453] = { name = 'Montiont Silverpiece', kind = 'currency', family = 'bronze', value = 100 },
        [15001] = { name = 'Warrior relic armor', kind = 'af2', job = 'WAR' },
        [15002] = { name = 'Red Mage relic armor', kind = 'af2', job = 'RDM' },
        [15003] = { name = 'Relic accessory', kind = 'accessory', job = 'WAR' },
    },
}
local dynamis = require('core.dynamis')
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function truth(value, label) equal(not not value, true, label) end
local function near(actual, expected, label)
    checks = checks + 1
    assert(actual and math.abs(actual - expected) < 0.001, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function state(start)
    local result = dynamis.new()
    result:context(42, zone, 0, start or 1000)
    result:hourglass({ zone = zone, start_time = start or 1000, end_time = (start or 1000) + 3600 }, 0, start or 1000)
    return result
end
local function drop(s, slot, id, stamp, now, extra)
    local value = { slot = slot, item_id = id, start_time = stamp, count = 1 }
    for k, v in pairs(extra or {}) do value[k] = v end
    return s:drop(value, now, 1000 + now)
end
local function alert_count(events, id)
    local count = 0
    for _, event in ipairs(events) do if event.id == id then count = count + 1 end end
    return count
end

local s = dynamis.new()
equal(s:view(0, 1000).active, false, 'Not in Dynamis before a client snapshot')
equal(s:context(42, zone, 0, 1000), true, 'Dynamis context starts')
equal(s:view(0, 1000).active, true, 'Recognized zone may show waiting state')
equal(s:view(0, 1000).remaining, nil, 'No invented timer before hourglass')
equal(s:hourglass({ zone = other_zone, start_time = 1000, end_time = 4600 }, 0, 1000), false, 'Wrong hourglass rejected')
equal(s:hourglass({ zone = zone, start_time = 1000, end_time = 999 }, 0, 1000), false, 'Backwards hourglass rejected')
equal(s:hourglass({ zone = zone, start_time = 1000, end_time = math.huge }, 0, 1000), false, 'Nonfinite hourglass rejected')
drop(s, 0, 1455, 500000, 1)
s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 2, 1002)
s:death(mob + 1, 3, 1003)
truth(s:hourglass({ zone = zone, start_time = 1000, end_time = 4600 }, 4, 1004), 'Hourglass activates queued observations')
local view = s:view(4, 1004)
equal(view.remaining, 3596, 'Deadline reflects authoritative UTC')
equal(view.currency_found, 1, 'Early drop retained')
equal(view.currency_received, 1, 'Early receipt retained')
equal(view.kills, 1, 'Early death retained')
equal(view.partial, false, 'Run observed from entry remains complete')
equal(view.objectives[1].done, 1, 'Objective counts observed guard')
equal(view.objectives[1].status, 'incomplete', 'Incomplete observed objective')

s = dynamis.new()
s:context(42, zone, 0, 1000)
for id = 1, 1000 do s:spawn(mob + id, 0, 1000) end
equal(#s.pending, 0, 'Initial live mob updates do not fill the pending event queue')
s:death(mob + 1, 1, 1001)
s:spawn(mob + 1, 2, 1002)
s:death(mob + 1, 3, 1003)
s:hourglass({ zone = zone, start_time = 1000, end_time = 4600 }, 4, 1004)
equal(s:view(4, 1004).kills, 2, 'Spawn cycles observed before hourglass retain their order')

s = state()
local initial_revision = s.revision
equal(drop(s, 0, 1456, 1000000, 10), true, 'Hundred currency enters pool')
equal(drop(s, 0, 1456, 1000000, 11), false, 'Duplicate packet is ignored')
equal(drop(s, 0, 1456, 1000000, 12, { old = true }), false, 'Snapshot does not recount known drop')
s:lot({ slot = 0, kind = 'lot', winner_id = 42 }, 13, 1013)
equal(s:view(13, 1013).currency_received, 0, 'A lot is not a receipt')
s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 14, 1014)
equal(s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 15, 1015), false, 'Duplicate distribution ignored')
equal(drop(s, 0, 1456, 1000000, 16), false, 'Late replay after distribution ignored')
drop(s, 0, 1456, 1000010, 17)
s:lot({ slot = 0, kind = 'win', winner_id = 77 }, 18, 1018)
drop(s, 0, 1455, 1000020, 19, { count = 3 })
s:lot({ slot = 0, kind = 'lost' }, 20, 1020)
drop(s, 1, 1449, 1000030, 21)
drop(s, 2, 1453, 1000040, 22)
view = s:view(60, 1060)
equal(view.currency_found, 304, 'All currency uses actual denomination values')
equal(view.currency_received, 100, 'Only local awarded currency counts as received')
equal(view.currency.byne.found, 203, 'Bills family totals')
equal(view.currency.byne.hundreds_found, 2, 'Hundred-piece quantity stays available')
equal(view.currency.byne.singles_found, 3, 'Single-piece quantity stays available')
equal(view.currency.shell.found, 1, 'Shell family totals')
equal(view.currency.bronze.found, 100, 'Bronze family totals')
equal(view.pool_count, 2, 'Only unresolved slots count toward occupancy')
near(view.currency_rate, 18240, 'Currency rate uses observed run time')
truth(s.revision > initial_revision, 'Persisted changes update revision')
equal(view, s:view(60.5, 1060.5), 'Unchanged second reuses view')
truth(view ~= s:view(61, 1061), 'Next second refreshes timer view')

s = state()
drop(s, 0, 1455, 5000, 1, { token = 'server-packet-1' })
s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 1, 1001)
drop(s, 0, 1455, 5000, 1, { token = 'server-packet-2' })
s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 1, 1001)
equal(s:view(1, 1001).currency_found, 2, 'Solo drops in same server millisecond remain distinct')
equal(s:view(1, 1001).currency_received, 2, 'Immediate solo receipts remain distinct')
equal(drop(s, 0, 1455, 5000, 2, { token = 'server-packet-1' }), false, 'Explicit packet replay still ignored')
drop(s, 1, 1455, 7000, 3, { token = 'server-packet-3' })
equal(drop(s, 1, 1455, 9999999, 4, { old = true, seed = true }), false, 'Memory seed cannot replace an observed packet generation')
equal(s:view(4, 1004).partial, false, 'Memory seeding does not turn a complete observation into a partial run')
equal(s:view(4, 1004).pool[1].remaining, 296, 'Memory seed cannot erase known pool age')

s = state()
drop(s, 0, 15001, 90000, 5, { old = true })
view = s:view(5, 1005)
equal(view.af2, 0, 'Old pool snapshot is not a new AF2 drop')
equal(view.partial, true, 'Existing unseen loot marks partial tracking')
equal(view.pool[1].remaining, nil, 'Server uptime is not mistaken for Unix expiry')
s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 10, 1010)
equal(s:view(10, 1010).af2_received, 1, 'Receipt after old snapshot is known')
drop(s, 1, 15001, 90001, 11)
drop(s, 2, 15002, 90002, 12)
drop(s, 3, 15003, 90003, 13)
view = s:view(13, 1013)
equal(view.af2, 2, 'Accessories do not inflate AF2 armor count')
local events = s:take_alerts(13, { dynamis = { wanted_jobs = { WAR = true } } }, 1013)
equal(alert_count(events, 'dyna_wanted'), 2, 'Job wishlist covers armor and accessories')
equal(alert_count(s:take_alerts(14, {}, 1014), 'dyna_wanted'), 0, 'Wanted alert is emitted once')
drop(s, 4, 15002, 90004, 15)
equal(alert_count(s:take_alerts(15, { dynamis = { wanted_items = { ['15002'] = true } } }, 1015), 'dyna_wanted'), 1, 'Individual item wishlist')

s = state()
s:extension(20, 10, 1010, 'packet-1')
equal(s:extension(20, 10, 1010, 'packet-1'), false, 'Same extension packet token ignored')
s:extension(20, 10, 1010, 'packet-2')
view = s:view(10, 1010)
equal(view.extension_count, 2, 'Simultaneous legitimate extensions remain separate')
equal(view.extension_minutes, 40, 'Extension ledger adds observed minutes')
equal(view.remaining, 3590, 'Announcement cannot invent a new deadline')
s:hourglass({ zone = zone, start_time = 1000, end_time = 7000 }, 11, 1011)
view = s:view(11, 1011)
equal(view.remaining, 5989, 'Updated hourglass adds actual server time')
equal(view.extension_count, 2, 'Hourglass update does not double count extensions')
equal(alert_count(s:take_alerts(11, {}, 1011), 'dyna_extension'), 2, 'Each extension has one optional alert')

s = dynamis.new()
s:context(42, zone, 0, 1300)
s:hourglass({ zone = zone, start_time = 1000, end_time = 6400 }, 0, 1300)
view = s:view(0, 1300)
equal(view.extension_minutes, 30, 'Late arrival recovers total extension minutes from its hourglass')
equal(view.extension_count, 0, 'Late arrival does not invent an extension count')
equal(#view.extensions, 0, 'Late arrival does not invent extension events')
equal(s:export().current.extension_minutes, 0, 'Inferred minutes are kept out of observed ledger')
s:extension(10, 100, 1400, 'later-extension')
s:hourglass({ zone = zone, start_time = 1000, end_time = 7000 }, 101, 1401)
view = s:view(101, 1401)
equal(view.extension_minutes, 40, 'Observed extension after late arrival does not double count inferred minutes')
equal(view.extension_count, 1, 'Only newly observed extension contributes to event count')
equal(s:export().current.extension_minutes, 10, 'Saved active ledger retains only observed minutes')
s:close(102, 1402)
equal(s:view(102, 1402).history[1].extension_minutes, 40, 'History retains recovered total extension minutes')

s = state()
equal(s:death(other_mob + 1, 10, 1010), false, 'Death from another zone ignored')
s:death(mob + 1, 10, 1010)
equal(s:death(mob + 1, 11, 1011), false, 'Repeated death update counted once')
s:death(mob + 2, 12, 1012)
s:death(mob + 4, 13, 1013)
s:death(mob + 5, 14, 1014)
view = s:view(14, 1014)
equal(view.objectives[1].status, 'complete', 'All guards observed dead')
equal(view.objectives[2].complete, true, 'Any-of objective needs one observed death')
equal(view.weakening[1].complete, true, 'Observed weakening objective')
s:spawn(mob + 1, 15)
s:death(mob + 1, 16, 1016)
equal(s:view(16, 1016).kills, 5, 'Confirmed new spawn permits a second kill')
drop(s, 0, 1456, 1, 17)
s:effects({ subjob_locked = true, clear_owned = false, weakness_seconds = 600 }, 17)
s:extension(10, 18, 1018)
s:clear_totals(20, 1020)
view = s:view(20, 1020)
equal(view.remaining, 3580, 'Clear totals keeps entry timer running')
equal(view.currency_found, 0, 'Clear totals clears currency tally')
equal(view.currency_rate, nil, 'Cleared currency rate is blank')
equal(view.kills, 0, 'Clear totals clears observed kill count')
equal(view.objectives[1].complete, true, 'Clear totals keeps earned objectives')
equal(view.extension_count, 1, 'Clear totals keeps earned time extensions')
equal(view.weakness_seconds, 597, 'Weakness keeps running')
equal(view.pool_count, 1, 'Unresolved treasure pool survives tally reset')
equal(view.partial, true, 'Tally reset marks partial run')
s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 21, 1021)
equal(s:view(21, 1021).currency_received, 100, 'Pre-reset pending loot can be received afterward')
s:effects({ subjob_locked = false, clear_owned = true }, 22)
events = s:take_alerts(22, {}, 1022)
equal(alert_count(events, 'dyna_subjob'), 1, 'Unlock transition alert')
equal(alert_count(events, 'dyna_clear'), 1, 'New clear key item alert')
s:effects({ subjob_locked = false, clear_owned = true }, 23)
equal(#s:take_alerts(23, {}, 1023), 0, 'Stable effects do not spam alerts')
s:effects({ weakness_unknown = true }, 24)
equal(s:view(24, 1024).weakness_seconds, nil, 'Invalid status timer invalidates old weakness countdown')
s:effects({ weakness_seconds = 500 }, 25)
s:effects({ weakness_seconds = 0 }, 26)
equal(s:view(26, 1026).weakness_seconds, 0, 'Removed weakness clears its countdown')

s = state()
s:effects({ weakness_seconds = 0 }, 0)
local clear_view = s:view(2, 1002)
equal(s:effects({ weakness_seconds = 0 }, 2.5), false, 'Repeated no-Weakness sample does not change state')
equal(s:view(2.5, 1002.5), clear_view, 'Repeated no-Weakness sample keeps current second cached')
equal(s:effects({ weakness_seconds = 300 }, 3), true, 'New Weakness starts a countdown')
equal(s:view(3, 1003).weakness_seconds, 300, 'New Weakness duration is preserved')
local weak_view = s:view(3, 1003)
equal(s:effects({ weakness_seconds = 299.5 }, 3.5), false, 'Stable Weakness deadline keeps cached state')
equal(s:view(3.5, 1003.5), weak_view, 'Stable Weakness sample keeps current second cached')
equal(s:effects({ weakness_unknown = true }, 4), true, 'Missing Weakness timer invalidates known deadline')
equal(s:view(4, 1004).weakness_seconds, nil, 'Missing Weakness timer remains unknown')
equal(s:effects({ weakness_seconds = 200 }, 5), true, 'Known Weakness timer returns after missing sample')
equal(s:view(5, 1005).weakness_seconds, 200, 'Recovered Weakness countdown stays accurate')
equal(s:effects({ weakness_seconds = 0 }, 6), true, 'Ending Weakness clears the active timer')
clear_view = s:view(7, 1007)
equal(clear_view.weakness_seconds, 0, 'Ended Weakness stays at zero')
equal(s:effects({ weakness_seconds = 0 }, 7.5), false, 'Ended Weakness remains stable')
equal(s:view(7.5, 1007.5), clear_view, 'Ended Weakness keeps current second cached')

s = state()
s:effects({ subjob_locked = false, clear_owned = true }, 0)
equal(#s:take_alerts(0, {}, 1000), 0, 'Existing clear and unlocked subjob are not new acquisitions')
equal(alert_count(s:take_alerts(3000, {}, 4000), 'dyna_time'), 1, 'Ten-minute warning')
equal(alert_count(s:take_alerts(3001, {}, 4001), 'dyna_time'), 0, 'Ten-minute warning does not repeat')
equal(alert_count(s:take_alerts(3300, {}, 4300), 'dyna_time'), 1, 'Five-minute warning')
equal(alert_count(s:take_alerts(3540, {}, 4540), 'dyna_time'), 1, 'One-minute warning')
equal(alert_count(s:take_alerts(3600, {}, 4600), 'dyna_time'), 0, 'No misleading one-minute warning at zero')
s:hourglass({ zone = zone, start_time = 1000, end_time = 8200 }, 3601, 4601)
s:take_alerts(3602, {}, 4602)
equal(alert_count(s:take_alerts(6600, {}, 7600), 'dyna_time'), 1, 'Extension rearms future warning')

s = state()
for slot = 0, 8 do drop(s, slot, 1455, slot + 1, 1) end
equal(alert_count(s:take_alerts(1, {}, 1001), 'dyna_pool'), 1, 'Nearly full treasure pool warning')
equal(alert_count(s:take_alerts(2, {}, 1002), 'dyna_pool'), 0, 'Occupancy warning does not repeat')
for slot = 1, 8 do s:lot({ slot = slot, kind = 'win', winner_id = 77 }, 3, 1003) end
equal(alert_count(s:take_alerts(240, {}, 1240), 'dyna_pool'), 1, 'Old pending loot warning')
equal(alert_count(s:take_alerts(241, {}, 1241), 'dyna_pool'), 0, 'Pending warning only once per item generation')
view = s:view(242, 1242)
equal(view.pool[1].remaining, 56, 'Freshly observed pool age follows server five-minute lifetime')
truth(view.pool[1].approximate, 'Pool age is explicitly approximate')
s:drop({ slot = 0, item_id = 0, old = true }, 243, 1243)
equal(s:view(243, 1243).pool_count, 0, 'Empty snapshot clears stale pool slot')

s = state()
for slot = 0, 8 do drop(s, slot, 1455, slot + 1, 1) end
s:take_alerts(1, {}, 1001)
equal(alert_count(s:take_alerts(240, {}, 1240), 'dyna_pool'), 1, 'Many aging pool items use one reminder')
truth(pcall(function() s:take_alerts(241, { dynamis = { warning_minutes = false } }, 1241) end), 'Malformed optional warning list is safe')

s = state()
s:registration(zone, 20, 1020)
equal(s:view(20, 1020).next_entry_seconds, 259200, 'Observed registration supplies entry cooldown')
drop(s, 0, 1456, 1, 21)
s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 22, 1022)
s:death(mob + 1, 23, 1023)
s:extension(10, 24, 1024)
local json = require('json')
local saved = json.decode(json.encode(s:export()))
local restored = dynamis.new()
equal(restored:restore(saved, 0, 1100), true, 'Restore bounded run data')
equal(restored:view(0, 1100).active, false, 'Restore waits for live character context')
restored:context(42, zone, 1, 1101)
equal(restored:view(1, 1101).remaining, nil, 'Restored run waits for current hourglass')
restored:hourglass({ zone = zone, start_time = 1000, end_time = 4600 }, 2, 1102)
view = restored:view(2, 1102)
equal(view.remaining, 3498, 'Reloaded timer includes elapsed offline time')
equal(view.currency_found, 100, 'Reload retains found currency')
equal(view.currency_received, 100, 'Reload retains received currency')
equal(view.kills, 1, 'Reload retains confirmed kill tally')
equal(view.extension_minutes, 10, 'Reload retains extension ledger')
equal(view.partial, true, 'Reloaded observation gap is explicit')
equal(view.objectives[1].status, 'unknown', 'Unfinished objective not assumed untouched during gap')
equal(view.next_entry_seconds, 259118, 'Entry cooldown survives reload')
equal(restored:death(mob + 1, 3, 1103), false, 'Repeated death after reload does not inflate count')
restored:context(42, 100, 5, 1105)
view = restored:view(5, 1105)
equal(view.active, false, 'Leaving zone hides Dynamis live readings')
equal(#view.history, 1, 'Leaving zone saves run summary')
equal(view.history[1].currency_found, 100, 'Summary preserves found totals')
local outside = json.decode(json.encode(restored:export()))
local history_restore = dynamis.new()
equal(history_restore:restore(outside, 6, 1106), true, 'History and last run can be restored outside Dynamis')
history_restore:context(42, zone, 7, 1107)
history_restore:hourglass({ zone = zone, start_time = 1000, end_time = 4600 }, 8, 1108)
equal(history_restore:view(8, 1108).currency_found, 100, 'Reentry resumes same hourglass run')
equal(#history_restore:view(8, 1108).history, 0, 'Resumed run is not duplicated in history')
history_restore:context(42, other_zone, 9, 1109)
history_restore:hourglass({ zone = other_zone, start_time = 1109, end_time = 4709 }, 9, 1109)
equal(history_restore:view(9, 1109).currency_found, 0, 'Another zone gets independent run totals')
equal(history_restore:view(9, 1109).next_entry_seconds, 259111, 'Entry cooldown applies to every Dynamis zone')
history_restore:context(77, zone, 10, 1110)
equal(#history_restore:view(10, 1110).history, 0, 'Character switch does not expose other character history')

local bad = s:export()
bad.version = 999
local revision = restored.revision
equal(restored:restore(bad, 9, 1200), false, 'Unknown save version rejected')
equal(restored.revision, revision, 'Rejected restore is atomic')
bad = s:export(); bad.current.end_time = 0 / 0
equal(restored:restore(bad, 9, 1200), false, 'Nonfinite saved timer rejected')
bad = s:export(); bad.current.loot['1456'].received = -1
equal(restored:restore(bad, 9, 1200), false, 'Negative saved currency rejected')
bad = s:export(); bad.current.dead[other_mob + 1] = true
equal(restored:restore(bad, 9, 1200), false, 'Cross-zone saved deaths rejected')
bad = s:export(); bad.history.extra = {}
equal(restored:restore(bad, 9, 1200), false, 'Non-array history rejected')
bad = s:export(); bad.lockouts[999] = 3000
equal(restored:restore(bad, 9, 1200), false, 'Unsupported lockout zone rejected')
bad = s:export(); bad.player_id = 99
equal(restored:restore(bad, 9, 1200), false, 'Other character save rejected')

s = dynamis.new()
s:context(42, zone, 0, 1000)
for i = 1, 50 do s:death(mob + i, i, 1000 + i) end
s:hourglass({ zone = zone, start_time = 1000, end_time = 4600 }, 51, 1051)
equal(s:view(51, 1051).kills, 32, 'Pre-hourglass event queue is bounded')
equal(s:view(51, 1051).partial, true, 'Dropped early observations mark partial tracking')
for i = 1, 1100 do
    drop(s, 0, 1455, i, 100 + i)
    s:lot({ slot = 0, kind = 'win', winner_id = 42 }, 100 + i, 1100 + i)
end
truth(#s.token_order <= 1024, 'Packet dedupe storage stays bounded')
for i = 1, 40 do
    s:close(2000 + i, 10000 + i * 4000)
    s:context(42, zone, 2000 + i, 10000 + i * 4000)
    s:hourglass({ zone = zone, start_time = 10000 + i * 4000, end_time = 13600 + i * 4000 }, 2000 + i, 10000 + i * 4000)
end
equal(#s:view(2040, 170000).history, 30, 'Run history bounded to thirty entries')
equal(#s:view(2041, 170001, { dynamis = { retention = 3 } }).history, 3, 'History retention option trims oldest runs')
local many = s:export()
local row = many.history[1]
many.history = {}
for index = 1, 100 do many.history[index] = row end
local largest = dynamis.new()
equal(largest:restore(many, 2041, 170001), true, 'Largest supported history restores')
equal(#largest:view(2041, 170001, { dynamis = { retention = 100 } }).history, 100, 'Configured hundred-run history remains available')
many.history[101] = row
equal(largest:restore(many, 2042, 170002), false, 'History beyond supported maximum rejected')

for _, offset in ipairs({ -60, -30, 0, 30, 60 }) do
    local utc = 1800000000
    local clock_skew = dynamis.new()
    clock_skew:context(42, zone, 0, utc)
    local glass = { zone = zone, start_time = utc + offset, end_time = utc + offset + 3600 }
    equal(clock_skew:hourglass(glass, 0, utc), true, 'Bounded clock skew accepts current hourglass')
    clock_skew:drop({ slot = 0, item_id = 1455, count = 1, token = 'skew' }, 0, utc)
    local payload = json.decode(json.encode(clock_skew:export()))
    equal(payload.current.start_time, glass.start_time, 'Clock skew keeps authoritative entry time')
    equal(payload.current.end_time, glass.end_time, 'Clock skew keeps authoritative deadline')
    equal(payload.current.tally_since, math.max(utc, glass.start_time), 'Tally cannot start before the run')
    local reload = dynamis.new()
    equal(reload:restore(payload, 1, utc), true, 'Clock-skewed run can reload its own save')
    reload:context(42, zone, 1, utc)
    reload:hourglass(glass, 1, utc)
    equal(reload:view(1, utc).elapsed, 0, 'Early clock has no negative elapsed time')
    equal(reload:view(1, utc).currency_rate, nil, 'Early clock has no premature currency rate')
    local tally = payload.current.tally_since
    equal(reload:view(2, tally + 59).currency_rate, nil, 'Reload waits for a minute of tracked time')
    equal(reload:view(3, tally + 60).currency_rate, 60, 'Currency rate starts after tracked minute')
    equal(clock_skew:clear_totals(1, utc), true, 'Totals can clear before clock catches up')
    payload = json.decode(json.encode(clock_skew:export()))
    equal(dynamis.new():restore(payload, 2, utc), true, 'Cleared clock-skewed run remains restorable')
    equal(payload.current.tally_since, math.max(utc, glass.start_time), 'Clear keeps tally within run')
    clock_skew:close(2, utc)
    local finished = clock_skew:export()
    equal(finished.history[1].elapsed, 0, 'Early exit has no negative tracked time')
    equal(dynamis.new():restore(finished, 3, utc), true, 'Early exit history remains restorable')
end
local future = dynamis.new()
future:context(42, zone, 0, 1800000000)
equal(future:hourglass({ zone = zone, start_time = 1800000061, end_time = 1800003661 }, 0, 1800000000),
    false, 'Hourglass beyond tolerated clock skew stays rejected')

local original_sort, sorts = table.sort, 0
table.sort = function(values, compare)
    sorts = sorts + 1
    return original_sort(values, compare)
end
local idle = dynamis.new()
idle:context(42, 100, 0, 1000)
for second = 0, 120 do idle:view(second, 1000 + second) end
equal(sorts, 0, 'Idle outside Dynamis never sorts empty readouts')
s = state()
drop(s, 2, 1455, 700, 1)
s:view(1, 1001)
equal(sorts, 0, 'Single pool item and loot row do not need sorting')
drop(s, 0, 1456, 701, 2)
view = s:view(2, 1002)
equal(sorts, 2, 'Multiple pool and loot rows still sort')
equal(view.pool[1].slot, 0, 'Pool rows keep their slot order')
equal(view.loot[1].name, '1 Byne Bill', 'Loot rows keep their name order')
table.sort = original_sort

return { count = checks }
