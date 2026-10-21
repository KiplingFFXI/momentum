local rules = require('data.event_rules');
local checks = 0;
local function eq(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
require('ui.hud').draw = function() return false; end;
require('ui.settings_window').draw = function() return false; end;
local zone_reads = 0;
AshitaCore.GetResourceManager = function() return { GetString = function(_, kind, id)
    if kind == 'zones.names' then zone_reads = zone_reads + 1; return id == 144 and 'Waughroon Shrine' or 'La Theine Plateau'; end
end }; end;
MOCK.load_addon();
MOCK.fire('load');
MOCK.frame(0.25);
local app = MOMENTUM_TEST;
eq(app.view(MOCK.now).events.zone_name, 'La Theine Plateau', 'Current zone uses the client zone name');
local initial_reads = zone_reads;
for _ = 1, 5 do app.sample(MOCK.now); end
eq(zone_reads, initial_reads, 'Stable zone tracking does not reread zone resources');
local area, fight = rules.areas[144];
for _, value in pairs(area.battles) do if value.kind == 'bcnm' then fight = value; break; end end
assert(fight, 'The source catalog includes BCNM content');
local function packet(id, bytes) MOCK.fire('packet_in', MOCK.packet(id, bytes)); end
local utc = os.time();
local zone = MOCK.bytes(60);
MOCK.put(zone, 4, 4, 1001); MOCK.put(zone, 48, 2, 144); MOCK.put(zone, 56, 4, utc);
MOCK.player.zone = 144;
packet(0x00A, zone);
packet(0x061, MOCK.bytes(96));
MOCK.frame(0.25);
local entry = MOCK.bytes(28);
MOCK.put(entry, 4, 4, 1001); MOCK.put(entry, 12, 4, fight.index);
MOCK.put(entry, 26, 2, area.messages.ENTERING_THE_BATTLEFIELD_FOR);
packet(0x02A, entry);
local timer = MOCK.bytes(40);
MOCK.put(timer, 4, 4, 1); MOCK.put(timer, 8, 4, utc - 1009810800);
MOCK.put(timer, 12, 4, 900); MOCK.put(timer, 36, 1, 1);
packet(0x075, timer);
MOCK.frame(0.25);
eq(app.view(MOCK.now).events.kind, 'bcnm', 'Ordinary entry identifies the battlefield category');
eq(app.settings().events.active_kind, 'bcnm', 'Automatic uses the saved BCNM layout');
eq(app.view(MOCK.now).events.time_estimated, false, 'Normal native countdown is preferred');
local before = app.view(MOCK.now).events.remaining;
eq(before > 895 and before <= 900, true, 'Native remaining duration is shown');
app.services.session_pause(true);
eq(app.tracker().paused, true, 'EXP session can be paused');
MOCK.frame(2);
eq(app.view(MOCK.now).events.remaining < before, true, 'Battlefield timer keeps running while paused');
eq(app.services.session_reset(), true, 'EXP session can be reset');
eq(app.view(MOCK.now).events.active, true, 'EXP reset leaves the current battlefield active');
eq(app.view(MOCK.now).events.remaining <= before - 1, true, 'EXP reset does not restart the countdown');
eq(app.view(MOCK.now).rate, nil, 'EXP rate clears on reset');
eq(app.view(MOCK.now).eta, nil, 'Next estimate clears on reset');
local visit = app.view(MOCK.now).events.zone_elapsed;
MOCK.frame(2);
eq(app.view(MOCK.now).events.zone_elapsed > visit, true, 'Zone time is independent of session reset and pause');
app.settings().display.labels.event_time = 'My clock';
eq(app.services.bar_mode('enm'), true, 'ENM can be selected manually');
MOCK.frame(0.25);
eq(app.settings().events.active_kind, 'enm', 'Manual layout overrides Automatic without changing the run');
eq(app.view(MOCK.now).events.kind, 'bcnm', 'Layout selection does not invent an ENM');
eq(app.services.bar_mode('bcnm'), true, 'BCNM layout can be restored');
eq(app.settings().display.labels.event_time, 'My clock', 'Edited readout labels survive mode changes');
eq(app.services.bar_mode('exp'), true, 'Normal EXP layout can be selected during a battlefield');
eq(app.settings().events.active_kind, nil, 'Manual EXP removes the temporary battlefield layout');
eq(app.view(MOCK.now).events.active, true, 'Tracking continues behind the manual EXP layout');
local account = app.account_cooldowns;
account.own.dynamis = { ready_at = os.time() + 10000, character_id = 2002, observed_at = os.time() };
eq(app.view(MOCK.now).dynamis.next_entry_shared, true, 'A grouped observation is identified as shared');
account.own.dynamis = nil;
eq(app.view(MOCK.now).dynamis.next_entry_seconds, nil, 'Removing the shared observation restores unknown eligibility');
eq(app.view(MOCK.now).dynamis.next_entry_shared, nil, 'The old shared-source label is cleared with its observation');
MOCK.fire('unload');
eq(#MOCK.commands, 0, 'Tracking sends no gameplay commands');
return { count = checks };
