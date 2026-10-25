local layout = require('ui.layout');
local defaults = require('ui.defaults');
local history = require('ui.history');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function width(part)
    return #part.text + (part.gap or 0) + (part.icon_width or 0) + (part.icon_gap or 0);
end
local function used(parts)
    local result = 0;
    for _, part in ipairs(parts) do result = result + width(part); end
    return result;
end
local function signature(parts)
    local result = {};
    for _, part in ipairs(parts) do result[#result + 1] = part.id .. ':' .. part.role .. ':' .. part.text; end
    return table.concat(result, '|');
end
local function centered(parts, available, label)
    equal(#parts > 0, true, label .. ' has visible text');
    local left = parts[1].offset;
    local last = parts[#parts];
    local right = available - last.offset - width(last);
    equal(left, right, label .. ' has equal margins');
    equal(left >= 0, true, label .. ' starts inside the bar');
end

local display = defaults.make().display;
equal(display.alignment, 'left', 'The default stays Left');
display.alignment, display.divider, display.spacing = 'center', '|', 1;
local items = {
    { id = 'job', label = '', value = '(WAR) 32' },
    { id = 'progress', label = 'EXP', value = '102 / 6,000' },
    { id = 'rate', label = 'EXP/HR', value = '12,345' },
};
local parts = layout.segments(items, display);
local before = history.copy(parts);
local placed, overflow, hidden = layout.arrange(parts, 100, string.len, display);
centered(placed, 100, 'A short row');
equal(overflow, false, 'A short row fits');
equal(#hidden, 0, 'Center does not hide a fitting readout');
equal(signature(placed), signature(parts), 'Center keeps the chosen visual order');
equal(history.equal(parts, before), true, 'Placement does not change source segments');

placed, overflow = layout.arrange(parts, used(parts), string.len, display);
centered(placed, used(parts), 'An exact fit');
equal(placed[1].offset, 0, 'An exact fit starts at the inner edge');
equal(overflow, false, 'An exact fit has no overflow marker');
placed = layout.arrange(parts, used(parts) + 11, string.len, display);
centered(placed, used(parts) + 11, 'An odd amount of free space');
equal(placed[1].offset, 5.5, 'Odd free space centers without drifting to one edge');

display.alignment = 'left';
local left, left_overflow, left_hidden = layout.arrange(parts, 26, string.len, display);
display.alignment = 'center';
placed, overflow, hidden = layout.arrange(parts, 26, string.len, display);
centered(placed, 26, 'A fitted overflowing row');
equal(overflow, true, 'Overflow stays explicit');
equal(overflow, left_overflow, 'Center keeps the existing overflow decision');
equal(signature(placed), signature(left), 'Center keeps the fitted text and divider order');
equal(table.concat(hidden, ','), table.concat(left_hidden, ','), 'Center reports the same hidden readouts');

parts[1].icon, parts[1].icon_width, parts[1].icon_gap = 42, 13, 4;
placed, overflow = layout.arrange(parts, 120, string.len, display);
centered(placed, 120, 'A row with a job icon');
equal(placed[1].icon, 42, 'The job icon stays with its readout');
equal(placed[2].offset, placed[1].offset + width(placed[1]), 'Icon width and gap count toward the next position');
equal(overflow, false, 'A fitting icon row has no overflow');
display.label_position = 'after';
parts = layout.segments(items, display);
placed = layout.arrange(parts, 100, string.len, display);
centered(placed, 100, 'Labels after values');
equal(signature(placed), signature(parts), 'Center does not move suffix labels before their values');

local advanced = defaults.make().display;
advanced.alignment, advanced.divider, advanced.spacing = 'center', '|', 1;
advanced.priority_overflow, advanced.pinned, advanced.priorities = true, { job = true }, { job = 0, progress = 100, rate = 1 };
parts = layout.segments(items, advanced);
advanced.alignment = 'left';
left, left_overflow, left_hidden = layout.arrange(parts, 29, string.len, advanced);
advanced.alignment = 'center';
placed, overflow, hidden = layout.arrange(parts, 29, string.len, advanced);
centered(placed, 29, 'Priority overflow without groups');
equal(overflow, true, 'Priority overflow remains visible');
equal(signature(placed), signature(left), 'Center preserves priority selection and remaining order');
equal(table.concat(hidden, ','), table.concat(left_hidden, ','), 'Center preserves priority overflow metadata');
equal(placed[1].id, 'job', 'The pinned job stays visible');
equal(placed[#placed].id, 'overflow', 'Overflow still follows the selected readouts');
advanced.priority_overflow = false;
placed = layout.arrange(parts, 100, string.len, advanced);
centered(placed, 100, 'Pinned readouts without priority overflow');

advanced.groups_enabled, advanced.groups = true, { job = 'right', progress = 'left', rate = 'center' };
advanced.alignment = 'left';
left = layout.arrange(parts, 100, string.len, advanced);
advanced.alignment = 'center';
placed = layout.arrange(parts, 100, string.len, advanced);
equal(signature(placed), signature(left), 'Groups keep their existing visual order');
for index, part in ipairs(placed) do equal(part.offset, left[index].offset, 'Group placement overrides global Center ' .. index); end

display.alignment = 'center';
for _, available in ipairs({ 0, 1, 2, 3, 4, 7 }) do
    placed, overflow = layout.arrange(parts, available, string.len, display);
    for _, part in ipairs(placed) do equal(part.offset >= 0, true, 'A narrow bar never starts text at a negative offset'); end
end
placed, overflow, hidden = layout.arrange({}, 100, string.len, display);
equal(#placed, 0, 'An empty row stays empty');
equal(overflow, false, 'An empty row does not overflow');
equal(#hidden, 0, 'An empty row has no hidden readouts');

local hud = require('ui.hud');
local readouts = require('ui.readouts');
local settings, view = defaults.make(), readouts.sample();
settings.bar.docked, settings.bar.auto_width, settings.bar.width = false, false, 800;
settings.display.order = { 'rate' };
settings.display.enabled.rate = true;
local arrangements = 0;
local original = layout.arrange;
layout.arrange = function(...) arrangements = arrangements + 1; return original(...); end;
local function draw()
    MOCK.imgui_calls = {};
    hud.draw(settings, view, {});
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' and call[6] == '8,500' then return call[4][1]; end
    end
    error('The EXP/HR value was not drawn');
end
local left_x = draw();
settings.display.alignment = 'center';
local center_x, center_arrangements = draw(), arrangements;
equal(center_x > left_x, true, 'Center updates the drawn row immediately');
for _ = 1, 30 do draw(); end
equal(arrangements, center_arrangements, 'Unchanged centered frames reuse the HUD arrangement');
settings.display.alignment = 'right';
equal(draw() > center_x, true, 'Right alignment still moves the same row to the far edge');
layout.arrange = original;

return { count = count };
