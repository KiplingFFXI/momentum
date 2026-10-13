local imgui = require('imgui');
local bit = require('bit');
local defaults = require('ui.defaults');
local layout = require('ui.layout');
local readouts = require('ui.readouts');
local theme = require('ui.theme');
local fonts = require('ui.fonts');
local hud = require('ui.hud');
local details = require('ui.details');
local dynamis = require('ui.dynamis');
local settings_window = {};
local selected = 'progress';
local scroll_selected = false;
local query = { '' };
local readout_filter = { '' };
local shown_only = true;
local catalog_filter = { '' };
local sample_preview = false;
local focus_on_open = false;
local minimum_window_height = 300;
local search_matches = {};
local search_target;
local search_scroll;
local search_focus = false;
local profile_name = { '' };
local profile_selected;
local profile_job = 1;
local status;
local pending = false;
local reset_layout = false;
local section_settings;
local profile_confirmation;
local window_colors;
local dragged, drag_target;
local readout_sizes = {};
local section_labels = {};
local help_marker;
local pages = { 'Display', 'Tracking', 'Dynamis', 'Details', 'Alerts', 'Appearance', 'Session', 'Profiles' };
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
local page_section = { Display = 'display', Tracking = 'tracking', Dynamis = 'dynamis', Details = 'planner', Alerts = 'alerts', Appearance = 'style', Session = 'sessions', Profiles = 'profiles' };
local section_names = {
    ['Level sync'] = 'Level Sync', ['Advanced sync estimate'] = 'Level Sync estimate',
    ['Recent rewards'] = 'Recent EXP and LP', ['Owned EXP rings'] = 'EXP rings',
    ['Quiet conditions'] = 'When to mute alerts', ['EXP and merits'] = 'EXP and merit points',
    ['Job links'] = 'Job profiles', ['Session storage'] = 'Saved session options',
};

local tips = {
    ['Placement'] = 'Attach the bar above or below your chat log. Choose Free placement to move it anywhere. Hold Shift to drag the bar or resize its edges.',
    ['Bar height'] = 'Set the bar height from 12 to 120 pixels. When attached to chat, it stays outside the border and fits the space available.',
    ['Starting point'] = 'Move the left end of the bar along your chat log by this many pixels. Zero lines it up with the left edge. The right end stays lined up with chat.',
    ['Gap from chat'] = 'Set the space between the bar and your chat log.',
    ['Maximum width'] = 'Let the bar grow up to this width. Hover over ... to see any readings that do not fit.',
    ['Custom bar width'] = 'Set the width in pixels, or Shift-drag the right edge of the bar.',
    ['Horizontal position'] = 'Set how far the bar sits from the left edge of your game window.',
    ['Vertical position'] = 'Set how far the bar sits from the top of your game window.',
    ['Starter layout'] = 'Choose a starting layout. This changes which readouts appear and their order. Your other settings stay the same.',
    ['Readout group'] = 'Put this readout on the left, in the center, or on the right. Readouts in the same group follow your list order.',
    ['Display priority'] = 'Give important readouts a higher number so they stay visible when space is short. Keep visible first takes priority over this number.',
    ['Show when'] = 'Choose when this readout appears. It must also have Show checked in the list. Always shows it even when the value is unknown.',
    ['Divider style'] = 'Choose a divider, then check Divider beside each readout that needs one. The first readout in each group has no divider. You can enter your own divider under Dividers and formatting.',
    ['Label separator'] = 'Choose what goes between a label and its number, such as a space or colon.',
    ['Extra space between readouts'] = 'Add space between the readouts on your bar.',
    ['Show EXP or LP'] = 'Automatic follows your EXP or merit point mode. Choose EXP or Limit points to keep that progress on the bar. This does not change your mode in the game. You earn one merit point for every 10,000 LP when your merit points are not full.',
    ['EXP/HR time period'] = 'Calculate EXP/HR and LP/HR over the last 5, 15, or 30 minutes, or your whole session. Paused time does not count.',
    ['Rate calculation'] = 'EXP/LP received counts the amounts shown by the game, including points lost at the cap. EXP/LP kept counts changes to your EXP or LP, including EXP lost on death and recovered through Raise.',
    ['Recent gains to average'] = 'Choose how many recent EXP or LP gains to compare. This sets the average, lowest, highest, and middle gain. It does not change EXP/HR or LP/HR.',
    ['Goal type'] = 'Choose a level, EXP, or merit point goal. Momentum estimates how long it will take from your current EXP/HR or LP/HR.',
    ['Merit points to save'] = 'Set how many unspent merit points you want to save. Your current LP counts toward the next point. The goal cannot go above your merit point cap. Use a session goal to count points you earn and spend along the way.',
    ['Target level'] = 'Choose the level you want to reach, up to level 75. The estimate includes the EXP needed for every level along the way.',
    ['Session EXP target'] = 'Set how much EXP you want to earn this session.',
    ['Merit points to earn'] = 'Set how many merit points you want to earn this session. Spending them does not reduce your count. LP you already had counts toward the next merit point.',
    ['Target EXP buffer'] = 'Set the EXP buffer you want to keep at your current level.',
    ['Skin'] = 'Choose a color theme. Your readouts, labels, order, and position stay the same.',
    ['Font'] = 'Choose the font for the bar and settings window.',
    ['Bar text size'] = 'Set the size of the text on your bar. Increase Bar height if it needs more room.',
    ['Settings text size'] = 'Set the text size in settings. Bar text keeps its own size.',
    ['Bar background opacity'] = 'Set how solid the bar background looks. Lower values let more of the game show through.',
    ['Corner roundness'] = 'Round the ends of the bar, or use zero for square corners.',
    ['Progress style'] = 'Show your EXP or LP as a thin line or a fill behind the text.',
    ['Fill direction'] = 'Choose which way the EXP or LP bar fills. This does not change the readout order.',
    ['Sample state'] = 'Try sample EXP, LP, or Dynamis readings in the preview. Your session keeps tracking normally.',
    ['Sound'] = 'Choose a sound from the list. To add your own .mp3 or .wav, put it in config/addons/momentum/sounds and press Refresh.',
    ['Sound volume'] = '0 is silent. 100 is full volume.',
    ['Profile'] = 'Choose a saved layout, then press Load profile to use it or Delete profile to remove it.',
    ['Job'] = 'Choose the main job you want to set a profile for.',
    ['Load this profile on job change'] = 'Use this profile when you change to the selected main job. Choose (none) to stop loading a profile for that job.',
};

local function note(text)
    imgui.PushTextWrapPos(0);
    imgui.TextUnformatted(text);
    imgui.PopTextWrapPos();
end

local function tip(text)
    if text and imgui.IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled or 0) then
        imgui.BeginTooltip();
        imgui.PushTextWrapPos(math.min(390, math.max(180, imgui.GetIO().DisplaySize.x - 32)));
        imgui.TextUnformatted(text);
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end
end

local function beside(width)
    local right = imgui.GetItemRectMax();
    local left = imgui.GetWindowPos();
    local window_width = imgui.GetWindowSize();
    if right + width + 8 <= left + window_width - 24 then imgui.SameLine(); end
end

local function help(text)
    if not text then return; end
    local font, size = imgui.GetFont(), imgui.GetFontSize();
    if not help_marker or help_marker.font ~= font or help_marker.size ~= size then
        help_marker = { font = font, size = size, width = imgui.CalcTextSize('(?)') };
    end
    beside(help_marker.width);
    imgui.TextDisabled('(?)');
    tip(text);
end

local function heading(text, explanation)
    imgui.Spacing();
    imgui.TextColored(window_colors.heading, text);
    if section_settings and search_scroll == section_settings.window.tab .. '/' .. text then
        imgui.SetScrollHereY(0); search_scroll = nil;
        if search_focus then imgui.SetKeyboardFocusHere(); search_focus = false; end
    end
    help(explanation);
    imgui.Separator();
end

