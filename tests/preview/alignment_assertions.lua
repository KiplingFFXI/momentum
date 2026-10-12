local alignment = {};

function alignment.capture(settings)
    local p, name = PREVIEW_PY, '##momentum_bar';
    local runs = p.hud_runs();
    assert(#runs > 0, 'No HUD draw-list runs were recorded');
    assert(math.abs(runs[1].x - p.window_x(name) - 9) < 0.01, 'Left alignment did not begin at the inner edge');
    PREVIEW.alignment_before = {
        runs = runs, x = p.window_x(name), y = p.window_y(name),
        width = p.window_width(name), height = p.window_height(name),
        order = table.concat(settings.display.order, ','),
        anchor = settings.bar.anchor, docked = settings.bar.docked,
        fill_direction = settings.style.fill_direction,
    };
end

function alignment.check(settings)
    local p, name, before = PREVIEW_PY, '##momentum_bar', PREVIEW.alignment_before;
    local runs = p.hud_runs();
    assert(settings.display.alignment == 'right', 'Right alignment was not selected');
    assert(#runs == #before.runs, 'Alignment changed the number of drawn text/image runs');
    assert(p.window_x(name) == before.x and p.window_y(name) == before.y
        and p.window_width(name) == before.width and p.window_height(name) == before.height,
        'Readout alignment moved or resized the bar');
    local shift = runs[1].x - before.runs[1].x;
    assert(shift > 0, 'Right alignment did not move the group');
    local right, pictures, text = before.x, 0, '';
    for index, run in ipairs(runs) do
        local previous = before.runs[index];
        assert(run.kind == previous.kind and run.text == previous.text, 'Alignment changed drawn readout order');
        assert(run.width == previous.width and run.height == previous.height and run.y == previous.y,
            'Alignment changed run size or vertical position');
        assert(math.abs(run.x - previous.x - shift) < 0.01, 'Text, picture or spacing did not move with the group');
        assert(run.x >= before.x + 9 - 0.01 and run.x + run.width <= before.x + before.width - 9 + 0.01,
            'Right-aligned text or picture escaped the padded bar');
        right = math.max(right, run.x + run.width);
        if run.kind == 'image' then pictures = pictures + 1; else text = text .. run.text; end
    end
    assert(math.abs(right - before.x - before.width + 9) < 0.01, 'Group did not finish at the nine-pixel right inset');
    if PREVIEW.expect_icon then
        assert(pictures == 1 and text:find('(WAR) 61', 1, true), 'Job picture and label were not aligned together');
    end
    if PREVIEW.expect_overflow then
        assert(text:find('...', 1, true), 'Narrow right-aligned bar lost its overflow marker');
    else
        assert(not text:find('...', 1, true), 'Readout alignment caused unexpected overflow');
    end
    assert(table.concat(settings.display.order, ',') == before.order, 'Alignment changed the saved readout order');
    assert(settings.bar.anchor == before.anchor and settings.bar.docked == before.docked
        and settings.style.fill_direction == before.fill_direction, 'Alignment changed anchoring or fill direction');
end

return alignment;
