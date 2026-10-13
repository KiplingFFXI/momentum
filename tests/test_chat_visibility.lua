local defaults = require('ui.defaults');
local history = require('ui.history');
local player = require('core.player');
local hud = require('ui.hud');
local window = require('ui.settings_window');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function check(value, label) equal(not not value, true, label); end
local function same(actual, expected, label) equal(history.equal(actual, expected), true, label); end
local function close(actual, expected, label)
    count = count + 1;
    assert(type(actual) == 'number' and math.abs(actual - expected) < 0.000001,
        label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

equal(defaults.make().visibility.mode, 'placement', 'Existing placement behavior remains the default');
for _, value in ipairs({ 'placement', 'chat', 'keep', 'always' }) do
    local settings = defaults.make();
    settings.visibility.mode = value;
    defaults.tidy(settings);
    equal(settings.visibility.mode, value, 'Supported visibility choice survives validation');
end
for _, value in ipairs({ '', 'invalid', 1, false, {} }) do
    local settings = defaults.make();
    settings.visibility.mode = value;
    defaults.tidy(settings);
    equal(settings.visibility.mode, 'placement', 'Invalid visibility choice preserves the old behavior');
end
local old_settings = defaults.make();
old_settings.visibility.mode = nil;
old_settings.visibility.map = false;
defaults.tidy(old_settings);
equal(old_settings.visibility.mode, 'placement', 'Older settings gain the existing placement behavior');
equal(old_settings.visibility.map, false, 'Older hide choices are retained');

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
dofile(ADDON_DIR .. '/momentum.lua');
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
for _, mode in ipairs({ 'placement', 'chat', 'keep', 'always' }) do
    for _, docked in ipairs({ false, true }) do
        app.settings().visibility.mode, app.settings().bar.docked = mode, docked;
        local saved_bar = history.copy(app.settings().bar);
        for _, state in ipairs({ 'open', 'closed', 'unknown' }) do
            MOCK.chat = state == 'open' and chat or nil;
            if state == 'open' then MOCK.chat_visible = true;
            elseif state == 'closed' then MOCK.chat_visible = false;
            else MOCK.chat_visible = nil; end
            MOCK.chat_retained = chat;
            local visible = mode == 'keep' or mode == 'always' or state == 'open'
                or not docked and (mode == 'placement' or state == 'unknown');
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
        same(frame(true, mode .. ' retains ' .. anchor .. ' anchor'), live, 'Closed chat keeps the last checked anchor');
        MOCK.chat_retained = nil;
        local fallback = frame(true, mode .. ' has no previous chat bounds');
        equal(fallback.x, saved_bar.x, 'Unknown anchor uses the saved free X position');
        equal(fallback.y, saved_bar.y, 'Unknown anchor uses the saved free Y position');
        equal(fallback.width, saved_bar.width, 'Unknown anchor uses the saved free width');
        same(bar, saved_bar, 'Temporary free display preserves the selected chat anchor');
        MOCK.chat, MOCK.chat_visible = { x = 40, y = 450, width = 750, height = 380, windows = {} }, true;
        local restored = frame(true, mode .. ' follows reopened chat');
        equal(restored.x, 40, 'Reopened chat restores current horizontal alignment');
        equal(restored.width, 750, 'Reopened chat restores current width');
        equal(restored.y, anchor == 'top' and 430 or 832, 'Reopened chat restores the selected edge');
        same(bar, saved_bar, 'Reopening chat does not overwrite saved free placement');
    end
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
for _, mode in ipairs({ 'placement', 'chat', 'keep', 'always' }) do
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
app.settings().visibility.mode = 'placement';
check(app.services.load_profile('Chat visibility'), 'Visibility profile can be restored');
equal(app.settings().visibility.mode, 'keep', 'Profile restores its visibility choice');
app.services.save();
frame(true, 'Visibility settings save');
equal(MOCK.settings.last_saved.visibility.mode, 'keep', 'Character settings save the preference');
MOCK.fire('unload');
MOCK.settings_file = history.copy(MOCK.settings.last_saved);
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
app = MOMENTUM_TEST;
equal(app.settings().visibility.mode, 'keep', 'Reload retains the saved preference');
MOCK.chat, MOCK.chat_visible, MOCK.chat_retained = nil, false, nil;
frame(true, 'Reloaded keep-visible bar needs no previously seen chat');
equal(#MOCK.commands, 0, 'Visibility controls send no gameplay commands');
return { count = count };
