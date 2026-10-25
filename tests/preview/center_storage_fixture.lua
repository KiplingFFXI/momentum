-- These samples render the real UI without a game client.
local readouts = require('ui.readouts');
local settings = PREVIEW.settings;
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y = 100, 300;
settings.bar.width = PREVIEW.center_storage_case == 'overflow' and 360 or 1100;
settings.display.alignment, settings.display.groups_enabled = 'center', false;
settings.display.divider, settings.display.spacing = ' | ', 8;
settings.display.order = { 'inventory_slots', 'inventory_free', 'satchel_slots', 'satchel_free' };
if PREVIEW.center_storage_case ~= 'values' then table.insert(settings.display.order, 1, 'job'); end
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end

local function rendered()
    local p = PREVIEW_PY;
    local runs = p.hud_runs();
    assert(#runs > 0, 'No HUD draw-list runs were recorded');
    local left, right = p.window_x('##momentum_bar') + 9, p.window_x('##momentum_bar') + p.window_width('##momentum_bar') - 9;
    local first, last, prior, text, pictures = right, left, left, '', 0;
    for _, run in ipairs(runs) do
        assert(run.x >= prior - 0.1, 'A readout overlaps the previous readout');
        assert(run.x >= left - 0.1 and run.x + run.width <= right + 0.1, 'A readout escapes the bar');
        first, last, prior = math.min(first, run.x), math.max(last, run.x + run.width), run.x + run.width;
        if run.kind == 'image' then pictures = pictures + 1; else text = text .. run.text; end
    end
    return { runs = runs, left = left, right = right, first = first, last = last, text = text, pictures = pictures };
end

function PREVIEW.capture_storage_left()
    local row = rendered();
    assert(math.abs(row.first - row.left) < 0.1, 'Left reference row does not start at the inner edge');
    PREVIEW.storage_left = row;
    PREVIEW.storage_order = table.concat(settings.display.order, ',');
end

function PREVIEW.check_storage_center(compare_left)
    local row = rendered();
    assert(math.abs((row.first - row.left) - (row.right - row.last)) <= 1, 'Centered row has unequal left and right margins');
    assert(table.concat(settings.display.order, ',') == PREVIEW.storage_order, 'Center changed the saved readout order');
    if PREVIEW.center_storage_case ~= 'values' then
        assert(row.pictures == 1 and row.text:find('(WAR) 61', 1, true), 'Job icon and abbreviation did not stay together');
    end
    if PREVIEW.center_storage_case == 'overflow' then
        assert(row.text:find('...', 1, true), 'A narrow centered bar lost its overflow marker');
    else
        assert(not row.text:find('...', 1, true), 'A wide centered bar unexpectedly overflowed');
    end
    if compare_left then
        local before = PREVIEW.storage_left;
        assert(#before.runs == #row.runs, 'Center changed the number of drawn text and icon runs');
        local shift = row.first - before.first;
        assert(shift > 0, 'Center did not move the reference row');
        for index, run in ipairs(row.runs) do
            local prior = before.runs[index];
            assert(run.kind == prior.kind and run.text == prior.text, 'Center changed the drawn order or values');
            assert(math.abs(run.x - prior.x - shift) < 0.1, 'A label, divider, value, or icon did not move with the row');
        end
    end
end

function PREVIEW.expect_storage(values)
    local text = PREVIEW_PY.drawn_text();
    for _, value in ipairs(values) do assert(text:find(value, 1, true), 'Missing storage readout: ' .. value); end
end

PREVIEW.storage_order = table.concat(settings.display.order, ',');
PREVIEW.storage_cached = function() return readouts.cached(settings, PREVIEW.view); end;
