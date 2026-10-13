local imgui = require('imgui');
local bit = require('bit');
local layout = require('ui.layout');
local readouts = require('ui.readouts');
local theme = require('ui.theme');
local fonts = require('ui.fonts');
local job_icons = require('ui.job_icons');
local hud = {};
local gesture;
local hover_id, hover_since, hover_updated, hover_title, hover_value, hover_help;
local hover_flags = bit.bor(ImGuiHoveredFlags_AnyWindow, ImGuiHoveredFlags_AllowWhenBlockedByPopup,
    ImGuiHoveredFlags_AllowWhenBlockedByActiveItem);

local function inside(rect, x, y)
    return x >= rect.x and x < rect.x + rect.width and y >= rect.y and y < rect.y + rect.height;
end

local function text_size(settings, height)
    return math.min(settings.style.font_size, math.max(8, height - 4));
end

local render_cache = setmetatable({}, { __mode = 'k' });
local last_context = setmetatable({}, { __mode = 'k' });
local last_render = setmetatable({}, { __mode = 'k' });
local measurements, measurement_order = {}, {};

local function measurer(settings, size)
    local key = tostring(imgui.GetFont()) .. ':' .. settings.style.font .. ':' .. tostring(size);
    local bucket = measurements[key];
    if not bucket then
        if #measurement_order >= 4 then measurements[table.remove(measurement_order, 1)] = nil; end
        bucket = { count = 0, values = {} };
        measurements[key], measurement_order[#measurement_order + 1] = bucket, key;
    end
    return function(text)
        local width = bucket.values[text];
        if width == nil then
            if bucket.count >= 512 then bucket.values, bucket.count = {}, 0; end
            width = imgui.CalcTextSize(text);
            bucket.values[text], bucket.count = width, bucket.count + 1;
        end
        return width;
    end, key;
end

local function parts_for(settings, view, height, sample)
    local font_size = text_size(settings, height);
    local items = readouts.cached(settings, view, sample);
    local has_job, has_status = false, false;
    local keys = { tostring(height), tostring(font_size), tostring(view.job), tostring(sample), tostring(view.paused),
        settings.display.label_position, settings.display.label_divider, settings.display.divider, tostring(settings.display.spacing) };
    for _, item in ipairs(items) do
        has_job, has_status = has_job or item.id == 'job', has_status or item.id == 'status';
        keys[#keys + 1] = tostring(settings.display.dividers[item.id]);
    end
    local texture = view.valid and view.job and has_job and job_icons.texture(view.job) or nil;
    keys[#keys + 1] = tostring(texture);
    local key = table.concat(keys, '\1');
    local slots = render_cache[settings];
    if not slots then slots = {}; render_cache[settings] = slots; end
    local slot = sample and 'sample' or 'live';
    local entry = slots[slot];
    if entry and entry.items == items and entry.key == key then return entry; end
    local parts = layout.segments(items, settings.display);
    if texture then
        for _, part in ipairs(parts) do
            if part.id == 'job' and part.role == 'text' then
                part.icon, part.icon_width, part.icon_gap = texture, math.min(font_size + 2, math.max(8, height - 4)), 4;
                part.text = '(' .. (view.job_name or tostring(view.job)) .. ') ' .. (view.level and tostring(view.level) or '--');
                if view.effective_level and view.level and view.effective_level < view.level then part.text = part.text .. ' (sync ' .. view.effective_level .. ')'; end
                break;
            end
        end
    end
    if sample then table.insert(parts, 1, { text = 'SAMPLE  ', role = 'warning', id = 'sample' });
    elseif view.paused and not has_status then table.insert(parts, 1, { text = 'PAUSED  ', role = 'warning', id = 'paused' }); end
    entry = { key = key, items = items, parts = parts };
    slots[slot] = entry;
    return entry;
end

local function arranged(settings, view, height, sample, width, measure, font_key)
    local entry = parts_for(settings, view, height, sample);
    local display = settings.display;
    local keys = { font_key, tostring(width), tostring(display.groups_enabled), tostring(display.priority_overflow), display.alignment };
    local any_pinned = false;
    for _, pinned in pairs(display.pinned or {}) do any_pinned = any_pinned or pinned; end
    keys[#keys + 1] = tostring(any_pinned);
    for _, part in ipairs(entry.parts) do
        keys[#keys + 1] = tostring((display.groups or {})[part.id]);
        keys[#keys + 1] = tostring((display.priorities or {})[part.id]);
        keys[#keys + 1] = tostring((display.pinned or {})[part.id]);
    end
    local key = table.concat(keys, '\1');
    if entry.arrangement_key ~= key then
        local hidden;
        entry.segments, entry.overflow, hidden = layout.arrange(entry.parts, width, measure, display);
        local omitted = {}; for _, id in ipairs(hidden) do omitted[id] = true; end
        entry.hidden = {};
        for _, item in ipairs(entry.items) do if omitted[item.id] then entry.hidden[#entry.hidden + 1] = item; end end
        entry.arrangement_key = key;
    end
    return entry;
end

local function content_width(settings, view, height, sample)
    if not settings.display.show_text then return settings.bar.width; end
    local size = text_size(settings, height);
    local pushed = fonts.push(settings.style.font, size);
    local measure, font_key = measurer(settings, size);
    local entry = parts_for(settings, view, height, sample);
    if entry.width_font ~= font_key then
        local width = 18;
        for _, part in ipairs(entry.parts) do width = width + measure(part.text) + (part.gap or 0) + (part.icon_width or 0) + (part.icon_gap or 0); end
        entry.width, entry.width_font = math.ceil(width), font_key;
    end
    fonts.pop(pushed);
    return entry.width;
end

function hud.bounds(settings, view, context)
    local display = imgui.GetIO().DisplaySize;
    local mode = settings.visibility.mode;
    local keep_visible = mode == 'keep' or mode == 'always';
    local desired;
    if (not settings.bar.docked or keep_visible and not (context and context.chat)) and settings.bar.auto_width then
        desired = content_width(settings, view, math.min(settings.bar.height, display.y), context and context.preview);
    end
    return layout.rect(settings.bar, display.x, display.y, context and context.chat, desired, keep_visible);
end

function hud.place(settings, view, context, mode)
    if mode ~= 'free' and mode ~= 'top' and mode ~= 'bottom' then return false; end
    gesture = nil;
    if mode == 'free' then
        layout.detach(settings.bar, hud.bounds(settings, view, context));
        settings.bar.docked, settings.bar.snap, settings.bar.auto_width, settings.bar.locked = false, false, false, false;
    else
        settings.bar.docked, settings.bar.snap, settings.bar.anchor = true, true, mode;
    end
    return true;
end

local function paint(settings, view, rect, sample, mouse_x, mouse_y)
    local style, colors = settings.style, settings.style.colors;
    local list = imgui.GetWindowDrawList();
    local corner = math.min(style.rounding, rect.height / 2);
    local a, b = { rect.x, rect.y }, { rect.x + rect.width, rect.y + rect.height };
    list:AddRectFilled(a, b, theme.u32(colors.background, style.opacity), corner);
    local rail = style.fill_style == 'rail';
    if settings.display.show_fill then
        local inset = rail and math.min(math.max(6, corner), rect.width / 2) or 0;
        local track_x, track_width = rect.x + inset, math.max(0, rect.width - inset * 2);
        local track_y, track_height = rect.y + (rail and math.max(0, rect.height - 3) or 0), rail and math.min(2, rect.height) or rect.height;
        if rail then
            list:AddRectFilled({ track_x, track_y }, { track_x + track_width, track_y + track_height }, theme.u32(colors.divider, 0.5), 1);
        end
        local percent, merit_fill = view.valid and view.percent, view.mode == 'lp';
        local dyna = view.dynamis;
        if settings.dynamis and settings.dynamis.layout_active and dyna and dyna.active then
            local duration = dyna.end_time and dyna.start_time and dyna.end_time - dyna.start_time;
            percent = duration and duration > 0 and dyna.remaining and dyna.remaining / duration or nil;
            merit_fill = false;
        end
        if percent then
            local fraction = layout.clamp(percent, 0, 1);
            local left = style.fill_direction == 'left' and track_x + track_width * (1 - fraction) or track_x;
            local right = style.fill_direction == 'left' and track_x + track_width or track_x + track_width * fraction;
            if right > left then
                list:AddRectFilled({ left, track_y }, { right, track_y + track_height },
                    theme.u32(merit_fill and colors.lp_fill or colors.fill, rail and 1 or 0.25), math.min(rail and 1 or corner, (right - left) / 2));
            end
        end
    end
    if style.border then list:AddRect(a, b, theme.u32(colors.border), corner, 0, 1); end
    local info = { overflow = false, hidden_count = 0, hidden_readouts = {}, bar_width = rect.width };
    if not settings.display.show_text and not view.notice then return false, mouse_x and 'progress' or nil, info; end
    local font_size = text_size(settings, rect.height);
    local pushed = fonts.push(style.font, font_size);
    local measure, font_key = measurer(settings, font_size);
    local entry = settings.display.show_text and arranged(settings, view, rect.height, sample, math.max(0, rect.width - 18), measure, font_key) or nil;
    local segments, overflow = entry and entry.segments or {}, entry and entry.overflow or false;
    info.overflow, info.hidden_readouts = overflow, entry and entry.hidden or {};
    info.hidden_count = #info.hidden_readouts;
    local content_height = rect.height - (rail and settings.display.show_fill and 3 or 0);
    local x, y = rect.x + 9, rect.y + math.floor((content_height - font_size) / 2);
    local notice = view.notice and type(view.notice.text) == 'string' and not sample;
    if notice then
        list:AddRect({ rect.x + 1, rect.y + 1 }, { rect.x + rect.width - 1, rect.y + rect.height - 1 }, theme.u32(colors.warning), math.max(0, corner - 1), 0, 1);
    end
    local chain_left, chain_right;
    local hovered = not settings.display.show_text and mouse_x and 'progress' or nil;
    local chain_ending = view.valid and (view.chain_source == 'local' or view.chain_source == 'server') and view.chain_active ~= false
        and type(view.chain_left) == 'number' and view.chain_left > 0 and view.chain_left < 10;
    list:PushClipRect({ rect.x + 2, rect.y + 1 }, { rect.x + rect.width - 2, rect.y + rect.height - 1 }, true);
    for _, segment in ipairs(segments) do
        x = rect.x + 9 + (segment.offset or 0) + (segment.gap or 0);
        local segment_left = x;
        if segment.id == 'chain' and segment.role ~= 'divider' then chain_left = chain_left or x; end
        if segment.icon then
            local icon_y = rect.y + math.max(1, math.floor((content_height - segment.icon_width) / 2));
            list:AddImage(segment.icon, { x, icon_y }, { x + segment.icon_width, icon_y + segment.icon_width });
            x = x + segment.icon_width + segment.icon_gap;
        end
        local color = segment.role ~= 'label' and segment.role ~= 'divider' and settings.display.colors[segment.id] or nil;
        color = color or colors[segment.role] or colors.text;
        if chain_ending and segment.id == 'chain_time' and segment.role == 'chain' then color = colors.chain_ending; end
        local function text(value, tint)
            if style.text_shadow then list:AddText(imgui.GetFont(), font_size, { x + 1, y + 1 }, imgui.col32(220, 0, 0, 0), value); end
            list:AddText(imgui.GetFont(), font_size, { x, y }, theme.u32(tint), value);
            x = x + measure(value);
        end
        local start = x;
        if segment.id == 'chain' and segment.role == 'chain' then
            local value, bonus = segment.text:match('^(%d+)( .+)$');
            if value then text(value, color); text(bonus, colors.label); else text(segment.text, color); end
        else
            text(segment.text, color);
        end
        x = start + measure(segment.text);
        if mouse_x and segment.role ~= 'divider' and mouse_x >= math.max(rect.x + 2, segment_left)
            and mouse_x < math.min(rect.x + rect.width - 2, x)
            and mouse_y >= rect.y + 1 and mouse_y < rect.y + content_height then hovered = segment.id; end
        if segment.id == 'chain' and segment.role ~= 'divider' then chain_right = x; end
    end
    if settings.display.chain_strip and view.valid and chain_left and chain_right
        and (view.chain_source == 'server' or view.chain_source == 'local') and view.chain_active ~= false
        and type(view.chain_left) == 'number' and view.chain_left >= 0 and view.chain_left < math.huge
        and type(view.chain_window) == 'number' and view.chain_window > 0 and view.chain_window < math.huge then
        local fraction = layout.clamp(view.chain_left / view.chain_window, 0, 1);
        if fraction > 0 then
            list:AddRectFilled({ chain_left, rect.y + 1 }, { chain_left + (chain_right - chain_left) * fraction, rect.y + 2 },
                theme.u32(colors.chain, view.chain_source == 'local' and 0.45 or 0.8), 0.5);
        end
    end
    if notice then
        local size = math.min(8, font_size);
        list:AddText(imgui.GetFont(), size, { rect.x + 2, rect.y + math.floor((content_height - size) / 2) }, theme.u32(colors.warning), '!');
        if mouse_x and mouse_x >= rect.x + 1 and mouse_x < rect.x + 8 and mouse_y >= rect.y and mouse_y < rect.y + rect.height then hovered = 'notice'; end
    end
    list:PopClipRect();
    fonts.pop(pushed);
    return overflow, hovered, info;
end

local function tooltip(settings, view, id, info)
    if id == 'overflow' then
        info = info or last_render[settings];
        local lines = {};
        for _, item in ipairs(info and info.hidden_readouts or {}) do
            local definition = readouts.definition(item.id);
            local label = item.label ~= '' and item.label or definition and definition.name or item.id;
            lines[#lines + 1] = label .. ': ' .. item.value;
        end
        return 'More readings', table.concat(lines, '\n'), 'These readings do not fit on the bar. Make the bar wider or choose fewer readings in Display.';
    elseif id == 'notice' then
        return 'Alert', view.notice and view.notice.text or '', 'This alert appears briefly on the bar. Choose which alerts to show or play a sound for in Alerts.';
    elseif id == 'sample' then
        return 'Preview', 'Example values', 'These example values let you try the layout before using it for your session.';
    elseif id == 'paused' then
        return 'Session paused', 'Paused', 'EXP chain, food, Dedication, and EXP ring recast timers keep running. Dynamis time and drops keep tracking too. Choose Resume session to count EXP, LP, and session time again.';
    end
    local definition = readouts.definition(id);
    if not definition then return nil; end
    local value = '--';
    for _, item in ipairs(readouts.cached(settings, view)) do
        if item.id == id then value = item.value; break; end
    end
    if id == 'progress' and not settings.display.show_text and view.valid then
        value = readouts.format_number(view.current, settings.display.short) .. ' / ' .. readouts.format_number(view.needed, settings.display.short);
    end
    local title, help = definition.name, definition.help;
    if not view.valid and id:sub(1, 5) ~= 'dyna_' then return title, value, 'Waiting for your character information. -- means this amount is not known yet.'; end
    if id == 'rate' or id == 'exp_rate' or id == 'lp_rate' or id == 'merit_rate' then
        local unit = id == 'exp_rate' and 'EXP' or (id == 'lp_rate' or id == 'merit_rate') and 'LP' or view.mode == 'lp' and 'LP' or 'EXP';
        title = id == 'merit_rate' and 'Merit points per hour' or unit .. '/HR';
        help = settings.tracking.rate_basis == 'net'
            and 'EXP/LP kept counts the points you kept. EXP lost on death, recovered from Raise, and other EXP changes affect this rate.'
            or 'EXP/LP received counts the EXP or LP awarded by the game. EXP recovered from Raise does not count. Points lost because you were capped still count.';
        help = help .. ' Any Level Sync penalty is already included. Do not subtract it again.';
        if id == 'merit_rate' then help = help .. ' Every 10,000 LP is worth one merit point.'; end
        help = help .. (settings.tracking.window == 0 and ' This uses the whole session.'
            or ' This uses the last ' .. readouts.format_time(settings.tracking.window) .. ' of session time. Paused time does not count.');
        help = help .. ' Change EXP/HR time period or Rate calculation in Tracking.';
        if view.collecting then help = help .. ' The rate appears after 60 seconds of session time.'; end
        if view.paused then help = help .. ' This session is paused.'; end
    elseif id == 'remaining' then
        title = view.mode == 'lp' and 'LP to next merit point' or (view.level or 0) >= 75 and 'EXP buffer remaining' or 'EXP to next level (TNL)';
        help = view.mode == 'lp' and (view.lp and view.lp.blocked and 'Your stored merit points are full. Spend at least one to earn another merit point.'
            or 'This is the LP needed for your next merit point. Every 10,000 LP earns one merit point when you have room for it.')
            or (view.level or 0) >= 75 and 'This is the EXP needed to fill your level 75 EXP buffer. Level 75 is the cap, so it does not lead to another level.'
            or 'This is the EXP needed for your next job level. Level Sync does not change how much EXP you need.';
        if view.capped then help = help .. ' Your EXP or LP bar is full.'; end
    elseif id == 'sync' then
        if view.sync_active == false then
            help = 'Level Sync is off. You have no Level Sync penalty.';
        elseif view.sync_active then
            help = 'Your normal job level is ' .. readouts.format_number(view.level) .. '. Your synced level is '
                .. readouts.format_number(view.sync_level or view.effective_level) .. '.';
            if view.sync_source == 'server' and type(view.sync_penalty) == 'number' then
                help = help .. ' Phoenix reports a Level Sync EXP penalty of ' .. readouts.format_number(view.sync_penalty) .. '%.';
                help = help .. ' Your other EXP bonuses also affect the final amount you receive.';
            else
                help = help .. ' Phoenix has not sent your current Level Sync penalty. The level difference alone is not enough to work it out.';
            end
            help = help .. ' EXP/HR already includes any penalty. Do not subtract it again. Open Details to check Level Sync or try a different sync level.';
        else
            help = 'Momentum does not know whether Level Sync is active yet. This will update when your character information is available.';
        end
    elseif id == 'chain_time' then
        if view.chain_source == 'server' and view.chain_active == false then
            help = 'No EXP chain is active. Phoenix will send a new end time when a qualifying reward starts one.';
        elseif view.chain_source == 'server' and type(view.chain_left) == 'number' and view.chain_left >= 0 and view.chain_left < math.huge then
            help = 'This is the time left for your next qualifying EXP chain kill, using the end time sent by Phoenix. A connection delay can affect the displayed time slightly.';
        elseif view.chain_source == 'local' then
            if type(view.chain_left) == 'number' and view.chain_left >= 0 and view.chain_left < math.huge then
                title = 'EXP chain timer (estimated)';
                help = 'This timer uses Phoenix EXP chain rules. ~ means it is estimated. When the defeated monster\'s level is unknown, Momentum uses the shortest possible time, so the chain may last longer. Your next kill must qualify for an EXP chain. The timer starts when the reward arrives, so a connection delay can affect it slightly.';
            else
                title = 'Estimated EXP chain timer ended';
                help = 'The estimated timer has ended, but the EXP chain may still be active. When the defeated monster\'s level is unknown, Momentum uses the shortest possible time. Another EXP chain reward starts a new timer.';
            end
        else
            help = 'Momentum is waiting for an EXP chain reward. It then starts an estimated timer using Phoenix EXP chain rules.';
        end
    elseif id == 'no_exp' then
        if view.no_exp_reason == 'distance' then help = 'Phoenix reported that you were too far from the defeated monster to receive EXP.';
        elseif view.no_exp_reason == 'sync_target' then help = 'Phoenix reported that your Level Sync target was unavailable for this EXP reward. The target may have been KO\'d or too far from the defeated monster.';
        else help = 'Phoenix has not sent a recent reason for missing EXP. A missing reward alone cannot tell Momentum what happened.'; end
    elseif id == 'dedication_budget' then
        help = type(view.dedication_pool) == 'number' and 'This is the bonus EXP left from Dedication, as sent by Phoenix. After an EXP reward, it may briefly show -- until Phoenix sends a new amount.'
            or 'Phoenix has not sent the current bonus EXP left from Dedication. The effect icon and timer cannot tell Momentum how much is left.';
    elseif id == 'food' then
        help = definition.help;
        if view.food and not view.food_name then help = help .. ' Your food effect is active, but Momentum did not see which food you used.'; end
        if view.food and not view.food_seconds then help = help .. ' The game has not provided the time left for this food effect.'; end
    elseif id == 'goal' and view.goal then
        help = (view.goal.label or 'Current goal') .. '. ' .. (view.goal.reason or definition.help);
    elseif id == 'elapsed' then
        help = 'This counts time while the session is running. Pauses and time while Momentum was unloaded do not count. You can continue a saved session after reloading.';
    elseif id == 'status' and view.collecting then
        help = 'EXP/HR and LP/HR appear after 60 seconds of session time. Paused time does not count.';
    end
    return title, value, help;
end

local function draw_tooltip(settings, view, id, context, info)
    if not id then hover_id, hover_since = nil, nil; return; end
    local now = context.now or os.clock();
    if id ~= hover_id then
        hover_id, hover_since, hover_updated = id, now, nil;
    end
    if now - hover_since < 0.25 then return; end
    if not hover_updated or now - hover_updated >= 0.2 then
        hover_title, hover_value, hover_help = tooltip(settings, view, id, info);
        hover_updated = now;
    end
    if not hover_title then return; end
    local colors = settings.style.window_colors;
    imgui.PushStyleColor(ImGuiCol_PopupBg, colors.card);
    imgui.PushStyleColor(ImGuiCol_Text, colors.text);
    imgui.PushStyleColor(ImGuiCol_Border, colors.border);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 12, 10 });
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, 5);
    local pushed = fonts.push(settings.style.font, settings.window.font_size);
    if imgui.BeginTooltip() then
        imgui.PushTextWrapPos(math.max(120, math.min(440, imgui.GetIO().DisplaySize.x - 32)));
        imgui.TextColored(colors.heading, hover_title);
        imgui.TextUnformatted(hover_value);
        imgui.Separator();
        imgui.TextUnformatted(hover_help);
        if context.preview then imgui.TextColored(colors.muted, 'Sample preview'); end
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end
    fonts.pop(pushed);
    imgui.PopStyleVar(2);
    imgui.PopStyleColor(3);
end

function hud.draw_inline(settings, view, width, height, context)
    context = context or {};
    local sample_width = context.preview and tonumber(context.width);
    if context.chat == nil and not context.chat_checked then
        local previous = last_context[settings] or {};
        context = { chat = previous.chat, now = context.now or previous.now, preview = context.preview };
    end
    local actual = hud.bounds(settings, view, context);
    local simulated_width = false;
    if sample_width and sample_width > 0 and sample_width < math.huge then
        actual = { width = math.min(sample_width, imgui.GetIO().DisplaySize.x), height = actual.height or settings.bar.height };
        simulated_width = true;
    end
    local x, y = imgui.GetCursorScreenPos();
    local shown_width = math.max(1, math.min(width, actual.width or settings.bar.width));
    height = height or actual.height or settings.bar.height;
    local info;
    if actual.hidden then
        info = { overflow = false, hidden_count = 0, hidden_readouts = {}, unavailable = true, reason = actual.reason };
        imgui.GetWindowDrawList():AddRectFilled({ x, y }, { x + shown_width, y + height }, theme.u32(settings.style.colors.background, settings.style.opacity), math.min(settings.style.rounding, height / 2));
    else
        local rect = { x = x, y = y, width = actual.width, height = height };
        local list = imgui.GetWindowDrawList();
        list:PushClipRect({ x, y }, { x + shown_width, y + height }, true);
        local ignored, hovered;
        ignored, hovered, info = paint(settings, view, rect, context.preview);
        list:PopClipRect();
    end
    info.bar_width, info.preview_width = actual.width, shown_width;
    info.preview_clipped = actual.width ~= nil and shown_width < actual.width;
    info.simulated_width = simulated_width;
    imgui.Dummy({ shown_width, height });
    return info;
end

local function controls(settings, rect, width, height, chat)
    imgui.SetCursorScreenPos({ rect.x, rect.y });
    imgui.InvisibleButton('##momentum_drag', { rect.width, rect.height });
    local mx, my = imgui.GetMousePos();
    local edge_x = mx >= rect.x + rect.width - 7;
    local top_edge = rect.anchor == 'top';
    local edge_y = top_edge and my < rect.y + 6 or not top_edge and my >= rect.y + rect.height - 6;
    if imgui.IsItemActivated() then
        gesture = { x = mx, y = my, rect = rect, width = edge_x, height = edge_y, docked = settings.bar.docked, dirty = false,
            auto_width = settings.bar.auto_width, top_edge = top_edge, anchor = rect.anchor,
            saved_width = settings.bar.width, screen_width = width, screen_height = height };
    end
    if gesture and imgui.IsItemActive() then
        local dx, dy = mx - gesture.x, my - gesture.y;
        if gesture.dirty or dx ~= 0 or dy ~= 0 then
            if settings.bar.docked and not gesture.rect.anchor then layout.detach(settings.bar, gesture.rect); end
            if gesture.width or gesture.height then
                local next_width = gesture.width and gesture.rect.width + dx or gesture.rect.width;
                local next_height = gesture.height and gesture.rect.height + dy * (gesture.top_edge and -1 or 1) or gesture.rect.height;
                if gesture.width then
                    if settings.bar.docked then layout.detach(settings.bar, gesture.rect); end
                    settings.bar.auto_width = false;
                end
                layout.resize(settings.bar, next_width, next_height, width, height);
                if gesture.height and gesture.top_edge and not settings.bar.docked then
                    settings.bar.y = layout.clamp(gesture.rect.y + gesture.rect.height - settings.bar.height, 0, height - settings.bar.height);
                end
                if not gesture.width then
                    settings.bar.auto_width, settings.bar.width = gesture.auto_width, gesture.saved_width;
                end
            else
                if settings.bar.docked then layout.detach(settings.bar, gesture.rect); end
                layout.move(settings.bar, gesture.rect.x + dx, gesture.rect.y + dy, width, height, false, gesture.rect.width, chat);
            end
            gesture.anchor = settings.bar.docked and rect.anchor or nil;
            gesture.dirty = true;
        end
    end
    if imgui.IsItemHovered() or imgui.IsItemActive() then
        local resize_x, resize_y, resize_top = edge_x, edge_y, top_edge;
        if gesture then resize_x, resize_y, resize_top = gesture.width, gesture.height, gesture.top_edge; end
        local diagonal = resize_top and ImGuiMouseCursor_ResizeNESW or ImGuiMouseCursor_ResizeNWSE;
        local cursor = resize_x and resize_y and diagonal or resize_x and ImGuiMouseCursor_ResizeEW
            or resize_y and ImGuiMouseCursor_ResizeNS or ImGuiMouseCursor_ResizeAll;
        if cursor then imgui.SetMouseCursor(cursor); end
        imgui.GetWindowDrawList():AddRect({ rect.x, rect.y }, { rect.x + rect.width, rect.y + rect.height }, theme.u32(settings.style.colors.chain), settings.style.rounding, 0, 1);
    end
end

function hud.cancel_layout_gesture()
    gesture = nil;
    hover_id, hover_since = nil, nil;
end

function hud.draw(settings, view, context)
    context = context or {};
    last_context[settings] = { chat = context.chat, now = context.now, preview = context.preview };
    local display = imgui.GetIO().DisplaySize;
    local width, height = display.x, display.y;
    if width <= 0 or height <= 0 then return false; end
    local changed = false;
    local movable = context.shift and not context.typing and not settings.bar.locked;
    local mouse_down = imgui.IsMouseDown(ImGuiMouseButton_Left);
    if gesture and (not mouse_down or not movable or width ~= gesture.screen_width or height ~= gesture.screen_height) then
        if not mouse_down and gesture.dirty and not gesture.width and not gesture.height then
            layout.move(settings.bar, settings.bar.x, settings.bar.y, width, height, true, gesture.rect.width, context.chat);
        end
        changed = gesture.dirty;
        gesture = nil;
    end
    local rect = hud.bounds(settings, view, context);
    if gesture and (rect.hidden or rect.anchor ~= gesture.anchor) then
        changed = gesture.dirty or changed;
        gesture = nil;
    end
    if rect.hidden then hover_id, hover_since = nil, nil; return changed; end
    local mx, my = imgui.GetMousePos();
    local hovering = settings.display.hover and not context.shift and not context.typing and not gesture and inside(rect, mx, my)
        and not imgui.IsAnyMouseDown() and not imgui.IsWindowHovered(hover_flags);
    local hovered, info;
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav);
    if not movable then flags = bit.bor(flags, ImGuiWindowFlags_NoInputs); end
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, { 1, 1 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.SetNextWindowPos({ rect.x, rect.y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ rect.width, rect.height }, ImGuiCond_Always);
    if imgui.Begin('##momentum_bar', true, flags) then
        local overflow;
        overflow, hovered, info = paint(settings, view, rect, context.preview, hovering and mx or nil, my);
        last_render[settings] = info;
        if movable then controls(settings, rect, width, height, context.chat); end
    end
    imgui.End();
    imgui.PopStyleVar(3);
    draw_tooltip(settings, view, hovered, context, info);
    return changed;
end

if MOMENTUM_TEST_MODE then hud._tooltip = tooltip; end

return hud;
