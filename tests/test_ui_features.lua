local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local layout = require('ui.layout');
local count = 0;
local function eq(a, b, label) count = count + 1; assert(a == b, label .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); end
local s = defaults.make();
eq(s.display.groups_enabled, false, 'Groups remain optional');
eq(s.display.priority_overflow, false, 'Existing overflow remains default');
eq(s.sessions.resume, true, 'Matching sessions resume by default');
local enabled = 0;
for _, item in ipairs(defaults.READOUTS) do if s.display.enabled[item.id] then enabled = enabled + 1; end end
eq(enabled, 5, 'Default bar retains its five readouts');
for _, event in ipairs(defaults.ALERTS) do
    eq(s.alerts.events[event[1]].visual, false, event[1] .. ' visual starts off');
    eq(s.alerts.events[event[1]].sound, false, event[1] .. ' sound starts off');
end
s.sessions.retention, s.tracking.average_count = 0, 900;
s.display.conditions.rate, s.display.groups.rate, s.display.priorities.rate = 'invented', 'bad', math.huge;
s.alerts.events.level.file, s.alerts.events.level.cooldown = 'C:\\sounds\\test.wav', -10;
defaults.tidy(s);
eq(s.sessions.retention, 1, 'Retention cannot delete every record');
eq(s.tracking.average_count, 100, 'Sample bound');
eq(s.display.conditions.rate, 'always', 'Invalid condition restored');
eq(s.display.groups.rate, 'left', 'Invalid group restored');
eq(s.display.priorities.rate, 50, 'Invalid priority restored');
eq(s.alerts.events.level.file, 'test.wav', 'Event sound keeps safe filename');
eq(s.alerts.events.level.cooldown, 0, 'Cooldown nonnegative');
local view = readouts.sample('Leveling');
s.display.order = { 'sync', 'dedication_budget', 'food', 'no_exp', 'average3', 'sample_count', 'exp_rate', 'lp_rate', 'goal' };
for _, id in ipairs(s.display.order) do s.display.enabled[id] = true; end
local function values()
    local result = {}; for _, item in ipairs(readouts.build(s, view)) do result[item.id] = item.value; end; return result;
end
view.sync_active, view.sync_level, view.sync_penalty, view.sync_source = true, 54, 25, 'unknown';
eq(values().sync, '61 > 54 (penalty unknown)', 'Unverified penalty cannot become applied');
view.sync_source = 'server';
eq(values().sync, '61 > 54 (-25%)', 'Server penalty displayed');
eq(values().dedication_budget, '--', 'Unknown pool remains unknown despite active buff');
view.dedication_pool = 0;
eq(values().dedication_budget, '0', 'Authoritative empty pool is known');
eq(values().average3, '198', 'Recent average rounds for display');
eq(values().sample_count, '10 / 10', 'Sample coverage shown');
eq(values().exp_rate, '8,500', 'EXP rate independent');
eq(values().lp_rate, '0', 'Known zero LP rate independent');
view.goal = { available = true, complete = false, remaining = 3000, unit = 'EXP', eta = 600 };
eq(values().goal, '3,000 EXP left (~10:00)', 'Generalized goal units and ETA');
view.goal.available = false;
eq(values().goal, '--', 'Unavailable goal stays unknown');
s.display.conditions.no_exp = 'known';
eq(values().no_exp, nil, 'Unknown condition hides only unknown value');
view.no_exp_reason = 'distance';
eq(values().no_exp, 'Too far for EXP', 'Server reason displayed');
s.display.conditions.food = 'food'; view.food = false;
eq(values().food, nil, 'Inactive food hides conditional field');
s.display.conditions.exp_rate, s.display.conditions.lp_rate = 'exp', 'lp';
eq(values().lp_rate, nil, 'LP-only field hides during EXP');
eq(values().exp_rate, '8,500', 'EXP condition retains value');

