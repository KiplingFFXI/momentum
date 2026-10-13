local layout = {};

function layout.clamp(value, low, high)
    return math.max(low, math.min(math.max(low, high), value));
end

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge;
end

local function chat_bounds(chat, screen_width, screen_height)
    if type(chat) ~= 'table' or not finite(chat.x) or not finite(chat.y) or not finite(chat.width) or not finite(chat.height)
        or chat.width <= 0 or chat.height <= 0 then return nil; end
    local left, right = math.max(0, math.ceil(chat.x)), math.min(screen_width, math.floor(chat.x + chat.width));
    local top, bottom = math.max(0, math.floor(chat.y)), math.min(screen_height, math.ceil(chat.y + chat.height));
    if right <= left or bottom <= top then return nil; end
    return { x = left, y = top, width = right - left, height = bottom - top };
end

function layout.dock(bar, screen_width, screen_height, chat, anchor)
    local bounds = chat_bounds(chat, screen_width, screen_height);
    if not bounds then return { hidden = true, reason = 'Waiting for the chat window.' }; end
    anchor = (anchor or bar.anchor) == 'top' and 'top' or 'bottom';
    local start = layout.clamp(finite(bar.start) and bar.start or 0, 0, math.max(0, bounds.width - 120));
    local left, right = bounds.x + start, bounds.x + bounds.width;
    local top, bottom = bounds.y, bounds.y + bounds.height;
    for _, other in ipairs(chat.windows or {}) do
        local area = chat_bounds(other, screen_width, screen_height);
        if area and area.x < right and area.x + area.width > left then
            top, bottom = math.min(top, area.y), math.max(bottom, area.y + area.height);
        end
    end
    local gap = math.max(2, bar.bottom);
    local available = anchor == 'top' and top - gap or screen_height - bottom - gap;
    local height = math.min(bar.height, screen_height);
    if available < math.min(12, height) then
        return { hidden = true, anchor = anchor, reason = anchor == 'top'
            and 'There is not enough room above chat. Choose Below chat or Free placement.'
            or 'There is not enough room below chat. Choose Above chat or Free placement.' };
    end
    height = math.min(height, available);
    local y = anchor == 'top' and top - gap - height or bottom + gap;
    return { x = left, y = y, width = right - left, height = height, anchor = anchor };
end

function layout.rect(bar, screen_width, screen_height, chat, content_width, keep_visible)
    screen_width = math.max(1, screen_width);
    screen_height = math.max(1, screen_height);
    if bar.docked and (chat or not keep_visible) then return layout.dock(bar, screen_width, screen_height, chat); end
    local width = math.min(bar.width, screen_width);
    if bar.auto_width and finite(content_width) then width = math.min(width, math.max(1, math.ceil(content_width))); end
    local height = math.min(bar.height, screen_height);
    local x = layout.clamp(bar.x, 0, screen_width - width);
    local y = layout.clamp(bar.y, 0, screen_height - height);
    return { x = x, y = y, width = width, height = height };
end

function layout.move(bar, x, y, screen_width, screen_height, release, rendered_width, chat)
    bar.docked = false;
    local rect = layout.rect(bar, screen_width, screen_height, nil, rendered_width);
    bar.x = layout.clamp(x, 0, screen_width - rect.width);
    bar.y = layout.clamp(y, 0, screen_height - rect.height);
    if release and bar.snap then
        local preferred = bar.anchor == 'top' and 'top' or 'bottom';
        local selected, distance;
        for _, anchor in ipairs({ preferred, preferred == 'top' and 'bottom' or 'top' }) do
            local dock = layout.dock(bar, screen_width, screen_height, chat, anchor);
            if not dock.hidden and bar.x < dock.x + dock.width and bar.x + rect.width > dock.x then
                local delta = math.abs(bar.y - dock.y);
                if delta <= 18 and (not distance or delta < distance) then selected, distance = dock, delta; end
            end
        end
        if selected then bar.docked, bar.anchor = true, selected.anchor; end
    end
