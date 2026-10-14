local defaults = require('ui.defaults');
local history = require('ui.history');
local player = require('core.player');
local hud = require('ui.hud');
local window = require('ui.settings_window');
local profiles = require('ui.profiles');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function check(value, label) equal(not not value, true, label); end
local function same(actual, expected, label) equal(history.equal(actual, expected), true, label); end
local function same_rect(actual, expected, label)
    for _, key in ipairs({ 'x', 'y', 'width', 'height' }) do equal(actual and actual[key], expected and expected[key], label .. ': ' .. key); end
end
local function close(actual, expected, label)
    count = count + 1;
    assert(type(actual) == 'number' and math.abs(actual - expected) < 0.000001,
        label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

equal(defaults.make().visibility.mode, 'keep', 'A new bar starts with Keep visible when chat closes');
local migration_cases = {
    { name = 'missing mode' }, { name = 'legacy placement', value = 'placement' },
    { name = 'empty mode', value = '' }, { name = 'unknown mode', value = 'invalid' },
    { name = 'number mode', value = 1 }, { name = 'boolean mode', value = false },
    { name = 'table mode', value = {} }, { name = 'missing visibility', whole = true },
};
for _, docked in ipairs({ false, true }) do
    for _, value in ipairs({ 'chat', 'keep', 'always' }) do
        local settings = defaults.make();
        settings.bar.docked, settings.visibility.mode = docked, value;
        defaults.tidy(settings);
        equal(settings.visibility.mode, value, 'An explicit visibility choice survives either placement');
        settings.bar.docked = not docked;
        defaults.tidy(settings);
        equal(settings.visibility.mode, value, 'Changing placement never changes an explicit visibility choice');
        local restored = defaults.make();
        profiles.apply(restored, { bar = { docked = docked }, visibility = { mode = value } });
        defaults.tidy(restored);
        equal(restored.visibility.mode, value, 'Profiles preserve each explicit choice with either placement');
        profiles.apply(restored, { style = { font_size = 15 } });
        defaults.tidy(restored);
        equal(restored.visibility.mode, value, 'A style-only profile preserves the current visibility choice');
    end
    for _, entry in ipairs(migration_cases) do
        local inferred = entry.value == 'placement' and docked and 'chat' or 'keep';
        local settings = defaults.make();
        settings.bar.docked, settings.visibility.mode = docked, entry.value;
        settings.visibility.map = false;
        if entry.whole then settings.visibility = nil; end
        defaults.tidy(settings);
        equal(settings.visibility.mode, inferred, entry.name .. ' uses the current default or legacy placement');
        if not entry.whole then equal(settings.visibility.map, false, 'Migration preserves other hide choices'); end
        settings.bar.docked = not docked;
        defaults.tidy(settings);
        equal(settings.visibility.mode, inferred, 'Later validation never repeats ' .. entry.name .. ' migration');

        local restored = defaults.make();
        restored.visibility.mode = 'always';
        local profile = { bar = { docked = docked }, visibility = { mode = entry.value, map = false } };
        if entry.whole then profile.visibility = nil; end
        profiles.apply(restored, profile);
        defaults.tidy(restored);
        equal(restored.visibility.mode, inferred, 'A profile with ' .. entry.name .. ' uses the current default or legacy placement');
        if not entry.whole then equal(restored.visibility.map, false, 'Profile migration preserves its other hide choices'); end
    end
end

local utc, effect_deadline, ring_deadline = 1800000000, 600, 500;
os.time = function() return utc + math.floor(MOCK.now); end;
player.utc = function() return utc + MOCK.now; end;
local stats = AshitaCore:GetMemoryManager():GetPlayer();
stats.GetStatusIcons = function() return { [0] = 251, [1] = 249 }; end;
stats.GetStatusTimers = function()
    local ending = ((utc + effect_deadline - 1009810800) * 60) % 4294967296;
    return { [0] = ending, [1] = ending };
end;
local extra = MOCK.bytes(24);
MOCK.put(extra, 0, 1, 1);
MOCK.put(extra, 1, 1, 6);
MOCK.put(extra, 3, 1, 0x90);
MOCK.put(extra, 4, 4, utc + ring_deadline - 1009810800);
local ring = { Id = 15762, Count = 1, Flags = 0, Extra = MOCK.packet(0, extra).data };
local get_memory = AshitaCore.GetMemoryManager;
AshitaCore.GetMemoryManager = function(...)
    local memory = get_memory(...);
    memory.GetInventory = function()
        return {
            GetContainerCountMax = function(_, bag) return bag == 0 and 1 or 0; end,
            GetContainerItem = function(_, bag, slot) return bag == 0 and slot == 1 and ring or nil; end,
        };
    end;
    return memory;
end;
local hiding = {};
local native_hidden = player.hidden;
player.hidden = function(flags)
    return flags.map and hiding.map or flags.event and hiding.event or flags.game_ui and hiding.game_ui or native_hidden(flags);
end;
local drawn, configs;
local draw, config_draw = hud.draw, window.draw;
hud.draw = function(settings, view, context)
    drawn = hud.bounds(settings, view, context);
    return draw(settings, view, context);
end;
window.draw = function(...)
    configs = configs + 1;
    return config_draw(...);
end;
local settings = defaults.make();
settings.bar.auto_width = false;
settings.bar.x, settings.bar.y, settings.bar.width = 35, 320, 500;
settings.display.enabled.ring = true;
settings.tracking.window = 0;
MOCK.settings_file = settings;
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
local chat = { x = 12, y = 520, width = 900, height = 344, windows = {} };
local function frame(expected, label, seconds)
    drawn, configs, MOCK.imgui_calls = nil, 0, {};
    MOCK.frame(seconds or 0.25);
    equal(app.state.broken, false, label .. ': render remains healthy');
    local bars = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' and call[2] == '##momentum_bar' then bars = bars + 1; end
    end
    equal(bars, expected and 1 or 0, label .. ': actual bar window visibility');
    return drawn;
end
local function command(text) MOCK.fire('command', { command = '/momentum' .. (text and ' ' .. text or '') }); end

-- A failed chat read is different from a confirmed hidden chat window.
for _, mode in ipairs({ 'chat', 'keep', 'always' }) do
    for _, docked in ipairs({ false, true }) do
        app.settings().visibility.mode, app.settings().bar.docked = mode, docked;
        local saved_bar = history.copy(app.settings().bar);
        for _, state in ipairs({ 'open', 'closed', 'unknown' }) do
            MOCK.chat = state == 'open' and chat or nil;
            if state == 'open' then MOCK.chat_visible = true;
            elseif state == 'closed' then MOCK.chat_visible = false;
            else MOCK.chat_visible = nil; end
            MOCK.chat_retained = chat;
            local visible = mode == 'keep' or mode == 'always' or state == 'open' or not docked and state == 'unknown';
            frame(visible, mode .. ', ' .. (docked and 'docked' or 'free') .. ', chat ' .. state);
            same(app.settings().bar, saved_bar, 'Visibility changes never rewrite the saved placement');
        end
    end
end

for _, mode in ipairs({ 'keep', 'always' }) do
    for _, anchor in ipairs({ 'top', 'bottom' }) do
        local bar = app.settings().bar;
        app.settings().visibility.mode, bar.docked, bar.anchor = mode, true, anchor;
        MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = chat, true, nil;
        local live = history.copy(frame(true, mode .. ' opens ' .. anchor .. ' anchor'));
        local saved_bar = history.copy(bar);
        MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, false, chat;
        same_rect(frame(true, mode .. ' retains ' .. anchor .. ' anchor'), live, 'Closed chat keeps the last drawn rectangle');
        MOCK.chat_retained = nil;
        same_rect(frame(true, mode .. ' loses native retained bounds'), live, 'Losing native bounds never moves an already drawn bar');
        MOCK.chat_visible = nil;
        same_rect(frame(true, mode .. ' cannot read chat'), live, 'Unknown chat keeps the last drawn rectangle');
        MOCK.chat_visible, MOCK.chat_retained = false, { x = 200, y = 200, width = 400, height = 200, windows = {} };
        same_rect(frame(true, mode .. ' receives changed retained bounds'), live, 'Changed retained chat bounds cannot relocate a held bar');
        local preview = hud.draw_inline(app.settings(), app.view(MOCK.now), 280);
        equal(preview.bar_width, live.width, 'An inline preview preserves held-chat metadata from its last draw');
        same(bar, saved_bar, 'Holding the drawn rectangle preserves saved placement');
        MOCK.chat, MOCK.chat_visible = { x = 40, y = 450, width = 750, height = 380, windows = {} }, true;
        local restored = frame(true, mode .. ' follows reopened chat');
        equal(restored.x, 40, 'Reopened chat restores current horizontal alignment');
        equal(restored.width, 750, 'Reopened chat restores current width');
        equal(restored.y, anchor == 'top' and 430 or 832, 'Reopened chat restores the selected edge');
        same(bar, saved_bar, 'Reopening chat does not overwrite saved free placement');
        MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, false, nil;
        same_rect(frame(true, mode .. ' closes again after reopening'), restored, 'The next close keeps the newly drawn position');
    end
end

for _, mode in ipairs({ 'keep', 'always' }) do
    local saved_bar = history.copy(app.settings().bar);
    app.settings().visibility.mode = mode;
    app.settings().bar = history.copy(saved_bar);
    local bar = app.settings().bar;
    bar.docked, bar.anchor = true, 'bottom';
    MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, nil, nil;
    local preview_context = { chat = chat, chat_visible = true, chat_checked = true, preview = true, width = 280 };
    hud.bounds(app.settings(), app.view(MOCK.now), preview_context);
    hud.draw_inline(app.settings(), require('ui.readouts').sample(), 280, 18, preview_context);
    local cold = frame(true, mode .. ' has never drawn a chat anchor');
    equal(cold.x, bar.x, 'A cold start may use saved free X');
    equal(cold.y, bar.y, 'A cold start may use saved free Y');
    equal(cold.width, bar.width, 'A cold start may use saved free width');
    MOCK.chat, MOCK.chat_visible = chat, true;
    local live = history.copy(frame(true, mode .. ' observes a real chat anchor'));
    local unchanged = history.copy(bar);
    local other_chat = { x = 100, y = 200, width = 400, height = 200, windows = {} };
    local context = { chat = other_chat, chat_visible = true, chat_checked = true, preview = true, width = 280 };
    hud.bounds(app.settings(), app.view(MOCK.now), context);
    hud.draw_inline(app.settings(), require('ui.readouts').sample(), 280, 18, context);
    MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, nil, nil;
    same_rect(frame(true, mode .. ' closes after preview measurements'), live, 'Bounds and inline previews cannot replace the real bar rectangle');
    same(bar, unchanged, 'Preview measurements leave saved placement unchanged');
    bar.height = bar.height + 10;
    local taller = frame(true, mode .. ' changes height while chat is closed');
    equal(taller.x, live.x, 'The height slider keeps held X');
    equal(taller.y, live.y, 'The height slider keeps held Y');
    equal(taller.height, live.height + 10, 'The height slider still changes held height');
    frame(true, mode .. ' holds the changed height');
    MOCK.chat_retained = { x = chat.x, y = chat.y, width = chat.width, height = chat.height,
        windows = { { index = 2, x = live.x, y = live.y, width = live.width, height = live.height } } };
    MOCK.chat_visible = false;
    frame(false, mode .. ' avoids a newly opened second chat window');
    MOCK.chat_retained = nil;
    same_rect(frame(true, mode .. ' second chat no longer blocks the held position'), taller, 'A second chat window never relocates the held bar');
    MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, nil, nil;
    MOCK.chat_windows = { { index = 2, x = taller.x, y = taller.y, width = taller.width, height = taller.height } };
    frame(false, mode .. ' has an unreadable main window beside an overlapping second chat');
    local blocked_preview = hud.draw_inline(app.settings(), app.view(MOCK.now), 280);
    equal(blocked_preview.unavailable, true, 'An inline preview retains known secondary exclusions when main chat is unreadable');
    MOCK.chat_windows = nil;
    same_rect(frame(true, mode .. ' loses the secondary exclusion'), taller, 'Removing a separately reported exclusion restores the exact held rectangle');
    local saved_placement = history.copy(bar);
    MOCK.screen = { 800, 700 };
    local smaller = history.copy(frame(true, mode .. ' viewport shrinks while chat is closed'));
    equal(smaller.width, 800, 'A held rectangle shrinks only enough to fit the viewport');
    equal(smaller.x, 0, 'A held rectangle stays inside the smaller viewport horizontally');
    equal(smaller.y, 700 - taller.height, 'A held rectangle stays inside the smaller viewport vertically');
    same(bar, saved_placement, 'Viewport clamping never changes saved placement');
    MOCK.screen = nil;
    same_rect(frame(true, mode .. ' viewport expands again'), smaller, 'Expanding the viewport keeps the last drawn rectangle');
    hud.reset_chat_anchor();
    local reset = frame(true, mode .. ' resets the runtime anchor');
    equal(reset.x, bar.x, 'Reset clears the prior chat X');
    equal(reset.y, bar.y, 'Reset clears the prior chat Y');
    MOCK.chat, MOCK.chat_visible = chat, true;
    frame(true, mode .. ' redraws chat after runtime reset');
    app.settings().bar = history.copy(saved_bar);
    bar = app.settings().bar;
    bar.x, bar.y, bar.width, bar.docked = 70, 240, 430, true;
    MOCK.chat, MOCK.chat_visible = nil, nil;
    local replaced = frame(true, mode .. ' replaces the saved bar');
    equal(replaced.x, 70, 'A replaced bar cannot inherit an old layout X');
    equal(replaced.y, 240, 'A replaced bar cannot inherit an old layout Y');
    equal(replaced.width, 430, 'A replaced bar cannot inherit an old layout width');
    command('free');
    local free = frame(true, mode .. ' explicitly selects Free placement');
    equal(bar.docked, false, 'Free placement clears the saved docking choice');
    same_rect(free, replaced, 'Free placement starts at the currently visible rectangle');
    bar.x, bar.y, bar.width = 100, 210, 480;
    free = frame(true, mode .. ' changes its free position and width');
    equal(free.x, 100, 'Free X stays editable without chat');
    equal(free.y, 210, 'Free Y stays editable without chat');
    equal(free.width, 480, 'Free width stays editable without chat');
    MOCK.chat, MOCK.chat_visible = chat, true;
    same_rect(frame(true, mode .. ' reopens chat beside a free bar'), free, 'Reopening chat cannot pull a free bar back to the held anchor');

    app.settings().bar = history.copy(saved_bar);
    bar = app.settings().bar;
    bar.docked, bar.anchor, bar.height = true, 'bottom', 120;
    local constrained = history.copy(frame(true, mode .. ' constrains a tall bar below chat'));
    check(constrained.height < 120 and constrained.height >= 12, 'Live chat limits the height to available space');
    MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, nil, nil;
    same_rect(frame(true, mode .. ' holds the constrained height'), constrained, 'Closing chat preserves the actually drawn height');
    bar.height = 12;
    equal(frame(true, mode .. ' selects minimum height while held').height, 12, 'The height slider sets its exact value after a constrained dock');
    app.settings().bar = saved_bar;
end

-- Resizing a temporary free bar uses its visible bottom edge, even with Above chat saved.
local imgui = require('imgui');
local activated, dragging = false, false;
local item_activated, item_active = imgui.IsItemActivated, imgui.IsItemActive;
imgui.IsItemActivated = function() return activated; end;
imgui.IsItemActive = function() return dragging; end;
local placement = history.copy(app.settings().bar);
for _, mode in ipairs({ 'keep', 'always' }) do
    app.settings().bar = history.copy(placement);
    local bar = app.settings().bar;
    app.settings().visibility.mode, bar.docked, bar.anchor = mode, true, 'top';
    MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, false, nil;
    local fallback = history.copy(frame(true, mode .. ' resize starts from temporary free placement'));
    local saved_bar = history.copy(bar);
    MOCK.key_shift, MOCK.mouse_down, activated, dragging = true, true, true, true;
    MOCK.mouse_x, MOCK.mouse_y = fallback.x + fallback.width / 2, fallback.y + fallback.height - 1;
    frame(true, mode .. ' Shift-press without moving');
    same(bar, saved_bar, 'A press alone keeps the saved chat anchor and size');
    MOCK.mouse_down, activated, dragging = false, false, false;
    frame(true, mode .. ' Shift-release without moving');
    same(bar, saved_bar, 'A click without movement never detaches the saved chat anchor');
    MOCK.mouse_down, activated, dragging = true, true, true;
    frame(true, mode .. ' begins bottom-edge resize');
    activated = false;
    MOCK.mouse_y = MOCK.mouse_y + 12;
    frame(true, mode .. ' drags the visible bottom edge down');
    equal(bar.docked, false, 'An actual resize detaches the temporary free bar');
    equal(bar.y, fallback.y, 'Bottom-edge resizing keeps the free top position fixed');
    equal(bar.height, fallback.height + 12, 'Dragging down makes the free bar taller');
    equal(bar.width, saved_bar.width, 'Vertical resizing preserves the chosen width');
    MOCK.key_shift, MOCK.mouse_down, dragging = false, false, false;
    local resized = frame(true, mode .. ' finishes bottom-edge resize');
    equal(resized.y, fallback.y, 'The completed resize keeps its visible top position');
    equal(resized.height, fallback.height + 12, 'The completed resize keeps its new height');
end

-- Losing or regaining a chat anchor ends a held resize at its last valid size.
for _, mode in ipairs({ 'keep', 'always' }) do
    for _, transition in ipairs({ 'fallback', 'hidden' }) do
        app.settings().bar = history.copy(placement);
        local bar = app.settings().bar;
        app.settings().visibility.mode, bar.docked, bar.anchor = mode, true, 'top';
        MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = chat, true, nil;
        local anchored = history.copy(frame(true, mode .. ' starts anchored resize before ' .. transition));
        MOCK.key_shift, MOCK.mouse_down, activated, dragging = true, true, true, true;
        MOCK.mouse_x, MOCK.mouse_y = anchored.x + anchored.width / 2, anchored.y + 1;
        frame(true, mode .. ' presses anchored top edge');
        activated = false;
        MOCK.mouse_y = MOCK.mouse_y - 6;
        frame(true, mode .. ' resizes before losing its anchor');
        equal(bar.height, anchored.height + 6, 'The resize first changes the valid anchored bar');
        local saved_bar = history.copy(bar);
        if transition == 'fallback' then
            MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, nil, nil;
        else
            MOCK.chat = { x = chat.x, y = 5, width = chat.width, height = chat.height, windows = {} };
        end
        MOCK.mouse_y = MOCK.mouse_y - 8;
        frame(transition == 'fallback', mode .. ' loses anchor space while mouse is held');
        same(bar, saved_bar, 'Losing the visible anchor never applies the old resize delta');
        MOCK.chat, MOCK.chat_visible = chat, true;
        MOCK.mouse_y = MOCK.mouse_y - 7;
        frame(true, mode .. ' regains anchor while mouse is still held');
        same(bar, saved_bar, 'A returning anchor never resumes the cancelled resize');
        MOCK.key_shift, MOCK.mouse_down, activated, dragging = false, false, false, false;
        frame(true, mode .. ' releases after anchor transition');
        same(bar, saved_bar, 'Releasing retains the last valid size and docking choice');
    end

    app.settings().bar = history.copy(placement);
    local bar = app.settings().bar;
    app.settings().visibility.mode, bar.docked, bar.anchor = mode, true, 'top';
    MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, false, nil;
    local fallback = history.copy(frame(true, mode .. ' starts fallback press before chat reopens'));
    local saved_bar = history.copy(bar);
    MOCK.key_shift, MOCK.mouse_down, activated, dragging = true, true, true, true;
    MOCK.mouse_x, MOCK.mouse_y = fallback.x + fallback.width / 2, fallback.y + fallback.height - 1;
    frame(true, mode .. ' presses fallback bottom edge');
    activated = false;
    MOCK.chat, MOCK.chat_visible = chat, true;
    MOCK.mouse_y = MOCK.mouse_y + 10;
    frame(true, mode .. ' chat reopens before fallback resize begins');
    same(bar, saved_bar, 'Reopening chat cancels the fallback press before it can detach the bar');
    MOCK.mouse_y = MOCK.mouse_y + 5;
    frame(true, mode .. ' holds mouse after returning to chat');
    same(bar, saved_bar, 'A held mouse cannot restart the cancelled fallback resize');
    MOCK.key_shift, MOCK.mouse_down, activated, dragging = false, false, false, false;
    frame(true, mode .. ' releases after fallback press');
    same(bar, saved_bar, 'Releasing a cancelled fallback press preserves the saved placement');

    app.settings().bar = history.copy(placement);
    bar = app.settings().bar;
    bar.docked, bar.anchor = true, 'top';
    local anchored = history.copy(frame(true, mode .. ' starts normal anchored width resize'));
    MOCK.key_shift, MOCK.mouse_down, activated, dragging = true, true, true, true;
    MOCK.mouse_x, MOCK.mouse_y = anchored.x + anchored.width - 1, anchored.y + anchored.height / 2;
    frame(true, mode .. ' presses anchored right edge');
    activated = false;
    MOCK.mouse_x = MOCK.mouse_x + 20;
    frame(true, mode .. ' first width movement detaches normally');
    equal(bar.docked, false, 'An intentional width resize still detaches from chat');
    equal(bar.width, anchored.width + 20, 'The first width movement applies');
    MOCK.mouse_x = MOCK.mouse_x + 15;
    frame(true, mode .. ' continues width resize after intentional detach');
    equal(bar.width, anchored.width + 35, 'Intentional detachment does not cancel a continuing width resize');
    MOCK.key_shift, MOCK.mouse_down, activated, dragging = false, false, false, false;
    frame(true, mode .. ' releases normal width resize');
    equal(bar.width, anchored.width + 35, 'Releasing retains the complete width change');
end
imgui.IsItemActivated, imgui.IsItemActive = item_activated, item_active;
MOCK.mouse_x, MOCK.mouse_y = -1, -1;
app.settings().bar = placement;

MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = chat, true, nil;
app.settings().bar.docked = false;
for _, mode in ipairs({ 'chat', 'keep', 'always' }) do
    app.settings().visibility.mode = mode;
    for _, cause in ipairs({ 'typing', 'map', 'event', 'game_ui', 'idle' }) do
        MOCK.typing = cause == 'typing';
        hiding = { [cause] = true };
        app.settings().tracking.hide_idle = cause == 'idle';
        frame(mode == 'always', mode .. ' with ' .. cause);
        MOCK.typing, hiding, app.settings().tracking.hide_idle = false, {}, false;
    end
    command('hide');
    frame(false, mode .. ' respects manual hide');
    command('show');
    frame(true, mode .. ' responds to manual show');
end

app.settings().visibility.mode = 'chat';
MOCK.chat, MOCK.chat_visible = nil, false;
MOCK.player.status = 1;
command();
frame(false, 'Settings open while combat chat is hidden');
equal(configs, 1, 'Hidden chat never prevents drawing settings');
equal(app.settings().window.open, true, 'Settings stay open for editing');
MOCK.key_escape = true;
frame(false, 'Escape closes settings while combat chat is hidden');
equal(app.settings().window.open, false, 'Escape closes on its first frame');
equal(configs, 0, 'Closed settings are not drawn');
MOCK.key_escape, MOCK.player.status = false, 0;

local function award(amount, chain)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, MOCK.player.server_id);
    MOCK.put(bytes, 8, 4, MOCK.player.server_id);
    MOCK.put(bytes, 16, 4, amount);
    MOCK.put(bytes, 20, 4, chain);
    MOCK.put(bytes, 24, 2, 8);
    MOCK.fire('packet_in', MOCK.packet(0x02D, bytes));
    MOCK.player.exp = MOCK.player.exp + amount;