s.display.order = { 'chain', 'chain_time' };
s.display.enabled.chain, s.display.enabled.chain_time = true, true;
s.display.conditions.chain, s.display.conditions.chain_time = 'chain', 'chain';
view.chain_source, view.chain_active, view.chain_left = 'local', nil, 38;
eq(values().chain, '4 (+40%)', 'A positive local countdown keeps the conditional observed count');
eq(values().chain_time, '~0:38', 'A positive local countdown keeps the conditional timer');
view.chain_left = nil;
eq(view.chain, 4, 'Local expiry fixture preserves the last confirmed count');
eq(values().chain, nil, 'Expired local timing hides a nonzero historical count when conditional');
eq(values().chain_time, nil, 'Expired local timing hides its conditional timer');
view.chain_source, view.chain_left = 'unknown', 38;
eq(values().chain, nil, 'Unknown timing hides a conditional count even with stale numbers');
eq(values().chain_time, nil, 'Unknown timing hides the conditional timer');
view.chain_source, view.chain_active = 'server', false;
eq(values().chain, nil, 'Server inactive state hides the conditional count');
eq(values().chain_time, nil, 'Server inactive state hides the conditional timer');
view.chain_active, view.chain = true, 0;
eq(values().chain, '0', 'Server active state supports a chain that has not reached chain one');
eq(values().chain_time, '0:38', 'Server active chain zero keeps the conditional countdown');
view.chain_source, view.chain_active, view.chain_left = 'local', nil, 0;
eq(values().chain, nil, 'An expired zero-second local estimate hides conditional readouts');
view.chain_left = math.huge;
eq(values().chain_time, nil, 'Invalid local timing cannot activate a conditional readout');
view.valid, view.chain_source, view.chain_active = false, 'server', true;
eq(values().chain, nil, 'Unavailable player data cannot retain a conditional chain');

local display = defaults.make().display;
display.spacing, display.divider, display.groups_enabled = 1, '|', true;
display.groups = { a = 'left', b = 'center', c = 'right' };
local items = { { id = 'a', label = '', value = 'AAAA' }, { id = 'b', label = '', value = 'BBBB' }, { id = 'c', label = '', value = 'CCCC' } };
local parts = layout.segments(items, display);
parts[1].icon, parts[1].icon_width, parts[1].icon_gap = 123, 2, 1;
local placed, overflow = layout.arrange(parts, 60, string.len, display);
eq(overflow, false, 'Three groups fit');
eq(#placed, 3, 'Each group omits its leading divider');
eq(placed[1].offset, 0, 'Left group anchored');
eq(placed[2].offset, 28, 'Center group centered');
eq(placed[3].offset, 56, 'Right group anchored');
eq(placed[1].icon, 123, 'Icon stays with readout');
display.priorities = { a = 0, b = 10, c = 100 };
display.pinned = { a = true };
placed, overflow = layout.arrange(parts, 25, string.len, display);
eq(overflow, true, 'Insufficient group room is explicit');
local kept = {}; for _, part in ipairs(placed) do kept[part.id] = true; end
eq(kept.a, true, 'Pinned low-priority item is kept');
eq(kept.b, nil, 'Lowest unpinned item removed');
eq(kept.c, true, 'Higher priority right item kept');
eq(kept.overflow, true, 'Overflow remains visible');
local last_end = 0;
for _, part in ipairs(placed) do
    local start = part.offset + (part.gap or 0);
    eq(start >= last_end, true, 'Groups never overlap');
    last_end = start + #part.text + (part.icon_width or 0) + (part.icon_gap or 0);
end
eq(last_end <= 25, true, 'All selected groups remain in bounds');
display.groups_enabled, display.priority_overflow, display.alignment = false, true, 'right';
placed, overflow = layout.arrange(parts, 16, string.len, display);
kept = {}; for _, part in ipairs(placed) do kept[part.id] = true; end
eq(kept.a, true, 'Pinned item survives without groups');
eq(kept.b, nil, 'Priority removes whole readout');
eq(placed[#placed].id, 'overflow', 'Overflow follows original order');
eq(placed[#placed].offset + #placed[#placed].text + (placed[#placed].gap or 0), 16, 'Right alignment retained');
local profiles = require('ui.profiles');
local profile_source = defaults.make();
profile_source.sessions.retention, profile_source.planner.level = 8, 20;
local captured = profiles.capture(profile_source);
eq(captured.sessions, nil, 'Layout profile omits session policy');
eq(captured.planner, nil, 'Layout profile omits planning inputs');
local destination = defaults.make();
profiles.apply(destination, { sessions = { resume = false, retention = 1 }, planner = { level = 20, population = 2000 } });
eq(destination.sessions.retention, 30, 'Old profile cannot change retention');
eq(destination.sessions.resume, true, 'Old profile cannot change resume policy');
eq(destination.planner.level, 50, 'Old profile cannot change planning input');
return { count = count };