end

function layout.detach(bar, rect)
    if type(rect) ~= 'table' or rect.hidden or not finite(rect.x) or not finite(rect.y)
        or not finite(rect.width) or not finite(rect.height) or rect.width <= 0 or rect.height <= 0 then return false; end
    bar.x, bar.y, bar.width, bar.height = rect.x, rect.y, rect.width, rect.height;
    bar.docked, bar.auto_width = false, false;
    return true;
end

function layout.resize(bar, width, height, screen_width, screen_height)
    bar.auto_width = false;
    bar.width = layout.clamp(width, math.min(120, screen_width), screen_width);
    bar.height = layout.clamp(height, math.min(12, screen_height), math.min(120, screen_height));
    if not bar.docked then
        bar.x = layout.clamp(bar.x, 0, screen_width - bar.width);
        bar.y = layout.clamp(bar.y, 0, screen_height - bar.height);
    end
end

function layout.reorder(order, from, to)
    if from < 1 or from > #order or to < 1 or to > #order or from == to then return false; end
    local id = table.remove(order, from);
    table.insert(order, to, id);
    return true;
end

-- A hidden item never leaves a leading or doubled divider.
function layout.segments(items, display)
    local result = {};
    for index, item in ipairs(items) do
        if index > 1 then
            local separator = display.dividers[item.id] ~= false and display.divider or '';
            result[#result + 1] = { text = separator, role = 'divider', gap = display.spacing, id = item.id };
        end
        local after = display.label_position == 'after';
        if item.label ~= '' and not after then result[#result + 1] = { text = item.label .. display.label_divider, role = 'label', id = item.id }; end
        result[#result + 1] = { text = item.value, role = item.role or 'text', id = item.id };
        if item.label ~= '' and after then result[#result + 1] = { text = display.label_divider .. item.label, role = 'label', suffix = true, id = item.id }; end
    end
    return result;
end

function layout.fit(segments, width, measure, overflow_text)
    local full = 0;
    local function size(segment)
        return measure(segment.text) + (segment.gap or 0) + (segment.icon_width or 0) + (segment.icon_gap or 0);
    end
    for _, segment in ipairs(segments) do full = full + size(segment); end
    if full <= width then return segments, false; end
    local room = math.max(0, width - measure(overflow_text or '...'));
    local result, used = {}, 0;
    for _, segment in ipairs(segments) do
        local length = size(segment);
        if used + length > room then
            if segment.suffix then
                while #result > 0 and result[#result].id == segment.id do table.remove(result); end
            end
            break;
        end
        result[#result + 1] = segment;
        used = used + length;
    end
    while #result > 0 and (result[#result].role == 'divider' or result[#result].role == 'label' and not result[#result].suffix) do table.remove(result); end
    result[#result + 1] = { text = overflow_text or '...', role = 'warning', id = 'overflow' };
    return result, true;
end

-- Keep complete readouts together when groups or overflow priorities are enabled.
function layout.arrange(segments, width, measure, display)
    local measured = {};
    local function size(part)
        if not measured[part] then measured[part] = measure(part.text) + (part.gap or 0) + (part.icon_width or 0) + (part.icon_gap or 0); end
        return measured[part];
    end
    local function total(parts)
        local value = 0; for _, part in ipairs(parts) do value = value + size(part); end
        return value;
    end
    local function finish(parts, overflow)
        local counts, shown, order = {}, {}, {};
        for _, part in ipairs(segments) do
            if part.role ~= 'divider' then
                if not counts[part.id] then order[#order + 1] = part.id; end
                counts[part.id] = (counts[part.id] or 0) + 1;
            end
        end
        for _, part in ipairs(parts) do if part.role ~= 'divider' then shown[part.id] = (shown[part.id] or 0) + 1; end end
        local hidden = {};
        for _, id in ipairs(order) do if (shown[id] or 0) < counts[id] then hidden[#hidden + 1] = id; end end
        return parts, overflow, hidden;
    end
    local advanced = display.groups_enabled or display.priority_overflow;
    for _, pinned in pairs(display.pinned or {}) do advanced = advanced or pinned; end
    if not advanced then
        local parts, overflow = layout.fit(segments, width, measure);
        local x = display.alignment == 'right' and math.max(0, width - total(parts)) or 0;
        local placed = {};
        for _, part in ipairs(parts) do
            local copy = {}; for key, value in pairs(part) do copy[key] = value; end
            copy.offset = x; placed[#placed + 1] = copy; x = x + size(part);
        end
        return finish(placed, overflow);
    end
    local chunks = {};
    for _, part in ipairs(segments) do
        local chunk = chunks[#chunks];
        if not chunk or chunk.id ~= part.id then
            chunk = { id = part.id, parts = {}, width = 0, leading = 0,
                group = display.groups_enabled and (display.groups[part.id] or 'left') or 'left',
                priority = (display.priorities or {})[part.id] or 50,
                pinned = (display.pinned or {})[part.id] == true or part.id == 'sample' or part.id == 'paused' };
            chunks[#chunks + 1] = chunk;
        end
        local length = size(part);
        if #chunk.parts == 0 and part.role == 'divider' then chunk.leading = length; end
        chunk.width = chunk.width + length;
        chunk.parts[#chunk.parts + 1] = part;
    end
    local overflow = false;
    local overflow_width = measure('...');
    local function widths_for(collect)
        local grouped = collect and { left = {}, center = {}, right = {} } or nil;
        local widths, populated = { left = 0, center = 0, right = 0 }, {};
        for _, chunk in ipairs(chunks) do
            if not chunk.hidden then
                local name = widths[chunk.group] and chunk.group or 'left';
                widths[name] = widths[name] + chunk.width - (not populated[name] and chunk.leading or 0);
                if collect then
                    for _, part in ipairs(chunk.parts) do
                        if populated[name] or part.role ~= 'divider' then grouped[name][#grouped[name] + 1] = part; end
                    end
                end
                populated[name] = true;
            end
        end
        if overflow then
            local name = display.groups_enabled and 'right' or 'left';
            local gap = populated[name] and display.spacing or 0;
            widths[name], populated[name] = widths[name] + overflow_width + gap, true;
            if collect then grouped[name][#grouped[name] + 1] = { text = '...', role = 'warning', id = 'overflow', gap = gap }; end
        end
        local required, count = 0, 0;
        for _, name in ipairs({ 'left', 'center', 'right' }) do
            if populated[name] then required, count = required + widths[name], count + 1; end
        end
        return widths, required + math.max(0, count - 1) * 8, grouped;
    end
    local widths, required = widths_for();
    while required > width do
        local remove;
        for i, chunk in ipairs(chunks) do
            if not chunk.hidden then
                local previous = remove and chunks[remove];
                if not previous or (previous.pinned and not chunk.pinned)
                    or previous.pinned == chunk.pinned and chunk.priority <= previous.priority then remove = i; end
            end
        end
        if not remove then break; end
        chunks[remove].hidden, overflow = true, true;
        widths, required = widths_for();
    end
    local grouped;
    widths, required, grouped = widths_for(true);
    local result = {};
    for _, name in ipairs({ 'left', 'center', 'right' }) do
        local x = 0;
        if display.groups_enabled then
            if name == 'right' then x = math.max(0, width - widths.right);
            elseif name == 'center' then
                local low = widths.left > 0 and widths.left + 8 or 0;
                local high = width - widths.center - (widths.right > 0 and widths.right + 8 or 0);
                x = layout.clamp((width - widths.center) / 2, low, high);
            end
        elseif display.alignment == 'right' then x = math.max(0, width - widths.left); end
        for _, part in ipairs(grouped[name]) do
            local copy = {}; for key, value in pairs(part) do copy[key] = value; end
            copy.offset = x; result[#result + 1] = copy; x = x + size(part);
        end
    end
    return finish(result, overflow);
end

return layout;
