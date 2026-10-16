local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local layout = require('ui.layout');
local theme = require('ui.theme');
local checks = 0;
local function equal(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function contains(text, expected, label)
    checks = checks + 1;
    assert(text:find(expected, 1, true), label .. ': ' .. expected .. ' not in ' .. text);
end
equal(readouts.format_number(nil), '--', 'Missing number stays unknown');
equal(readouts.format_number(0), '0', 'Zero is a known value');
equal(readouts.format_number(0 / 0), '--', 'NaN stays unknown');
equal(readouts.format_number(math.huge), '--', 'Infinity stays unknown');
equal(readouts.format_number(12450), '12,450', 'Thousands format');
equal(readouts.format_number(-12450), '-12,450', 'Negative format');
equal(readouts.format_number(12450, true), '12.5k', 'Short format');
equal(readouts.format_time(nil), '--', 'Unknown time stays unknown');
equal(readouts.format_time(0), '0:00', 'Zero time is known');
equal(readouts.format_time(3661), '1h 01m', 'Long duration format');

local settings = defaults.make();
local view = readouts.sample('Leveling');
contains(readouts.text(settings, view), 'EXP 12,450 / 20,000', 'Current EXP uses view values');
contains(readouts.text(settings, view), 'EXP/HR 8,500', 'Default rate puts the label before the value');
contains(readouts.text(settings, view), 'Chain 4 (+40%)', 'Confirmed chain bonus');
settings.display.order = { 'chain_time' };
settings.display.enabled.chain_time = true;
equal(readouts.text(settings, view), 'Next chain ~0:38', 'Local timing shows one estimated countdown');
view.chain_left_min, view.chain_estimated = 10, true;
equal(readouts.text(settings, view), 'Next chain ~0:38', 'Legacy estimated fields cannot turn the local timer into a range');
view.chain_source = 'local';
equal(readouts.text(settings, view), 'Next chain ~0:38', 'Local timing has a single estimate instead of a range');
view.chain_estimated = false;
equal(readouts.text(settings, view), 'Next chain ~0:38', 'Local source remains visibly estimated');
view.chain_left = nil;
equal(readouts.text(settings, view), 'Next chain --', 'An expired local estimate does not invent time remaining');
view.chain_left = 38;
view.chain_source = 'unknown';
equal(readouts.text(settings, view), 'Next chain --', 'Unsupported timing is not shown as a deadline');
view.chain_source = nil;
equal(readouts.text(settings, view), 'Next chain --', 'A countdown without source stays unknown');
view.chain_source, view.chain_left = 'local', 0;
equal(readouts.text(settings, view), 'Next chain ~0:00', 'A zero local countdown stays a known estimate');
for _, value in ipairs({ -1, math.huge, -math.huge, 0 / 0, '38' }) do
    view.chain_left = value;
    equal(readouts.text(settings, view), 'Next chain --', 'Invalid local timing stays unknown without an estimate prefix');
end
view.chain_left = nil;
contains(readouts.text(settings, view), '--', 'Unknown chain expiry does not invent countdown');

settings.display.order = { 'remaining', 'job', 'rate' };
settings.display.enabled.remaining = false;
settings.display.enabled.job = true;
settings.display.enabled.rate = true;
local text = readouts.text(settings, readouts.sample('Leveling'));
equal(text:sub(1, 6), 'WAR 61', 'First enabled item has no leading separator');
settings.display.divider = ' / ';
contains(readouts.text(settings, readouts.sample('Leveling')), ' / ', 'Custom separator is used');
settings.display.dividers.rate = false;
equal(readouts.text(settings, readouts.sample('Leveling')):find('/', 1, true) ~= nil, true, 'Rate unit remains when divider is hidden');
equal(layout.segments(readouts.build(settings, view), settings.display)[2].text, '', 'Per-readout separator is disabled');

settings = defaults.make();
for _, item in ipairs(defaults.READOUTS) do settings.display.enabled[item.id] = true; end
view = readouts.sample('No data');
local built = readouts.build(settings, view);
for _, item in ipairs(built) do
    if item.id ~= 'status' then equal(item.value, '--', 'No-data value ' .. item.id); end
end
view = readouts.sample('Merits');
contains(readouts.text(settings, view), 'LP 7,250 / 10,000', 'LP mode uses LP progress');
contains(readouts.text(settings, view), 'Merits 3 / 10', 'Stored merits include actual cap');
contains(readouts.text(settings, view), 'Merits/hr 1.25', 'LP pace converts to merit pace');
view.rate, view.eta, view.goal_eta = 0, 300, 300;
for _, item in ipairs(readouts.build(settings, view)) do
    if item.id == 'eta' then equal(item.value, '--', 'No ETA at zero rate'); end
end
local before_order = table.concat(settings.display.order, ',');
settings.display.labels.progress = 'Custom';
for _, name in ipairs(theme.names) do
    equal(theme.apply(settings, name), true, name .. ' exists');
    equal(table.concat(settings.display.order, ','), before_order, name .. ' preserves ordering');
    equal(settings.display.labels.progress, 'Custom', name .. ' preserves labels');
end
contains(readouts.summary(readouts.sample('Leveling')), 'EXP lost: 525 | Recovered: 350', 'Recovery stays separate from rewards');
contains(readouts.summary(readouts.sample('Leveling')), 'At a cap, EXP or LP received can be more than the amount you keep', 'Summary explains caps');

settings = defaults.make();
settings.display.order = { 'rate' };
view = readouts.sample('Leveling');
view.rate = nil;
equal(readouts.text(settings, view), 'EXP/HR --', 'Collecting EXP rate keeps label before unknown value');
view.mode = 'lp';
equal(readouts.text(settings, view), 'LP/HR --', 'Collecting LP rate uses the matching label');
view.rate = 8500;
settings.display.label_position = 'after';
equal(readouts.text(settings, view), '8,500 LP/HR', 'Optional label-after rate');
settings.display.labels.rate = 'Pace';
settings.display.label_divider = ': ';
equal(readouts.text(settings, view), '8,500: Pace LP/HR', 'Custom label and separator survive label-after');
settings.display.label_position = 'before';
equal(readouts.text(settings, view), 'Pace LP/HR: 8,500', 'Custom label and unit before value');
settings.display.order = { 'remaining' };
equal(readouts.text(settings, view), 'TNL: 7,550', 'TNL uses the same label position');
settings.display.label_position = 'after';
equal(readouts.text(settings, view), '7,550: TNL', 'TNL can follow its value');

local suffix = layout.segments({ { id = 'rate', label = 'EXP/HR', value = '8500' },
    { id = 'next', label = 'TNL', value = '9999' } },
    { label_position = 'after', label_divider = ' ', spacing = 0, dividers = {}, divider = '|' });
local function fitted(width)
    local parts = layout.fit(suffix, width, function(value) return #value; end);
    local text = ''; for _, part in ipairs(parts) do text = text .. part.text; end
    return text;
end
equal(fitted(14), '8500 EXP/HR...', 'Overflow keeps a completed suffix');
equal(fitted(9), '...', 'Overflow never leaves a rate without its suffix');
equal(fitted(20), '8500 EXP/HR|9999 TNL', 'Complete suffix readouts fit unchanged');
return { count = checks };