local function section(title, explanation, default_open, summary)
    local settings = section_settings;
    local key = settings.window.tab .. '/' .. title;
    local saved = settings.window.sections[key];
    if saved == nil then saved = default_open ~= false; end
    local searching = query[1]:match('%S') ~= nil;
    local matched = search_matches[key] == true or title == 'Selected readout' and search_matches[settings.window.tab .. '/More options'] == true;
    imgui.SetNextItemOpen(searching and matched or not searching and saved, ImGuiCond_Always);
    imgui.Spacing();
    local label = section_names[title] or title;
    local suffix = (summary and ' (' .. summary .. ')' or '') .. (explanation and ' (?)' or '');
    local clipped = false;
    if summary then
        local available = math.max(0, (imgui.GetContentRegionAvail()) - imgui.GetFrameHeight() - 12);
        local font, size = imgui.GetFont(), imgui.GetFontSize();
        local cached = section_labels[key];
        if cached and cached.title == label and cached.suffix == suffix and cached.width == available
            and cached.font == font and cached.size == size then
            label, clipped = cached.label, cached.clipped;
        else
            local title = label;
            if imgui.CalcTextSize(label .. suffix) > available then
                repeat label = label:sub(1, -2); until #label == 0 or imgui.CalcTextSize(label .. '...' .. suffix) <= available;
                label, clipped = label .. '...', true;
            end
            section_labels[key] = { title = title, suffix = suffix, width = available, font = font, size = size,
                label = label, clipped = clipped };
        end
    end
    imgui.PushStyleColor(ImGuiCol_Text, window_colors.heading);
    local shown = imgui.CollapsingHeader(label .. suffix .. (summary and '###section_' or '##section_') .. key);
    imgui.PopStyleColor();
    tip(clipped and title .. '. ' .. (explanation or '') or explanation);
    if search_scroll == key then
        imgui.SetScrollHereY(0); search_scroll = nil;
        if search_focus then imgui.SetKeyboardFocusHere(); search_focus = false; end
    end
    if not searching and shown ~= saved then settings.window.sections[key] = shown; pending = true; end
    return shown;
end

local function checkbox(table_, key, title, explanation)
    local value = { table_[key] == true };
    local wrap = imgui.CalcTextSize(title) + imgui.GetFrameHeight() + 8 > imgui.GetContentRegionAvail();
    if imgui.Checkbox(wrap and '##' .. title or title, value) then table_[key] = value[1]; pending = true; end
    tip(explanation);
    if wrap then imgui.SameLine(); note(title); tip(explanation); end
    help(explanation);
end

local function slider(table_, key, title, low, high, format, explanation)
    imgui.TextUnformatted(title);
    help(explanation or tips[title]);
    imgui.SetNextItemWidth(math.min(400, (imgui.GetContentRegionAvail())));
    local value = { table_[key] };
    if imgui.SliderFloat('##' .. title, value, low, high, format or '%.0f') then table_[key] = value[1]; pending = true; end
    tip(explanation or tips[title]);
end

local function input(table_, key, title, maximum, explanation)
    imgui.TextUnformatted((title:gsub('##.*', '')));
    help(explanation or tips[title]);
    imgui.SetNextItemWidth(math.min(400, (imgui.GetContentRegionAvail())));
    local value = { table_[key] or '' };
    if imgui.InputText('##' .. title, value, (maximum or 32) + 1) then
        table_[key] = value[1]:gsub('[^ -~]', '');
        pending = true;
    end
    tip(explanation or tips[title]);
end

local function combo(title, current, choices, apply, width, explanation)
    imgui.TextUnformatted(title);
    help(explanation or tips[title]);
    imgui.SetNextItemWidth(math.min(width or 320, (imgui.GetContentRegionAvail())));
    if imgui.BeginCombo('##' .. title, tostring(current or '--')) then
        for _, option in ipairs(choices) do
            local name = type(option) == 'table' and option.name or option;
            local value = type(option) == 'table' and option.value or option;
            local visible = name:match('^(.-)##') or name;
            if imgui.Selectable(name, current == visible or current == value) then apply(value); end
        end
        imgui.EndCombo();
    end
    tip(explanation or tips[title]);
end

local function pick(table_, key, title, choices, help)
    local current = table_[key];
    for _, option in ipairs(choices) do
        if type(option) == 'table' and option.value == current then current = option.name; break; end
    end
    combo(title, current, choices, function(value) table_[key] = value; pending = true; end, nil, help);
    tip(help);
end

local function button_row(buttons)
    local available = imgui.GetContentRegionAvail();
    local used = 0;
    for _, entry in ipairs(buttons) do
        local width = imgui.CalcTextSize(entry[1]:gsub('##.*', '')) + 20;
        if used > 0 and used + width + 8 <= available then imgui.SameLine(); elseif used > 0 then used = 0; end
        if entry[4] then imgui.PushStyleColor(ImGuiCol_Button, entry[4]); end
        if imgui.Button(entry[1]) then entry[2](); end
        if entry[4] then imgui.PopStyleColor(); end
        tip(entry[3]);
        used = used + width + 8;
    end
end

local function color(table_, key, title)
    local value = table_[key];
    if imgui.ColorEdit4(title, value, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar)) then pending = true; end
    help('Choose a color and transparency for ' .. title:lower() .. '. Applying a skin restores its colors.');
end

local controls = { note = note, tip = tip, help = help, section = section, heading = heading, checkbox = checkbox, slider = slider,
    input = input, combo = combo, pick = pick, buttons = button_row, changed = function() pending = true; end };

local function position(settings, services)
    if not section('Position and size', 'Attach the bar to your chat log, or move and resize it freely. Set where the readouts sit and whether labels go before or after their numbers.', false) then return; end
    local mode = not settings.bar.docked and 'Free placement' or settings.bar.anchor == 'top' and 'Above chat' or 'Below chat';
    combo('Placement', mode, { { name = 'Below chat', value = 'bottom' }, { name = 'Above chat', value = 'top' },
        { name = 'Free placement', value = 'free' } }, function(value)
        if services.placement then services.placement(value);
        else hud.place(settings, readouts.sample(settings.preview.scenario), nil, value); end
        pending = true;
    end);
    tip(tips.Placement);
    slider(settings.bar, 'height', 'Bar height', 12, 120, '%.0f px');
    tip('Choose a height from 12 to 120 pixels. When attached to chat, the bar fits the available space outside the chat border.');
    imgui.BeginDisabled(settings.display.groups_enabled);
    pick(settings.display, 'alignment', 'Readout alignment', { { name = 'Left', value = 'left' }, { name = 'Right', value = 'right' } },
        'Align the readouts to either end of the bar. Their chosen order stays left to right.');
    imgui.EndDisabled();
    if settings.display.groups_enabled then note('Alignment is set by each readout group.'); end
    pick(settings.display, 'label_position', 'Label position', {
        { name = 'Before value', value = 'before' }, { name = 'After value', value = 'after' } },
        'Before value shows EXP/HR 8,500. After value shows 8,500 EXP/HR. This applies to readout labels, including TNL and Chain.');
    checkbox(settings.bar, 'hide_typing', 'Hide while typing', 'Keeps the bar out of the way while you enter chat.');
    checkbox(settings.bar, 'locked', 'Lock movement and resizing', 'Keep the bar in place. Turn this off to move or resize it while holding Shift. Free placement unlocks it. You cannot move it while typing in chat.');
    checkbox(settings.bar, 'snap', 'Snap to chat when dropped nearby', 'When moving the bar, dropping it close to the top or bottom of chat attaches it there. Choosing Free placement turns this off so the bar stays where you drop it.');
    if not settings.bar.docked then note(settings.bar.locked and 'Locked. Turn off Lock movement and resizing to move the bar.' or 'Hold Shift and drag to move. Shift-drag the right edge to resize.'); end
    if settings.bar.docked then
        local chat_width = services.chat_width and services.chat_width() or imgui.GetIO().DisplaySize.x;
        slider(settings.bar, 'start', 'Starting point', 0, math.max(0, math.floor(chat_width) - 120));
        tip(tips['Starting point']);
        slider(settings.bar, 'bottom', 'Gap from chat', 2, 40);
        local problem = services.dock_problem and services.dock_problem();
        if problem then note(problem .. ' Choose Free placement to move the bar anywhere.'); end
    else
        checkbox(settings.bar, 'auto_width', 'Fit width to readouts', 'Uses only the space your readouts need, up to the maximum width below.');
        slider(settings.bar, 'width', settings.bar.auto_width and 'Maximum width' or 'Custom bar width', 120, 3840);
        slider(settings.bar, 'x', 'Horizontal position', 0, math.max(1, imgui.GetIO().DisplaySize.x));
        slider(settings.bar, 'y', 'Vertical position', 0, math.max(1, imgui.GetIO().DisplaySize.y));
    end
