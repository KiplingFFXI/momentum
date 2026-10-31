local store = require('core.file_store');
local history = require('ui.history');
local defaults = require('ui.defaults');
local checks = 0;
local function check(value, message)
    checks = checks + 1;
    assert(value, message);
end

MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
check(app.services.shared(true), 'Sharing can be enabled');
local original = store.write;
local blocked, attempts = true, 0;
store.write = function(path, data)
    if path:find('shared_layout.json', 1, true) then
        attempts = attempts + 1;
        if blocked then return false, 'Test shared file is temporarily unavailable'; end
    end
    return original(path, data);
end;
local incoming = defaults.make();
incoming.bar.x, incoming.job_links[1], incoming.window.font_size = 440, 'Private WAR', 21;
app.settings().display.divider = ' pending ';
app.services.save();
MOCK.fire('d3d_present');
check(app.state.dirty and app.state.retry_at ~= nil, 'A failed shared save remains pending');
MOCK.settings.switch_character(history.copy(incoming));
check(app.settings().display.divider == ' pending ', 'The next character sees the pending shared layout');
check(app.settings().job_links[1] == 'Private WAR', 'Pending shared data does not replace private job links');
check(app.settings().window.font_size == 21, 'Pending shared data does not replace private window settings');
check(app.state.dirty and app.state.retry_at ~= nil, 'The retry survives the registered character callback');
local waiting = attempts;
MOCK.frame(1);
check(attempts == waiting, 'A pending save does not retry every frame');

-- New shared edits on the second character must supersede the failed capture.
app.settings().display.divider = ' latest ';
app.services.save();
MOCK.settings.switch_character(history.copy(incoming));
check(app.settings().display.divider == ' latest ', 'Repeated character switches preserve the latest shared edits');
blocked = false;
MOCK.frame(11);
check(not app.state.dirty and app.state.retry_at == nil, 'The pending layout is saved once the file becomes writable');
local path = MOCK_INSTALL_PATH .. '/config/addons/momentum/shared_layout.json';
check(store.read(path).layout.display.divider == ' latest ', 'The latest layout reaches disk');
MOCK.settings.switch_character(history.copy(incoming));
check(app.settings().display.divider == ' latest ', 'Returning loads the successfully recovered shared layout');

check(app.services.shared(false), 'Sharing can be disabled after recovery');
check(app.settings().job_links[1] == 'Private WAR', 'Disabling sharing keeps private links');
store.write = original;
return { count = checks };
