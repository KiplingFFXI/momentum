local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local details = require('ui.details');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local settings = defaults.make();
local view = readouts.sample('Merits');
settings.display.order = { 'rate', 'merits', 'merit_rate', 'merits_session', 'merit_headroom', 'lp_remaining', 'merit_eta', 'remaining', 'eta' };
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
local function values()
    local result = {};
    for _, item in ipairs(readouts.cached(settings, view)) do result[item.id] = item; end
    return result;
end
eq(readouts.definition('rate').name, 'EXP/HR', 'Rate selector uses the requested name');
local result = values();
eq(result.rate.label, 'LP/HR', 'Main rate follows merit display with truthful units');
eq(result.merits.value, '3 / 10', 'Stored merits stay separate from limit points');
eq(result.merits_session.value, '1', 'Session merit readout counts whole points');
eq(result.merit_headroom.value, '7', 'Free slot readout uses supplied storage space');
eq(result.lp_remaining.value, '2,750', 'Remaining LP uses independent LP progress');
eq(result.merit_eta.value, '~13:12', 'Next merit uses independent LP ETA');
eq(result.merit_rate.value, '1.25', 'Merit rate converts Phoenix LP pace');
view.mode, view.rate, view.eta = 'exp', 5000, 360;
result = values();
eq(result.rate.label, 'EXP/HR', 'Main rate follows EXP mode');
eq(result.merit_rate.value, '1.25', 'Merit rate stays LP-based while EXP is displayed');
eq(result.merit_eta.value, '~13:12', 'Next merit stays LP-based while EXP is displayed');
view.lp.rate = 20000;
eq(values().merit_rate.value, '2.00', 'LP-only rate changes invalidate cached merit rate');
view.merits, view.merit_headroom = 2, 8;
result = values();
eq(result.merits.value, '2 / 10', 'Spending is reflected in stored merit points');
eq(result.merits_session.value, '1', 'Spending does not lower whole points earned');
eq(result.merit_headroom.value, '8', 'Spending frees a stored merit slot');
view.lp.blocked, view.merit_full, view.merit_headroom = true, true, 0;
result = values();
eq(result.lp_remaining.value, 'Spend merits', 'Full storage explains why another merit cannot be earned');
eq(result.merit_eta.value, 'Spend merits', 'Full storage never promises an impossible next-merit time');
eq(result.merit_headroom.value, '0', 'Full storage is a known zero free slots');
eq(result.eta.value, '~6:00', 'Blocked merit conversion does not hide an EXP ETA');
view.mode = 'lp';
result = values();
eq(result.remaining.value, 'Spend merits', 'Mode-following remaining readout explains full storage');
eq(result.eta.value, 'Spend merits', 'Mode-following ETA explains full storage');
view.lp.blocked, view.merit_full = false, false;
view.lp.rate, view.lp.eta = 0, 50;
eq(values().merit_eta.value, '--', 'No next-merit ETA at a zero LP rate');
eq(values().merit_rate.value, '0.00', 'Known zero merit pace remains zero');
view.lp, view.merits, view.merit_cap, view.merit_headroom = {}, nil, nil, nil;
result = values();
eq(result.merits.value, '-- / --', 'Unknown storage does not become zero');
eq(result.merit_headroom.value, '--', 'Unknown capacity does not imply free slots');
eq(result.lp_remaining.value, '--', 'Unknown LP does not invent required progress');
eq(result.merit_eta.value, '--', 'Unknown LP pace has no ETA');
eq(result.merit_rate.value, '--', 'Unknown LP pace has no merit rate');
settings.display.labels.rate = 'My pace';
eq(values().rate.label, 'My pace LP/HR', 'Custom labels survive the standard unit rename');
settings.display.labels.rate = 'LP/hr';
eq(values().rate.label, 'LP/hr', 'A saved matching unit label is preserved without duplication');

local fresh = defaults.make();
for _, id in ipairs({ 'merits_session', 'merit_headroom', 'lp_remaining', 'merit_eta' }) do
    eq(fresh.display.enabled[id], false, 'New readout is opt-in: ' .. id);
end
local order = { 'rate', 'progress' };
local migrated = defaults.tidy({ display = { order = order, labels = { rate = 'My pace' } } });
eq(migrated.display.order[1], 'rate', 'Migration keeps the saved first readout');
eq(migrated.display.order[2], 'progress', 'Migration keeps the saved second readout');
eq(migrated.display.labels.rate, 'My pace', 'Migration keeps the custom label');
local index = {};
for position, id in ipairs(migrated.display.order) do index[id] = position; end
eq(index.merits_session < index.merit_headroom and index.merit_headroom < index.lp_remaining and index.lp_remaining < index.merit_eta, true,
    'Merit fields keep their existing relative order');
eq(index.dyna_zone > index.merit_eta, true, 'Dynamis fields append after existing readouts');

local words = {};
local ui = {
    section = function(title) return title == 'Merit points'; end,
    note = function(text) words[#words + 1] = text; end,
    tip = function() end, help = function() end,
};
view = readouts.sample('Merits');
view.lp.blocked = true;
details.draw(settings, view, {}, ui);
local text = table.concat(words, '\n');
eq(text:find('Stored merit points: 3 / 10', 1, true) ~= nil, true, 'Details distinguishes stored points');
eq(text:find('Merit points gained this session: 1', 1, true) ~= nil, true, 'Details exposes whole points earned');
eq(text:find('Merit points per hour: 1.25', 1, true) ~= nil, true, 'Details explains merit pace');
eq(text:find('Spend some merit points to make room for another.', 1, true) ~= nil, true, 'Details explains the storage block');
eq(text:find('Time:', 1, true), nil, 'Details omits an impossible ETA while blocked');
return { count = count };
