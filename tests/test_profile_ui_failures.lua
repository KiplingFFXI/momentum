local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local imgui = require('imgui');
local window = require('ui.settings_window');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local settings = defaults.make();
settings.window.open, settings.window.tab = true, 'Profiles';
local next_open, input, selected, failed = nil, nil, nil, true;
local saves, deletes = 0, 0;
local services = {
    profile_names = function() return { 'Existing' }; end,
    save_profile = function() saves = saves + 1; return not failed, failed and 'Profile file is read-only.' or nil; end,
    delete_profile = function() deletes = deletes + 1; return not failed, failed and 'Profile file is read-only.' or nil; end,
};
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function() return next_open; end;
imgui.BeginCombo = function(label, current)
    if label == '##Profile' then selected = current; return true; end
    return false;
end;
imgui.InputText = function(label, value)
    if label == '##Profile name' and input then value[1], input = input, nil; return true; end
    return false;
end;
local function draw(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end
    window.draw(settings, readouts.sample('Leveling'), services);
end
local function shown(method, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == method and call[2] == label then return true; end end
    return false;
end
draw('Existing');
draw();
eq(selected, 'Existing', 'Existing profile can be selected');
input = 'Unsaved';
draw('Save profile');
draw();
eq(saves, 1, 'New profile is saved only after an explicit click');
eq(selected, 'Existing', 'Failed save does not select an unsaved name');
eq(shown('TextUnformatted', 'Profile file is read-only.'), true, 'Save failure stays visible');
draw('Save profile');
eq(saves, 2, 'Failed new save can be retried directly');
input = 'Existing';
draw('Save profile');
eq(saves, 2, 'Replacing an existing profile still requires confirmation');
draw('Replace saved profile');
draw();
eq(saves, 3, 'Confirmed replacement attempts one write');
eq(shown('Button', 'Replace saved profile'), true, 'Failed replacement keeps its confirmation for retry');
eq(selected, 'Existing', 'Failed replacement keeps the selected profile');
failed = false;
draw('Replace saved profile');
draw();
eq(saves, 4, 'Replacement retry can succeed');
eq(shown('Button', 'Replace saved profile'), false, 'Successful replacement closes confirmation');
failed = true;
draw('Delete profile');
draw('Delete saved profile');
draw();
eq(deletes, 1, 'Confirmed deletion attempts one write');
eq(selected, 'Existing', 'Failed deletion keeps its selected record');
eq(shown('Button', 'Delete saved profile'), true, 'Failed deletion remains retryable');
eq(shown('TextUnformatted', 'Profile file is read-only.'), true, 'Deletion failure remains visible');
failed = false;
draw('Delete saved profile');
draw();
eq(deletes, 2, 'Deletion retry can succeed');
eq(selected, '(choose)', 'Successful deletion clears selection');
eq(shown('Button', 'Delete saved profile'), false, 'Successful deletion closes confirmation');
local refreshes, saved_name = 0, nil;
services.profile_names = function(force)
    if force then refreshes = refreshes + 1; return { 'Outside' }; end
    return {};
end;
services.save_profile = function(name) saves = saves + 1; saved_name = name; return true; end;
input = '  Outside  ';
draw('Save profile');
eq(refreshes, 1, 'Explicit save refreshes profile names before testing replacement');
eq(saves, 4, 'Trimmed existing name from fresh storage still needs confirmation');
eq(shown('Button', 'Replace saved profile'), true, 'Externally created profile shows replacement confirmation');
draw('Replace saved profile');
draw();
eq(saves, 5, 'Confirmed externally created profile can be replaced');
eq(saved_name, 'Outside', 'Confirmed replacement uses the normalized profile name');
eq(selected, 'Outside', 'Selected saved profile uses its normalized name');
services.profile_names = function(force)
    if force then refreshes = refreshes + 1; services.profile_error = 'The profile file could not be read.'; end
    return {};
end;
input = 'Brand new';
draw('Save profile');
eq(saves, 5, 'Failed fresh profile lookup cannot bypass replacement confirmation');
draw();
eq(shown('TextUnformatted', 'The profile file could not be read.'), true, 'Fresh profile lookup error stays visible');
eq(refreshes, 2, 'Only explicit save clicks force profile refresh');
return { count = count };