end
award(200, 2);
frame(false, 'Hidden bar observes an EXP chain');
local before = app.view(MOCK.now);
check(before.chain_left > 0, 'An observed chain has a live deadline');
check(before.rings.available and #before.rings.entries == 1, 'Ring recast fixture is readable');
local chain_deadline = MOCK.now + before.chain_left;
award(100, 0);
frame(false, 'Session continues while the bar is hidden', 3);
local after = app.view(MOCK.now);
equal(after.session_exp, before.session_exp + 100, 'Hidden bar continues recording EXP');
check(after.elapsed > before.elapsed, 'Hidden bar keeps session time running');
equal(after.paused, false, 'Hiding never pauses the session');
close(after.chain_left + MOCK.now, chain_deadline, 'Hiding preserves the EXP-chain deadline');
close(after.food_seconds + MOCK.now, effect_deadline, 'Hidden food timer keeps counting down');
close(after.dedication_seconds + MOCK.now, effect_deadline, 'Hidden Dedication timer keeps counting down');
close(after.rings.entries[1].recast + MOCK.now, ring_deadline, 'Hidden EXP ring recast keeps counting down');
MOCK.chat, MOCK.chat_visible = chat, true;
frame(true, 'Chat reopens after gains while hidden');
equal(app.view(MOCK.now).session_exp, after.session_exp, 'Showing the bar preserves hidden-session gains');

app.settings().visibility.mode = 'keep';
check(app.services.save_profile('Chat visibility'), 'Visibility preference can be saved in a profile');
app.settings().visibility.mode = 'chat';
check(app.services.load_profile('Chat visibility'), 'Visibility profile can be restored');
equal(app.settings().visibility.mode, 'keep', 'Profile restores its visibility choice');
app.services.save();
frame(true, 'Visibility settings save');
equal(MOCK.settings.last_saved.visibility.mode, 'keep', 'Character settings save the preference');
MOCK.fire('unload');
MOCK.settings_file = history.copy(MOCK.settings.last_saved);
MOCK.load_addon();
MOCK.fire('load');
app = MOMENTUM_TEST;
equal(app.settings().visibility.mode, 'keep', 'Reload retains the saved preference');
MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, false, nil;
frame(true, 'Reloaded keep-visible bar needs no previously seen chat');

local store = require('core.file_store');
local shared_file = MOCK_INSTALL_PATH .. '/config/addons/momentum/shared_layout.json';
MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = chat, true, nil;
for _, docked in ipairs({ false, true }) do
    for _, entry in ipairs(migration_cases) do
        check(app.services.shared(false), 'Shared migration starts from character settings');
        app.settings().visibility.mode = 'always';
        local shared = { bar = { docked = docked }, visibility = { mode = entry.value, map = false } };
        if entry.whole then shared.visibility = nil; end
        check(store.write(shared_file, { enabled = true, layout = shared }), 'Legacy shared layout is written to the test folder');
        frame(true, 'Shared layout refreshes with ' .. entry.name, 2.1);
        equal(app.settings().shared, true, 'The refreshed shared layout is active');
        equal(app.settings().visibility.mode, entry.value == 'placement' and docked and 'chat' or 'keep',
            'Shared ' .. entry.name .. ' uses the current default or legacy placement');
        if not entry.whole then equal(app.settings().visibility.map, false, 'Shared migration preserves its other hide choices'); end
    end
    for _, value in ipairs({ 'chat', 'keep', 'always' }) do
        check(app.services.shared(false), 'Explicit shared visibility starts from character settings');
        local shared = { bar = { docked = docked }, visibility = { mode = value } };
        check(store.write(shared_file, { enabled = true, layout = shared }), 'Explicit shared layout is written to the test folder');
        frame(true, 'Shared layout refreshes with explicit ' .. value, 2.1);
        equal(app.settings().visibility.mode, value, 'Shared layouts preserve each explicit choice with either placement');
    end
end
for _, value in ipairs({ 'chat', 'keep', 'always' }) do
    check(app.services.shared(false), 'Partial shared layout starts from character settings');
    app.settings().visibility.mode = value;
    check(store.write(shared_file, { enabled = true, layout = { style = { font_size = 15 } } }), 'Style-only shared layout is written');
    frame(true, 'Shared layout changes style only', 2.1);
    equal(app.settings().visibility.mode, value, 'A shared style-only layout preserves the character visibility choice');
end
check(app.services.shared(false), 'The shared migration checks restore character settings');
equal(#MOCK.commands, 0, 'Visibility controls send no gameplay commands');
return { count = count };
