local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local ids = { 'gil', 'gil_gained', 'gil_spent', 'gil_net', 'gil_rate' };
local fields = { 'current', 'gained', 'spent', 'net', 'rate' };
local settings = defaults.make();
for _, id in ipairs(ids) do eq(settings.display.enabled[id], false, id .. ' starts off'); end
for name in pairs(defaults.STARTER_LAYOUTS) do
    defaults.apply_starter(settings, name);
    for _, id in ipairs(ids) do eq(settings.display.enabled[id], false, name .. ' stays compact without ' .. id); end
end
settings.display.order = ids;
for _, id in ipairs(ids) do settings.display.enabled[id] = true; end
local view = readouts.sample('Leveling');
local function items() return readouts.cached(settings, view); end
local expected = { '125,400', '15,800', '5,800', '10,000', '13,333' };
for _, scenario in ipairs({ 'Leveling', 'Merits', 'Dynamis', 'Paused' }) do
    view = readouts.sample(scenario);
    for index, item in ipairs(items()) do
        eq(item.id, ids[index], scenario .. ' preserves gil readout order');
        eq(item.value, expected[index], scenario .. ' uses the independent gil balance and totals');
    end
end
view.valid = false;
eq(items()[1].value, '125,400', 'Known gil does not need known EXP');
view.gil = nil;
for _, item in ipairs(items()) do eq(item.value, '--', 'Missing gil data stays unknown'); end
view.gil = { current = 0, gained = 0, spent = 0, net = 0 };
for index = 1, 4 do eq(items()[index].value, '0', 'Known zero is shown'); end
eq(items()[5].value, '--', 'An unready rate stays unknown');
view.gil = { current = 999999999, gained = 12500, spent = 20000, net = -7500, rate = -12345.49 };
eq(items()[1].value, '999,999,999', 'Phoenix gil cap uses readable commas');
eq(items()[4].value, '-7,500', 'Spending can leave a negative session change');
eq(items()[5].value, '-12,345', 'Negative rate keeps its sign');
local before = items();
view.gil.rate = -12345.1;
eq(items(), before, 'Rate changes below displayed precision keep the cache');
view.gil.rate = -12345.51;
eq(items()[5].value, '-12,346', 'Rounded rate boundary updates');
settings.display.short = true;
eq(items()[1].value, '1000.0m', 'Short numbers use the existing shared formatter at the cap');
eq(items()[2].value, '12.5k', 'Short gained gil');
eq(items()[5].value, '-12.3k', 'Short negative rate');
before = items();
view.gil.rate = -12349;
eq(items(), before, 'Short rate changes below displayed precision keep the cache');
settings.display.short = false;
for index, field in ipairs(fields) do
    view.gil[field] = 42;
    eq(items()[index].value, '42', 'Each gil field invalidates its readout: ' .. field);
end
settings.display.labels.gil_net = 'My gil';
eq(items()[4].label, 'My gil', 'Custom gil labels are kept');
settings.display.enabled.gil_spent = false;
before = items();
view.gil.spent = 777;
eq(items(), before, 'A hidden gil total does not invalidate the visible line');
settings.display.enabled.gil_spent = true;
settings.display.conditions.gil_rate = 'known';
view.gil.rate = nil;
eq(#items(), 4, 'Show when known hides an unready gil rate');
view.gil.rate = 0;
eq(#items(), 5, 'Show when known includes a zero gil rate');
view.gil.rate = math.huge;
eq(#items(), 4, 'An invalid rate is not a known value');
local migrated = defaults.tidy({ display = { order = { 'rate', 'job' }, labels = { rate = 'My pace' } } });
eq(migrated.display.order[1], 'rate', 'New gil readouts keep the saved first readout');
eq(migrated.display.order[2], 'job', 'New gil readouts keep the saved second readout');
for _, id in ipairs(ids) do eq(migrated.display.enabled[id], false, 'New gil readout stays off for saved layouts: ' .. id); end
return { count = count };