end

local function starter_name(settings)
    for _, name in ipairs({ 'Minimal', 'Leveling', 'Merits', 'Dynamis' }) do
        local chosen, matches, index = {}, true, 0;
        for _, id in ipairs(defaults.STARTER_LAYOUTS[name]) do chosen[id] = true; end
        for _, item in ipairs(defaults.READOUTS) do
            if settings.display.enabled[item.id] ~= (chosen[item.id] == true) then matches = false; break; end
        end
        if matches then
            for _, id in ipairs(settings.display.order) do
                if settings.display.enabled[id] then
                    index = index + 1;
                    if defaults.STARTER_LAYOUTS[name][index] ~= id then matches = false; break; end
                end
            end
        end
        if matches then return name; end
    end
    return 'Custom';
end

local function set_divider(settings, id, enabled)
    settings.display.dividers[id] = enabled;
    if enabled and not settings.display.divider:find('%S') then settings.display.divider = ' | '; end
    pending = true;
end

local catalog_groups = {
    { 'Progress', 'job progress remaining rate eta chain chain_time percent goal buffer status sync no_exp exp_progress exp_rate' },
    { 'Merit points and LP', 'merits merit_rate lp_progress lp_rate merits_session merit_headroom lp_remaining merit_eta' },
    { 'Session', 'last session net elapsed best_chain exp_session lp_session' },
    { 'Buffs', 'dedication food ring dedication_budget' },
    { 'Dynamis', 'dyna_zone dyna_time dyna_extensions dyna_currency dyna_af2 dyna_currency_received dyna_currency_rate dyna_af2_received dyna_bynes dyna_bronze dyna_shells dyna_bynes_received dyna_bronze_received dyna_shells_received dyna_kills dyna_objectives dyna_pool dyna_subjob dyna_weakness dyna_next_entry' },
    { 'Detailed statistics', 'average average3 average10 average_n sample_count minimum maximum median' },
};
local catalog_category = {};
for _, group in ipairs(catalog_groups) do
    for id in group[2]:gmatch('%S+') do catalog_category[id] = group[1]; end
end

local function add_readout(settings)
    local opening = imgui.Button('Add readout');
    local popup_x = imgui.GetItemRectMin();
    local _, popup_y = imgui.GetItemRectMax();
    if opening then
        catalog_filter[1] = '';
        imgui.OpenPopup('##readout_catalog');
    end
    tip('Choose another readout. Adding one keeps your existing order, labels, and colors.');
    local screen = imgui.GetIO().DisplaySize;
    local popup_width, popup_height = math.min(360, screen.x - 24), math.min(380, screen.y - 24);
    if opening then
        imgui.SetNextWindowPos({ layout.clamp(popup_x, 8, screen.x - popup_width - 8), layout.clamp(popup_y + 4, 8, screen.y - popup_height - 8) }, ImGuiCond_Appearing);
    end
    imgui.SetNextWindowSize({ popup_width, popup_height }, ImGuiCond_Always);
    imgui.SetNextWindowSizeConstraints({ popup_width, popup_height }, { popup_width, popup_height });
    if not imgui.BeginPopup('##readout_catalog') then return; end
    imgui.SetNextItemWidth(-1);
    imgui.InputTextWithHint('##Find readout to add', 'Find a readout', catalog_filter, 81);
    local term = catalog_filter[1]:lower():match('^%s*(.-)%s*$');
    local found = false;
    for _, group in ipairs(catalog_groups) do
        local heading_shown = false;
        for _, item in ipairs(defaults.READOUTS) do
            if (catalog_category[item.id] or 'Detailed statistics') == group[1]
                and (term == '' or (item.name .. ' ' .. item.help):lower():find(term, 1, true)) then
                if not heading_shown then imgui.Spacing(); imgui.TextDisabled(group[1]); imgui.Separator(); heading_shown = true; end
                found = true;
                local enabled = settings.display.enabled[item.id];
                imgui.BeginDisabled(enabled);
                if imgui.Selectable(item.name .. '##add_' .. item.id, enabled) and not enabled then
                    settings.display.enabled[item.id] = true;
                    selected, shown_only, scroll_selected = item.id, true, true;
                    readout_filter[1] = '';
                    settings.window.sections['Display/Selected readout'] = true;
                    pending = true;
                    imgui.CloseCurrentPopup();
                end
                imgui.EndDisabled();
                tip(enabled and 'Already chosen for the bar. ' .. item.help or item.help);
            end
        end
    end
    if not found then note('No matching readouts.'); end
    imgui.EndPopup();
end

