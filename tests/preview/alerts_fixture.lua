local imgui = require('imgui');
local history = require('ui.history');
local settings = PREVIEW.settings;
local ids = {};
PREVIEW.alert_sections, PREVIEW.alert_widgets, PREVIEW.alert_headers = {}, {}, {};
PREVIEW.notification_calls = 0;
if PREVIEW.alert_case == 'notification' then
    settings.alerts.events.level.file = 'Custom.wav';
    settings.alerts.events.level.volume = 37;
    settings.alerts.events.level.cooldown = 12;
    PREVIEW.scroll_target = 'header/Levels and merit points';
elseif PREVIEW.alert_case == 'search' then
    PREVIEW.scroll_target = 'header/EXP chains';
elseif PREVIEW.alert_case == 'counts' then
    settings.alerts.food_enabled = true;
    for _, id in ipairs({ 'food_soon', 'ring_ready', 'level' }) do
        settings.alerts.events[id].visual, settings.alerts.events[id].sound = true, true;
    end
    for _, id in ipairs({ 'dedication_end', 'merit', 'no_exp' }) do settings.alerts.events[id].visual = true; end
    for _, id in ipairs({ 'chain_soon', 'cap' }) do settings.alerts.events[id].sound = true; end
end
PREVIEW.alerts_before = history.copy(settings.alerts);
local test = PREVIEW.services.notification_test;
PREVIEW.services.notification_test = function(id)
    PREVIEW.notification_calls = PREVIEW.notification_calls + 1;
    return test(id);
end;
local begin = imgui.Begin;
imgui.Begin = function(name, ...)
    if name == 'Momentum##settings' then PREVIEW.alert_sections, PREVIEW.alert_widgets, PREVIEW.alert_headers = {}, {}, {}; end
    return begin(name, ...);
end;
local push, pop = imgui.PushID, imgui.PopID;
imgui.PushID = function(id, ...)
    ids[#ids + 1] = tostring(id);
    return push(id, ...);
end;
imgui.PopID = function(...)
    ids[#ids] = nil;
    return pop(...);
end;
local header = imgui.CollapsingHeader;
imgui.CollapsingHeader = function(label, ...)
    local open = header(label, ...);
    local key = label:match('##section_Alerts/(.*)');
    if key then
        PREVIEW.alert_sections[key] = open;
        PREVIEW.alert_headers[key] = label;
        if PREVIEW.scroll_target == 'header/' .. key then imgui.SetScrollHereY(0); end
    end
    return open;
end;
for _, name in ipairs({ 'Checkbox', 'Button', 'BeginCombo', 'SliderFloat' }) do
    local original = imgui[name];
    imgui[name] = function(label, ...)
        local result = original(label, ...);
        local key = (#ids > 0 and table.concat(ids, '/') .. '/' or '') .. label;
        PREVIEW.alert_widgets[key] = true;
        if PREVIEW.scroll_target == key then imgui.SetScrollHereY(0.2); end
        return result;
    end;
end
function PREVIEW.assert_alert_count(group, count)
    local label = assert(PREVIEW.alert_headers[group], 'Missing alert header: ' .. group);
    assert(label:find('(' .. count .. ' on)', 1, true), 'Wrong enabled count: ' .. label);
    assert(label:find('###section_Alerts/' .. group, 1, true), 'Count changed the stable group ID: ' .. label);
end
function PREVIEW.assert_alert_counts(counts)
    for group, count in pairs(counts) do PREVIEW.assert_alert_count(group, count); end
    local quiet = assert(PREVIEW.alert_headers['Quiet conditions'], 'Missing quiet conditions');
    assert(not quiet:find(' on)', 1, true), 'Quiet conditions were counted as alerts');
end
function PREVIEW.assert_alerts_unchanged()
    assert(history.equal(settings.alerts, PREVIEW.alerts_before), 'Opening, collapsing or searching changed saved alert choices');
    assert(PREVIEW.notification_calls == 0 and not PREVIEW.sound_plays, 'Sound or a notification was tested without an explicit click');
end
