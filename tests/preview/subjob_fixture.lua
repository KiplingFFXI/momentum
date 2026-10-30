local settings = PREVIEW.settings;
if PREVIEW.subjob_case ~= 'menu' then
    settings.bar.docked, settings.bar.auto_width = false, false;
    settings.bar.x, settings.bar.y = 100, 300;
    settings.bar.width = PREVIEW.subjob_case == 'overflow' and 320 or 1100;
    settings.display.alignment, settings.display.groups_enabled = 'left', false;
    settings.display.show_subjob = true;
    settings.display.order = { 'job', 'progress', 'remaining', 'rate' };
    settings.display.divider = ' | ';
end
local order = table.concat(settings.display.order, ',');
local texture = require('ui.job_icons').texture;

function PREVIEW.subjob_row(expected, pictures, centered)
    local p = PREVIEW_PY;
    local left = p.window_x('##momentum_bar') + 9;
    local right = left + p.window_width('##momentum_bar') - 18;
    local first, last, prior, text, images = right, left, left, '', 0;
    local runs = p.hud_runs();
    assert(#runs > 0, 'The subjob bar has no drawn readouts');
    for _, run in ipairs(runs) do
        assert(run.x >= prior - 0.1, 'A subjob readout overlaps the previous reading');
        assert(run.x >= left - 0.1 and run.x + run.width <= right + 0.1, 'A subjob readout escapes the bar');
        first, last, prior = math.min(first, run.x), math.max(last, run.x + run.width), run.x + run.width;
        if run.kind == 'image' then images = images + 1; else text = text .. run.text; end
    end
    assert(text:find(expected, 1, true), 'The drawn job reading is missing: ' .. expected);
    assert(images == pictures, 'The subjob added an icon or lost the main job icon');
    if centered then
        assert(math.abs((first - left) - (right - last)) <= 1, 'The subjob row is not centered');
    end
    assert(table.concat(settings.display.order, ',') == order, 'Subjob changes rearranged the saved readings');
    if PREVIEW.subjob_case == 'overflow' then
        assert(text:find('...', 1, true), 'The narrow subjob bar has no overflow marker');
    elseif PREVIEW.subjob_case == 'wide' then
        assert(not text:find('...', 1, true), 'The wide subjob bar unexpectedly overflows');
    end
    return text;
end

function PREVIEW.subjob_icon(available)
    require('ui.job_icons').texture = available and texture or function() return nil; end;
end
