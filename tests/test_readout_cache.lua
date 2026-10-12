local defaults, readouts = require('ui.defaults'), require('ui.readouts');
local count, builds = 0, 0;
local build = readouts.build;
readouts.build = function(...) builds = builds + 1; return build(...); end;
local function check(value, message) count = count + 1; assert(value, message); end
local function same(actual, expected)
    if #actual ~= #expected then return false; end
    for index, item in ipairs(expected) do
        local other = actual[index];
        if item.id ~= other.id or item.label ~= other.label or item.value ~= other.value or item.role ~= other.role then return false; end
    end
    return true;
end
local settings, view = defaults.make(), readouts.sample();
settings.display.order = { 'rate', 'exp_rate', 'lp_rate', 'merit_rate', 'eta', 'merit_eta' };
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
local function set_rate(value)
    view.rate, view.exp.rate, view.lp.rate = value, value, value;
end
view.eta, view.lp.eta = 60, 90;

-- Compare the retained line with a fresh reading across rounding and unit boundaries.
local samples = { false, 0, -0.1, 0.1, 0.49, 0.5, 0.51, 0.9, 1, 1.49, 1.5,
    49.99, 50, 50.01, 8500.1, 8500.4, 8500.6, 9999.49, 9999.5, 9999.99,
    10000, 10049.99, 10050, 999949.99, 999950, 999999.9, 1000000, 1049999.9, 1050000,
    -10000, -10049.99, -10050, -1000000, math.huge, -math.huge, 0 / 0 };
for _, short in ipairs({ false, true }) do
    settings.display.short = short;
    for _, mode in ipairs({ 'exp', 'lp' }) do
        view.mode = mode;
        for _, sample in ipairs({ false, true }) do
            for _, value in ipairs(samples) do
                set_rate(value);
                check(same(readouts.cached(settings, view, sample), build(settings, view)), 'Cached rates and ETAs match fresh readings at every display boundary.');
            end
            set_rate(nil);
            check(same(readouts.cached(settings, view, sample), build(settings, view)), 'Unknown rates immediately replace the last known readings.');
        end
    end
end

settings.display.short, view.mode = false, 'exp';
set_rate(8500.1);
readouts.cached(settings, view);
local previous = builds;
for frame = 1, 100 do
    set_rate(8500.1 + frame / 1000);
    readouts.cached(settings, view);
end
check(builds == previous, 'All rate readouts retain their line while their rounded values and ETA eligibility stay unchanged.');
settings.display.short = true;
set_rate(1234500);
readouts.cached(settings, view);
previous = builds;
for frame = 1, 40 do set_rate(1234500 + frame); readouts.cached(settings, view); end
check(builds == previous, 'Short rates and hundredth-of-a-merit rates retain identical displayed values.');

settings.display.order = { 'eta', 'merit_eta' };
settings.display.short = false;
set_rate(0);
check(readouts.cached(settings, view)[1].value == '--', 'No pace means no next-level ETA.');
set_rate(0.1);
local line = readouts.cached(settings, view);
check(line[1].value == '~1:00' and line[2].value == '~1:30', 'A small positive rate enables both ETAs even when its displayed pace rounds to zero.');
set_rate(0.2);
previous = builds;
readouts.cached(settings, view);
check(builds == previous, 'ETA-only lines do not rebuild for a changing positive pace.');
view.lp.blocked = true;
check(readouts.cached(settings, view)[2].value == 'Spend merits', 'Full merit storage immediately replaces a cached ETA.');
view.lp.blocked = false;
view.lp.eta = 90.6;
check(readouts.cached(settings, view)[2].value == '~1:31', 'ETA timing still advances at the next displayed second.');
return { count = count };