local function filtered_readouts(settings)
    local rows = {};
    local term = readout_filter[1]:lower():match('^%s*(.-)%s*$');
    for i, id in ipairs(settings.display.order) do
        local definition = readouts.definition(id);
        if (not shown_only or settings.display.enabled[id])
            and (term == '' or (definition.name .. ' ' .. definition.help .. ' ' .. (settings.display.labels[id] or '')):lower():find(term, 1, true)) then
            rows[#rows + 1] = { id = id, index = i };
        end
    end
    return rows;
end

local function display_page(settings, services)
    if section('Readouts and order', 'Choose what the bar shows. Drag a :: handle to change the order, or select a row and use First, Up, Down, and Last.', true) then
        imgui.SetNextItemWidth(math.min(imgui.CalcTextSize('All readouts') + imgui.GetFrameHeight() + 16, (imgui.GetContentRegionAvail())));
        if imgui.BeginCombo('##Readout list', shown_only and 'Shown only' or 'All readouts') then
            if imgui.Selectable('All readouts', not shown_only) then shown_only = false; dragged, drag_target = nil, nil; end
            if imgui.Selectable('Shown only', shown_only) then shown_only = true; dragged, drag_target = nil, nil; end
            imgui.EndCombo();
        end
        tip('Show all readouts or only those enabled for the bar. Conditions can still hide an enabled readout.');
        beside(imgui.CalcTextSize('Add readout') + 20);
        add_readout(settings);
        beside(120);
        imgui.SetNextItemWidth(math.max(80, (imgui.GetContentRegionAvail()) - (readout_filter[1] ~= '' and 58 or 0)));
        if imgui.InputTextWithHint('##Filter readouts', 'Filter readouts', readout_filter, 81) then dragged, drag_target = nil, nil; end
        tip('Find a readout by its name, label, or purpose. Filtering does not change the bar.');
        if readout_filter[1] ~= '' then
            imgui.SameLine();
            if imgui.SmallButton('Clear##readout_filter') then readout_filter[1] = ''; dragged, drag_target = nil, nil; end
        end
        local rows = filtered_readouts(settings);
        local index;
        for i, row in ipairs(rows) do if row.id == selected then index = i; break; end end
        local function move(to)
            if index and rows[to] and layout.reorder(settings.display.order, rows[index].index, rows[to].index) then pending = true; scroll_selected = true; end
        end
        imgui.BeginDisabled(index == nil);
        button_row({ { 'First##order', function() move(1); end, 'Move before the first listed readout.' }, { 'Up##order', function() move((index or 1) - 1); end, 'Move before the previous listed readout.' },
            { 'Down##order', function() move((index or 0) + 1); end, 'Move after the next listed readout.' }, { 'Last##order', function() move(#rows); end, 'Move after the last listed readout. Other readouts keep their relative order.' } });
        imgui.EndDisabled();
        rows = filtered_readouts(settings);
        if dragged then drag_target = nil; end
        local list_height = math.min(205, math.max(92, (#rows + 1) * (imgui.GetFrameHeight() + 3) + 14));
        if imgui.BeginChild('##readout_order', { 0, list_height }, ImGuiChildFlags_Borders or 1) then
            local font, font_size = tostring(imgui.GetFont()), imgui.GetFontSize();
            local start = imgui.GetCursorPosX();
            local show_x = start + 32;
            local divider_x = show_x + math.max(44, imgui.CalcTextSize('Show') + 10);
            local name_x = divider_x + math.max(54, imgui.CalcTextSize('Divider') + 10);
            imgui.SetCursorPosX(show_x); imgui.TextDisabled('Show');
            imgui.SameLine(divider_x); imgui.TextDisabled('Divider');
            imgui.SameLine(name_x); imgui.TextDisabled('Readout');
            imgui.Separator();
            if dragged and imgui.IsMouseDown(ImGuiMouseButton_Left) then
                local x, y = imgui.GetWindowPos();
                local w, h = imgui.GetWindowSize();
                local mx, my = imgui.GetMousePos();
                if mx >= x and mx < x + w and my >= y and my < y + h then
                    if my < y + 20 then imgui.SetScrollY(math.max(0, imgui.GetScrollY() - 5));
                    elseif my > y + h - 20 then imgui.SetScrollY(imgui.GetScrollY() + 5); end
                end
            end
            for _, row in ipairs(rows) do
                local i, id = row.index, row.id;
                imgui.PushID(id);
                local row_left = imgui.GetCursorScreenPos();
                imgui.SmallButton('::##drag_' .. id);
                if imgui.IsItemActivated() then dragged, selected, drag_target = id, id, nil; end
                tip('Drag this handle to move the readout.');
                imgui.SameLine(show_x);
                local checked = { settings.display.enabled[id] };
                if imgui.Checkbox('##shown', checked) then settings.display.enabled[id] = checked[1]; pending = true; end
                tip('Show this readout on the bar.');
                imgui.SameLine(divider_x);
                local divider = { settings.display.dividers[id] ~= false };
                if imgui.Checkbox('##divider_' .. id, divider) then set_divider(settings, id, divider[1]); end
                tip('Add a divider before this readout. The first readout in each group has none. If no divider style is set, this uses |.');
                imgui.SameLine(name_x);
                local definition = readouts.definition(id);
                local label = string.format('%02d  %s', i, definition.name);
                local available = math.max(1, (imgui.GetContentRegionAvail()));
                local size = readout_sizes[id];
                if not size or size.label ~= label or size.width ~= available or size.font ~= font or size.font_size ~= font_size then
                    local wrapped = imgui.CalcTextSize(label) > available;
                    local label_height = 0;
                    if wrapped then
                        local _, height = imgui.CalcTextSize(label, false, available);
                        label_height = height;
                    end
                    size = { label = label, width = available, font = font, font_size = font_size, wrapped = wrapped, height = label_height };
                    readout_sizes[id] = size;
                end
                local wrapped = size.wrapped;
                if wrapped then imgui.PushStyleColor(ImGuiCol_Text, { 0, 0, 0, 0 }); end
                local picked = imgui.Selectable(label, selected == id, 0, { 0, size.height });
                if wrapped then imgui.PopStyleColor(); end
                if picked then
                    selected = id;
                    settings.window.sections[settings.window.tab .. '/Selected readout'] = true;
                    pending = true;
                end
                local left, top = imgui.GetItemRectMin();
                local right, bottom = imgui.GetItemRectMax();
                local mx, my = imgui.GetMousePos();
                if dragged and mx >= row_left and mx <= right and my >= top and my < bottom then
                    drag_target = my < (top + bottom) / 2 and i or i + 1;
                    local line = drag_target == i and top or bottom;
                    imgui.GetWindowDrawList():AddLine({ row_left, line }, { right, line }, theme.u32(window_colors.accent), 2);
                end
                if scroll_selected and selected == id then imgui.SetScrollHereY(0.5); scroll_selected = false; end
                tip(definition.name .. '\n' .. definition.help);
                if wrapped then
                    local next_x, next_y = imgui.GetCursorScreenPos();
                    imgui.SetCursorScreenPos({ left, top });
                    note(label);
                    imgui.SetCursorScreenPos({ next_x, next_y });
                end
                imgui.PopID();
            end
            if #rows == 0 then note('No matching readouts.'); end
        end
        imgui.EndChild();
        if dragged and not imgui.IsMouseDown(ImGuiMouseButton_Left) then
            local from;
            for i, id in ipairs(settings.display.order) do if id == dragged then from = i; break; end end
            if from and drag_target then
                local to = drag_target > from and drag_target - 1 or drag_target;
                if layout.reorder(settings.display.order, from, to) then pending, scroll_selected = true, true; end
            end
            dragged, drag_target = nil, nil;
        end
        local dividers = { { name = 'Line |', value = ' | ' }, { name = 'Slash /', value = ' / ' }, { name = 'Dash -', value = ' - ' },
            { name = 'Dot .', value = ' . ' }, { name = 'Asterisk *', value = ' * ' }, { name = 'Space', value = ' ' },
            { name = 'Two spaces', value = '  ' }, { name = 'None', value = '' } };
        local divider_name = 'Custom: ' .. settings.display.divider;
        for _, divider in ipairs(dividers) do if divider.value == settings.display.divider then divider_name = divider.name; break; end end
        combo('Divider style', divider_name, dividers, function(value) settings.display.divider = value; pending = true; end);
        button_row({ { 'Add dividers to all', function()
            for _, item in ipairs(defaults.READOUTS) do set_divider(settings, item.id, true); end
        end, 'Add a divider before each readout except the first one in each group. If no divider style is set, this uses |.' },
            { 'Remove all dividers', function()
                for _, item in ipairs(defaults.READOUTS) do set_divider(settings, item.id, false); end
            end, 'Remove the dividers from every readout. Your chosen divider style stays saved.' } });
        combo('Starter layout', starter_name(settings), { 'Minimal', 'Leveling', 'Merits', 'Dynamis' }, function(value)
            if defaults.apply_starter(settings, value) then pending = true; end
        end);
        imgui.BeginDisabled(settings.modes.selected ~= 'auto');
        local automatic_display = settings.dynamis.layout_active and settings.dynamis.previous_display or settings.display;
        checkbox(automatic_display, 'auto_layout', 'Automatically switch EXP / Merits layouts',
            'When Bar mode is Automatic, use Leveling when earning EXP and Merits when earning LP. This also applies after you leave Dynamis. Manual modes stay selected. This does not switch your mode in the game.');
        imgui.EndDisabled();
        checkbox(settings.display, 'groups_enabled', 'Use separate alignment groups',
            'Put readouts on the left, in the center, or on the right under Selected readout. Each group follows your list order. Turn this off to use one alignment for the whole bar.');
        checkbox(settings.display, 'priority_overflow', 'Keep priority readouts when space is short',
            'Keep readouts with a higher Display priority when the bar fills up. Readouts marked Keep visible first come before the others. Hover over ... to see anything hidden.');
    end
    if section('Selected readout', 'Select a row above to change its label, alignment group, priority, conditions, divider, or color.', false) then
        local definition = readouts.definition(selected);
        heading(definition.name, definition.help);
        input(settings.display.labels, selected, 'Label##readout', 32, 'Leave this empty to show only the value and any built-in EXP or LP unit.');
        local divider = { settings.display.dividers[selected] ~= false };
        if imgui.Checkbox('Divider before this readout', divider) then set_divider(settings, selected, divider[1]); end
        help('Add a divider before this readout. The first readout in each group has none. If no divider style is set, this uses |.');
        local custom = { settings.display.colors[selected] ~= nil };
        if imgui.Checkbox('Use a separate value color', custom) then
            local base = (selected == 'chain' or selected == 'chain_time') and settings.style.colors.chain or settings.style.colors.text;
            settings.display.colors[selected] = custom[1] and defaults.copy(base) or nil;
            pending = true;
        end
        help('Choose a color just for this value. Turn this off to use the skin color again.');
        if custom[1] then color(settings.display.colors, selected, 'Value color'); end
        if selected == 'chain_time' then
            color(settings.style.colors, 'chain_ending', 'Below 10 seconds');
            note('Below 10 seconds, this warning color replaces the normal countdown color.');
        end
        if section('More options', 'Choose when this readout appears and which readouts to keep if the bar is too narrow. Hover each control for an example.', false) then
            if settings.display.groups_enabled then
                pick(settings.display.groups, selected, 'Readout group', {
                    { name = 'Left', value = 'left' }, { name = 'Center', value = 'center' }, { name = 'Right', value = 'right' } });
            end
            checkbox(settings.display.pinned, selected, 'Keep visible first', 'Keep this readout before unmarked ones when the bar is too narrow. If it still cannot fit, hover ... on the bar to see it.');
            local fitting = settings.display.groups_enabled or settings.display.priority_overflow;
            for _, pinned in pairs(settings.display.pinned) do fitting = fitting or pinned; end
            imgui.BeginDisabled(not fitting);
            slider(settings.display.priorities, selected, 'Display priority', 0, 100);
            imgui.EndDisabled();
            if not fitting then note('Enable Keep priority readouts when space is short, alignment groups, or Keep visible first to use this priority.'); end
            tip(tips['Display priority']);
            pick(settings.display.conditions, selected, 'Show when', {
                { name = 'Always', value = 'always' }, { name = 'When its value is known', value = 'known' },
                { name = 'While showing EXP', value = 'exp' }, { name = 'While showing LP', value = 'lp' },
                { name = 'While Level Sync is active', value = 'synced' }, { name = 'While an EXP chain timer is running', value = 'chain' },
                { name = 'While Dedication is active', value = 'dedication' }, { name = 'While a food effect is active', value = 'food' },
            });
        end
    end
    position(settings, services);
    if section('Dividers and formatting', 'Choose the dividers, spacing, and number style for your bar. Use the Divider checkbox beside each readout to turn its divider on or off.', false) then
        input(settings.display, 'divider', 'Custom divider', 16, 'Type your own plain text between readouts. The style above will show Custom. Each row\'s Divider checkbox chooses where it appears.');
        input(settings.display, 'label_divider', 'Label separator', 8);
        slider(settings.display, 'spacing', 'Extra space between readouts', 0, 24);
        color(settings.style.colors, 'divider', 'Divider color');
        checkbox(settings.display, 'short', 'Short numbers', 'Show values such as 12.5k instead of 12,500.');
        checkbox(settings.display, 'chain_strip', 'Show the EXP chain timer line', 'Show a countdown line above your EXP chain. A dim line uses an estimate from Phoenix rules. A bright line uses an end time reported by Phoenix. The line stays hidden when no timer is available.');
        checkbox(settings.display, 'hover', 'Show details on hover', 'Hover over a readout for its value and an explanation. Hover over ... for readings that do not fit. Hold Shift when you want to move or resize the bar instead.');
    end
end

local function tracking_page(settings, view, services)
    if section('EXP and merits', 'Choose whether the bar shows EXP or LP and how EXP/HR and LP/HR are calculated. Unknown values show --. Times to your next level, merit point, or goal are estimates.', true) then
        imgui.BeginDisabled(settings.modes.selected ~= 'auto');
        pick(settings.display, 'mode', 'Show EXP or LP', { { name = 'Automatic', value = 'auto' }, { name = 'EXP', value = 'exp' }, { name = 'Limit points (LP)', value = 'lp' } });
        imgui.EndDisabled();
        pick(settings.tracking, 'window', 'EXP/HR time period', { { name = 'Last 5 minutes', value = 300 }, { name = 'Last 15 minutes', value = 900 },
            { name = 'Last 30 minutes', value = 1800 }, { name = 'Whole session', value = 0 } });
        pick(settings.tracking, 'rate_basis', 'Rate calculation', { { name = 'EXP/LP received', value = 'earned' }, { name = 'EXP/LP kept', value = 'net' } });
        slider(settings.tracking, 'average_count', 'Recent gains to average', 1, 100);
        settings.tracking.average_count = math.floor(settings.tracking.average_count + 0.5);
    end
    if section('Progress goal', 'Choose a level, EXP, merit point, or EXP buffer goal. Add the Goal readout under Display to show it on your bar.', false) then
        pick(settings.tracking, 'goal_type', 'Goal type', {
            { name = 'Save merit points', value = 'stored_merits' }, { name = 'Reach a level', value = 'level' },
            { name = 'Earn EXP this session', value = 'session_exp' }, { name = 'Earn merit points this session', value = 'session_merits' },
            { name = 'Build an EXP buffer', value = 'buffer' },
        });
        local merit_cap = type(view.merit_cap) == 'number' and view.merit_cap > 0 and view.merit_cap or 30;
        if settings.tracking.goal_type == 'stored_merits' then
            slider(settings.tracking, 'goal_merits', 'Merit points to save', 1, math.max(merit_cap, settings.tracking.goal_merits));
            settings.tracking.goal_merits = math.floor(settings.tracking.goal_merits + 0.5);
        elseif settings.tracking.goal_type == 'level' then slider(settings.tracking, 'goal_level', 'Target level', 1, 75);
        elseif settings.tracking.goal_type == 'session_exp' then slider(settings.tracking, 'goal_exp', 'Session EXP target', 1, 1000000);
        elseif settings.tracking.goal_type == 'session_merits' then slider(settings.tracking, 'goal_session_merits', 'Merit points to earn', 1, 100);
        elseif settings.tracking.goal_type == 'buffer' then slider(settings.tracking, 'goal_buffer', 'Target EXP buffer', 1, 43999); end
        for _, key in ipairs({ 'goal_level', 'goal_exp', 'goal_session_merits', 'goal_buffer' }) do settings.tracking[key] = math.floor(settings.tracking[key] + 0.5); end
        if view.goal then
            note(view.goal.label or 'Selected goal');
            if view.goal.available then
                note(view.goal.complete and 'Goal complete.' or readouts.format_number(view.goal.remaining) .. ' ' .. (view.goal.unit or '') .. ' remaining'
                    .. (view.goal.eta and '   |   ~' .. readouts.format_time(view.goal.eta) or '   |   Time estimate unavailable'));
            else note(view.goal.reason or 'This goal is not available for your character right now.'); end
            if view.goal.available and view.goal.blocked and view.goal.reason then note(view.goal.reason); end
        end
    end
    if section('Visibility', 'Hide the bar temporarily while other game screens are open. Tracking continues while the bar is hidden.', false) then
        checkbox(settings.tracking, 'hide_idle', 'Hide until the session starts', 'Keep the bar hidden until your session timer starts. Sample previews still appear.');
        checkbox(settings.visibility, 'map', 'Hide while the map is open', 'Hide the bar while viewing the in-game map.');
        checkbox(settings.visibility, 'event', 'Hide during cutscenes', 'Hide the bar during cutscenes and NPC conversations.');
        checkbox(settings.visibility, 'game_ui', 'Hide with the game UI', 'Hide the bar when the game interface is hidden.');
    end
end

local function appearance_page(settings)
    if section('Skin and text', 'Choose a skin and adjust the bar or settings text. Your readout order and position stay as they are.', true) then
        combo('Skin', theme.current(settings) or ('Custom (' .. settings.style.preset .. ')'), theme.names,
            function(name) theme.apply(settings, name); pending = true; end);
        pick(settings.style, 'font', 'Font', fonts.names());
        slider(settings.style, 'font_size', 'Bar text size', 8, 48);
        slider(settings.window, 'font_size', 'Settings text size', 12, 28);
        checkbox(settings.window, 'compact_navigation', 'Use a tab dropdown', 'Use one dropdown to choose a settings tab. This leaves more room in a narrow window.');
    end
    if section('Bar and progress', 'Adjust the bar background, shape, progress fill, and text visibility.', false) then
        slider(settings.style, 'opacity', 'Bar background opacity', 0.05, 1, '%.2f');
        slider(settings.style, 'rounding', 'Corner roundness', 0, 24);
        pick(settings.style, 'fill_style', 'Progress style', { { name = 'Thin line', value = 'rail' }, { name = 'Full background', value = 'full' } });
        pick(settings.style, 'fill_direction', 'Fill direction', { { name = 'Left to right', value = 'right' }, { name = 'Right to left', value = 'left' } });
        checkbox(settings.display, 'show_fill', 'Show progress fill', 'Show how much EXP or LP you have toward your next level or merit point.');
        checkbox(settings.display, 'show_text', 'Show readout text', 'Turn this off to show just the EXP or LP bar without the numbers.');
        checkbox(settings.style, 'border', 'Show border', 'Draw an outline around the bar.');
        checkbox(settings.style, 'text_shadow', 'Text shadow', 'Add a small shadow to help text stand out against the game.');
    end
    if section('Bar colors', 'Customize the bar colors. A skin restores its own colors without changing your readouts or placement.', false) then
        for _, entry in ipairs({ { 'background', 'Background' }, { 'fill', 'EXP fill' }, { 'lp_fill', 'LP fill' }, { 'text', 'Values' },
            { 'label', 'Labels' }, { 'divider', 'Dividers' }, { 'border', 'Border' }, { 'chain', 'Chains' },
            { 'chain_ending', 'Chain ending text' }, { 'warning', 'Hidden readout indicator' } }) do
            color(settings.style.colors, entry[1], entry[2]);
        end
        note('Chain ending text applies below 10 seconds remaining.');
    end
    if section('Settings window colors', 'Customize the settings window colors separately from the bar.', false) then
        for _, entry in ipairs(theme.WINDOW_COLORS) do
            if entry[1] ~= 'success' then color(settings.style.window_colors, entry[1], entry[2]); end
        end
    end
end

local preview_options_requested = false;
local function fixed_preview(settings, view, services)
    imgui.SetNextItemWidth(math.min(imgui.CalcTextSize('Sample preview') + imgui.GetFrameHeight() + 16, (imgui.GetContentRegionAvail())));
    if imgui.BeginCombo('##Preview source', sample_preview and 'Sample preview' or 'Live preview') then
        if imgui.Selectable('Live', not sample_preview) then sample_preview = false; end
        if imgui.Selectable('Sample', sample_preview) then sample_preview = true; end
        imgui.EndCombo();
    end
    tip('Preview your current EXP and LP or use sample numbers. This only changes the preview in settings.');
    if sample_preview then
        local sample_width = imgui.CalcTextSize('Leveling') + imgui.GetFrameHeight() + 16;
        beside(sample_width);
        imgui.SetNextItemWidth(math.min(sample_width, (imgui.GetContentRegionAvail())));
        if imgui.BeginCombo('##Sample state', settings.preview.scenario) then
            for _, name in ipairs({ 'Leveling', 'Merits', 'Dynamis', 'Capped', 'No data', 'Paused' }) do
                if imgui.Selectable(name, name == settings.preview.scenario) then settings.preview.scenario = name; pending = true; end
            end
            imgui.EndCombo();
        end
        tip('Choose sample EXP and LP readings. If Show sample on game bar is on, the same sample appears there.');
    end
    beside(imgui.CalcTextSize('Preview options') + 20);
    local opening = imgui.Button('Preview options') or preview_options_requested;
    local popup_x = imgui.GetItemRectMin();
    local _, popup_y = imgui.GetItemRectMax();
    if opening then
        imgui.OpenPopup('##preview_options');
        preview_options_requested = false;
    end
    local shown = sample_preview and readouts.sample(settings.preview.scenario) or view;
    local context = services.preview_context and services.preview_context() or {};
    context.preview = sample_preview;
    local fit = hud.draw_inline(settings, shown, (imgui.GetContentRegionAvail()), nil, context);
    if fit then
        if fit.unavailable then note('Waiting for the game window or chat log before placing the bar.');
        elseif fit.overflow then note(string.format('%d readout%s hidden at the current bar width. Hover ... on the bar for their values.', fit.hidden_count, fit.hidden_count == 1 and ' is' or 's are'));
        elseif fit.preview_clipped then note('Your bar fits. This window shows only part of the preview.');
        end
    end
    local screen = imgui.GetIO().DisplaySize;
    local popup_width, popup_height = math.min(360, screen.x - 24), math.min(360, screen.y - 24);
    if opening then
        imgui.SetNextWindowPos({ layout.clamp(popup_x, 8, screen.x - popup_width - 8), layout.clamp(popup_y + 4, 8, screen.y - popup_height - 8) }, ImGuiCond_Appearing);
    end
    imgui.SetNextWindowSize({ popup_width, 0 }, ImGuiCond_Always);
    imgui.SetNextWindowSizeConstraints({ popup_width, 0 }, { popup_width, popup_height });
    if imgui.BeginPopup('##preview_options') then
        checkbox(settings.preview, 'show', 'Show sample on game bar', 'Show sample numbers on your game bar. Your session keeps tracking. Turn this off to show your current EXP and LP again.');
        note('Sample on game bar: ' .. settings.preview.scenario);
        local key = 'Preview/Narrow width test';
        local saved = settings.window.sections[key] == true;
        local finding = query[1]:lower():find('narrow', 1, true) ~= nil;
        imgui.SetNextItemOpen(finding or saved, ImGuiCond_Always);
        local open = imgui.CollapsingHeader('Narrow width test##narrow_preview');
        if not finding and open ~= saved then settings.window.sections[key] = open; pending = true; end
        if open then
            local narrow = math.min(280, (imgui.GetContentRegionAvail()));
            hud.draw_inline(settings, readouts.sample(settings.preview.scenario), narrow, nil, { preview = true, width = narrow,
                chat = context.chat, chat_checked = context.chat_checked, now = context.now });
            note('This sample uses a 280-pixel bar, or less if space is short. It does not resize your bar.');
        end
        imgui.EndPopup();
    end
end

local function session_page(settings, view, services)
    if section('Current session', 'Review your EXP and LP gains, EXP lost on death, EXP recovered through Raise, and time spent this session. Use Reset session to save this run and start fresh.', true) then
        note(readouts.summary(view));
        button_row({ { 'Copy summary', function() if services.copy then services.copy(readouts.summary(view)); status = 'Session summary copied.'; end end,
            'Copy these session totals as plain text.' } });
        details.current_session(settings, view, services, controls);
    end
    details.sessions(settings, view, services, controls);
end

local function profile_action(callback, name, success)
    if not callback then status = 'This profile action is unavailable.'; return false; end
    local okay, message = callback(name);
    status = okay == false and (message or 'That could not be saved.') or success;
    return okay ~= false;
end

local function profiles_page(settings, view, services)
    local names = services.profile_names and services.profile_names() or {};
    if section('Saved profiles', 'Save your bar layout, readouts, colors, and tracking settings. Profiles do not change your EXP, LP, merit points, or session history.', true) then
        combo('Profile', profile_selected or '(choose)', names, function(name)
            profile_selected = name; profile_name[1] = name; profile_confirmation = nil;
        end);
        imgui.TextUnformatted('Profile name');
        help('Choose a short name for a reusable layout. Saving over an existing name asks for confirmation.');
        imgui.SetNextItemWidth(math.min(320, (imgui.GetContentRegionAvail())));
        if imgui.InputText('##Profile name', profile_name, 49) then profile_confirmation = nil; end
        button_row({ { 'Save profile', function()
                local candidate = profile_name[1]:match('^%s*(.-)%s*$');
                local latest = services.profile_names and services.profile_names(true) or names;
                if services.profile_error then status = services.profile_error; return; end
                local exists = false;
                for _, name in ipairs(latest) do if name == candidate then exists = true; end end
                if exists then
                    profile_confirmation = { action = 'replace', name = candidate };
                else
                    if profile_action(services.save_profile, candidate, 'Profile saved.') then profile_selected = candidate; end
                end
            end, 'Save the current layout with the entered name. Replacing an existing profile asks for confirmation.' }, { 'Load profile', function()
                if profile_selected then profile_action(services.load_profile, profile_selected, 'Profile loaded.'); end
            end, 'Use the selected profile. Your session totals stay the same.' }, { 'Delete profile', function()
                if profile_selected then profile_confirmation = { action = 'delete', name = profile_selected }; end
            end, 'Remove the selected saved profile after confirmation.' } });
        if profile_confirmation then
            local deleting = profile_confirmation.action == 'delete';
            note((deleting and 'Delete ' or 'Replace ') .. profile_confirmation.name .. '? This changes the saved profile.');
            button_row({ { deleting and 'Delete saved profile' or 'Replace saved profile', function()
                    local action = profile_confirmation;
                    if profile_action(deleting and services.delete_profile or services.save_profile, action.name,
                        deleting and 'Profile deleted.' or 'Profile saved.') then
                        if deleting then profile_selected = nil; else profile_selected = action.name; end
                        profile_confirmation = nil;
                    end
                end }, { 'Keep saved profile', function() profile_confirmation = nil; end } });
        end
    end
    if section('Job links', 'Automatically load one of your saved layouts when you change to a linked job.', false) then
        local options = {};
        for id, name in ipairs(jobs) do options[#options + 1] = { name = name, value = id }; end
        combo('Job', jobs[profile_job] or tostring(profile_job), options, function(value) profile_job = value; end);
        local links = { { name = '(none)', value = '' } };
        for _, name in ipairs(names) do links[#links + 1] = name; end
        combo('Load this profile on job change', settings.job_links[tostring(profile_job)] or settings.job_links[profile_job] or '(none)', links, function(value)
            if services.job_link then services.job_link(profile_job, value ~= '' and value or nil); end
        end);
        if view.job then
            if imgui.Button('Select current job') then profile_job = view.job; end
            tip('Choose your current main job in the selector above.');
        end
    end
    if section('Characters', 'Choose whether your characters use the same layout. Each character keeps its own sessions.', false) then
        local share = { settings.shared };
        if imgui.Checkbox('Use one layout for all characters', share) then
            if services.shared then services.shared(share[1]); else settings.shared = share[1]; pending = true; end
        end
        help('Use the same bar layout and colors on every character. Each character keeps its own EXP, LP, merit points, and session history.');
    end
end

local search_sections = {
    { 'Display', 'Readouts and order', 'readouts shown filter order move first last up down groups priority dividers separator starter automatic switch exp merits layouts' },
    { 'Display', 'Selected readout', 'label divider value color countdown chain ending' },
    { 'Display', 'More options', 'condition pinned priority group advanced readout' },
    { 'Display', 'Preview options', 'sample preview leveling merits capped paused no data narrow game bar' },
    { 'Display', 'Position and size', 'alignment left right label position before after width maximum auto height placement free dock chat top bottom above below start lock snap hide typing' },
    { 'Display', 'Dividers and formatting', 'divider custom spacing separator short numbers hover chain strip' },
    { 'Tracking', 'EXP and merits', 'rate hour window exp limit points mode merits reward sample earned net' },
    { 'Tracking', 'Progress goal', 'goal target level session buffer merit' },
    { 'Tracking', 'Visibility', 'hide map event game ui visibility' },
    { 'Dynamis', 'Dynamis options', 'dynamis automatic layout mode enabled tracking history retention' },
    { 'Dynamis', 'Current Dynamis run', 'dynamis time hourglass currency relic armor af2 received found reset clear summary copy weakness support job clear' },
    { 'Dynamis', 'Objectives and time extensions', 'dynamis te time extension boss weakening wave monsters unknown objectives' },
    { 'Dynamis', 'Currency and drops', 'dynamis currency singles hundred bronze byne shells relic af2 received found loot' },
    { 'Dynamis', 'Treasure pool', 'dynamis treasure pool lot pass expiration items waiting' },
    { 'Dynamis', 'Wanted drops', 'dynamis wanted drops alert job relic armor af2 accessory weapon attestation fragment search' },
    { 'Dynamis', 'Dynamis run history', 'dynamis saved run history summary copy' },
    { 'Details', 'Level sync', 'sync penalty level' },
    { 'Details', 'Advanced sync estimate', 'sync planner estimate population tier' },
    { 'Details', 'EXP and limit points', 'exp lp progress totals earned net lost recovered' },
    { 'Details', 'Merit points', 'merits stored slots capacity earned session lp next time limit points' },
    { 'Details', 'Food and Dedication', 'food timer dedication buff bonus' },
    { 'Details', 'Owned EXP rings', 'rings charges recast cooldown inventory' },
    { 'Details', 'Recent rewards', 'reward sample min max median average' },
    { 'Alerts', 'Food', 'alert notification food effect wore off food effect ending soon warning sound volume notice visual cooldown play refresh mp3 wav' },
    { 'Alerts', 'EXP chains', 'alert notification exp chain timer low warning countdown sound volume notice visual cooldown play refresh' },
    { 'Alerts', 'Dedication', 'alert notification dedication wore off dedication bonus exp low remaining sound volume notice visual cooldown play refresh' },
    { 'Alerts', 'EXP rings', 'alert notification exp ring ready recast charges sound volume notice visual cooldown play refresh' },
    { 'Alerts', 'Levels and merit points', 'alert notification level gained merit point gained goal reached merit points almost full cap storage sound volume notice visual cooldown play refresh' },
    { 'Alerts', 'Level Sync and missed EXP', 'alert notification level sync changed penalty missed no exp reason distance range sound volume notice visual cooldown play refresh' },
    { 'Alerts', 'Dynamis', 'dynamis alert warning time extension wanted drop pool expires clear support job sound notice' },
    { 'Alerts', 'Quiet conditions', 'quiet paused event cutscene suppress' },
    { 'Appearance', 'Skin and text', 'skin font text size compact tab navigation selector' },
    { 'Appearance', 'Bar and progress', 'opacity transparency corners round border fill shadow rail accent text visibility' },
    { 'Appearance', 'Bar colors', 'color background exp lp value label divider border chain ending countdown warning' },
    { 'Appearance', 'Settings window colors', 'window color heading accent text muted success warning' },
    { 'Session', 'Current session', 'session pause resume reset copy summary rewards earned net lost recovered adjustment' },
    { 'Session', 'Saved sessions', 'history save name rename delete records' },
    { 'Session', 'Session storage', 'retention resume storage keep' },
    { 'Profiles', 'Saved profiles', 'profile save load delete layout' },
    { 'Profiles', 'Job links', 'job automatic links' },
    { 'Profiles', 'Characters', 'shared all characters' },
};
local last_search = '';

local function change_page(settings, page)
    settings.window.tab = page;
    search_target, search_scroll, search_focus, last_search = nil, nil, false, '';
    pending = true;
end

local function search(settings)
    imgui.SetNextItemWidth(math.min(320, (imgui.GetContentRegionAvail()) - (query[1] ~= '' and 88 or 32)));
    imgui.InputTextWithHint('##Find settings', 'Find settings', query, 81);
    if query[1] ~= '' then
        imgui.SameLine();
        if imgui.SmallButton('Clear##settings_search') then query[1] = ''; end
    end
    help('Find a section or readout. Choose a result to jump to it. Clear the search to restore your saved sections.');
    local term = query[1]:lower():match('^%s*(.-)%s*$');
    search_matches = {};
    if term ~= last_search then search_target, search_scroll, search_focus = nil, nil, false; end
    if term == '' then last_search = term; return; end
    local results = {};
    local first;
    local function jump(page, title)
        settings.window.tab = page;
        if title == 'Preview options' then sample_preview, preview_options_requested = true, true; end
        search_target = page .. '/' .. title;
        search_scroll = search_target;
        search_focus = true;
        search_matches = { [search_target] = true };
        pending = true;
    end
    for _, entry in ipairs(search_sections) do
        local page, title = entry[1], entry[2];
        if ((section_names[title] or title) .. ' ' .. entry[3]):lower():find(term, 1, true) then
            local key = page .. '/' .. title;
            search_matches[key] = search_target == nil or search_target == key;
            if not first and page == settings.window.tab then first = key; end
            results[#results + 1] = { page .. ': ' .. (section_names[title] or title) .. '##find', function() jump(page, title); end };
        end
    end
    for _, item in ipairs(defaults.READOUTS) do
        if (item.name .. ' ' .. item.help):lower():find(term, 1, true) then
            results[#results + 1] = { item.name .. '##find', function()
                selected = item.id;
                jump('Display', 'Selected readout');
            end };
        end
    end
    if search_target then search_matches[search_target] = true; end
    if term ~= last_search then search_scroll = first; end
    last_search = term;
    if #results == 0 then note('No match. Try order, divider, font, rate, or profile.');
    else
        if imgui.BeginChild('##search_results', { 0, math.min(84, #results * (imgui.GetFrameHeight() + 4)) }, 0) then button_row(results); end
        imgui.EndChild();
    end
end

local bar_modes = { 'auto', 'exp', 'merits', 'dynamis' };
local mode_names = require('ui.modes').names;
local function toolbar(settings, view, services)
    imgui.AlignTextToFramePadding();
    imgui.TextUnformatted('Bar mode');
    beside(210);
    imgui.SetNextItemWidth(math.min(170, (imgui.GetContentRegionAvail())));
    if imgui.BeginCombo('##Bar mode', mode_names[settings.modes.selected]) then
        for _, mode in ipairs(bar_modes) do
            if imgui.Selectable(mode_names[mode] .. '##bar_mode_' .. mode, settings.modes.selected == mode) and services.bar_mode then
                services.bar_mode(mode);
            end
        end
        imgui.EndCombo();
    end
    help('Pick EXP, Merits, or Dynamis to keep that bar selected. Each keeps its own layout. Automatic uses your automatic layout settings. This only changes the bar, not how you earn EXP or LP.');
    button_row({
        { view.paused and 'Resume session' or 'Pause session', function()
            if services.session_pause then services.session_pause(not view.paused); end
        end, (view.paused and 'Resume counting EXP, LP, merit points, and session time.'
            or 'Stop counting EXP, LP, merit points, and session time.')
            .. ' EXP chain, food, Dedication, EXP ring recast, and Dynamis timers keep running. Dynamis drops still count.' },
        { 'Reset session', function()
            local current = services.session_current and services.session_current();
            reset_layout = false;
            local okay, problem;
            if services.session_reset then okay, problem = services.session_reset(); end
            if okay == true then
                status = 'Previous session saved. New session started.';
            else
                local after = services.session_current and services.session_current();
                if (after and after.id) ~= (current and current.id) then
                    status = 'The session was reset, but saving failed: ' .. (problem or 'The new session could not be saved.');
                else
                    status = problem or 'The session could not be saved and reset. Wait for your EXP and LP to load, then try again.';
                end
            end
        end, 'Save this session and clear its totals, EXP/HR, LP/HR, and Next. EXP chain, food, Dedication, EXP ring recast, and Dynamis timers keep running. Dynamis totals stay as they are.' },
        { 'Undo', function() if services.undo then services.undo(); end end, 'Undo one of the last eight saved settings changes. This does not undo a session reset.' },
    });
    beside(108);
    imgui.SetNextItemWidth(math.min(108, (imgui.GetContentRegionAvail())));
    if imgui.BeginCombo('##reset_actions', 'Reset...') then
        if imgui.Selectable('Reset this section') and services.reset_section then
            services.reset_section(page_section[settings.window.tab]);
        end
        tip('Reset the settings on this tab. Use Undo to bring your previous choices back.');
        if imgui.Selectable('Reset layout') then reset_layout = true; status = nil; end
        tip('Restore the default layout and settings after confirmation. Saved sessions remain in history.');
        imgui.EndCombo();
    end
    tip('Restore settings for this tab or the entire layout. Use Reset session to start a fresh EXP session.');
    if reset_layout then
        note('Restore the default layout and settings? Session history stays as it is.');
        button_row({ { 'Restore default layout', function()
            if services.reset then services.reset(); end
            reset_layout = false;
        end }, { 'Keep layout', function() reset_layout = false; end } });
    end
end

function settings_window.draw(settings, view, services)
    if not settings.window.open then return false; end
    services = services or {};
    if focus_on_open then imgui.SetNextWindowFocus(); focus_on_open = false; end
    if settings.window.tab == 'Preview' then
        settings.window.tab = 'Display';
        sample_preview, preview_options_requested, pending = true, true, true;
    end
    local screen = imgui.GetIO().DisplaySize;
    local width = math.min(settings.window.width, screen.x);
    local height = math.min(settings.window.height, screen.y);
    imgui.SetNextWindowPos({ layout.clamp(settings.window.x, 0, screen.x - width), layout.clamp(settings.window.y, 0, screen.y - height) }, ImGuiCond_Appearing);
    imgui.SetNextWindowSize({ width, height }, ImGuiCond_Appearing);
    imgui.SetNextWindowSizeConstraints({ math.min(400, screen.x), math.min(minimum_window_height, screen.y) }, { screen.x, screen.y });
    local pushed = fonts.push(settings.style.font, settings.window.font_size);
    window_colors = settings.style.window_colors;
    local colors = theme.push(settings);
    local open = { settings.window.open };
    local flags = bit.bor(ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse);
    if imgui.Begin('Momentum##settings', open, flags) then
        section_settings = settings;
        if type(settings.window.sections) ~= 'table' then settings.window.sections = {}; end
        local x, y = imgui.GetWindowPos();
        local w, h = imgui.GetWindowSize();
        if not imgui.IsMouseDown(ImGuiMouseButton_Left) and (x ~= settings.window.x or y ~= settings.window.y or w ~= settings.window.width or h ~= settings.window.height) then
            settings.window.x, settings.window.y, settings.window.width, settings.window.height = x, y, w, h;
            pending = true;
        end
        if settings.window.compact_navigation then
            imgui.SetNextItemWidth(math.min(240, (imgui.GetContentRegionAvail())));
            if imgui.BeginCombo('##settings_page', settings.window.tab) then
                for _, page in ipairs(pages) do
                    if imgui.Selectable(page, settings.window.tab == page) then change_page(settings, page); end
                end
                imgui.EndCombo();
            end
            help('Choose a settings tab. Turn off Use a tab dropdown under Appearance to show the tab buttons again.');
        else
            local nav = {};
            local active_color = defaults.copy(window_colors.accent);
            active_color[4] = settings.style.preset == 'Phoenix' and 0.45 or 0.40;
            for _, page in ipairs(pages) do
                nav[#nav + 1] = { page .. '##page', function() change_page(settings, page); end, nil,
                    page == settings.window.tab and active_color or nil };
            end
            button_row(nav);
        end
        toolbar(settings, view, services);
        search(settings);
        imgui.Separator();
        fixed_preview(settings, view, services);
        imgui.Separator();
        local _, page_height = imgui.GetContentRegionAvail();
        minimum_window_height = math.max(300, h - page_height + math.max(96, settings.window.font_size * 4));
        if imgui.BeginChild('##momentum_page', { 0, 0 }, 0, ImGuiWindowFlags_NoSavedSettings) then
            if status then note(status); end
            if settings.window.tab == 'Display' then display_page(settings, services);
            elseif settings.window.tab == 'Tracking' then tracking_page(settings, view, services);
            elseif settings.window.tab == 'Dynamis' then dynamis.draw(settings, view, services, controls);
            elseif settings.window.tab == 'Details' then details.draw(settings, view, services, controls);
            elseif settings.window.tab == 'Alerts' then details.alerts(settings, view, services, controls);
            elseif settings.window.tab == 'Appearance' then appearance_page(settings);
            elseif settings.window.tab == 'Session' then session_page(settings, view, services);
            elseif settings.window.tab == 'Profiles' then profiles_page(settings, view, services);
            end
        end
        imgui.EndChild();
    end
    imgui.End();
    imgui.PopStyleColor(colors);
    fonts.pop(pushed);
    if open[1] ~= settings.window.open then
        settings.window.open = open[1];
        if not open[1] then settings_window.close(); return true; end
        pending = true;
    end
    if pending and not imgui.IsAnyItemActive() and not imgui.IsMouseDown(ImGuiMouseButton_Left) then pending = false; return true; end
    return false;
end

function settings_window.close()
    dragged, drag_target, pending = nil, nil, false;
    preview_options_requested, search_focus = false, false;
    reset_layout, profile_confirmation = false, nil;
    details.cancel_pending();
    dynamis.cancel_pending();
    focus_on_open = true;
end

function settings_window.use_live_preview()
    sample_preview = false;
end

return settings_window;
