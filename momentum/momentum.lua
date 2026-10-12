addon.name = 'momentum';
addon.author = 'Kipling';
addon.version = '1.0.0';
addon.desc = 'A movable EXP, chain and merit tracking bar for Phoenix.';

require('common');
local ffi = require('ffi');
local bit = require('bit');
local imgui = require('imgui');
local settings = require('settings');
local defaults = require('ui.defaults');
local history = require('ui.history');
local profiles = require('ui.profiles');
local store = require('core.file_store');
local player = require('core.player');
local chat_window = require('core.chat');
local packets = require('core.packets');
local tracker_module = require('core.tracker');
local tracker = tracker_module.new();
local sessions = require('core.sessions');
local phoenix_status = require('core.phoenix_status');
local phoenix = phoenix_status.new();
local rings = require('core.rings');
local notifications = require('core.notifications').new();
local food = require('core.food').new();
local sound = require('core.sound');
local fonts = require('ui.fonts');
local hud = require('ui.hud');
local layout = require('ui.layout');
local window = require('ui.settings_window');
local readouts = require('ui.readouts');
local migrate = require('ui.migrate');
local job_icons = require('ui.job_icons');
pcall(ffi.cdef, 'short __stdcall GetAsyncKeyState(int vKey);');

local folder = AshitaCore:GetInstallPath() .. '\\config\\addons\\momentum\\';
local shared_file = folder .. 'shared_layout.json';
local saved_profiles = profiles.new(folder);
local saved_sessions = sessions.new(folder .. 'sessions.json', { write = function(path, data)
    ashita.fs.create_dir(folder);
    return store.write(path, data);
end });
local undo = history.new();
local migration_pending = false;
local function tidy(value)
    defaults.tidy(value);
    local changed = migrate.apply(value, defaults.make());
    migration_pending = migration_pending or changed;
    return changed;
end

local function own_settings(loaded)
    -- Missing sections can share the library's defaults with the next character.
    for key, value in pairs(loaded) do
        if (type(value) == 'table') then loaded[key] = history.copy(value); end
    end
    tidy(loaded);
    return loaded;
end

local state = { own = own_settings(settings.load(T(defaults.make()))), hidden = false, broken = false, dirty = false,
    sampled = -1, shared_at = -1, last_job = nil, shared_data = nil };
state.settings = state.own;
state.dirty = migration_pending;

local function now() return tonumber(ashita.time.get_tick64()) / 1000; end
local function say(text) print('[Momentum] ' .. tostring(text)); end

local function session_result(ok, problem)
    if not ok and problem and state.session_error ~= problem then say(problem); end
    state.session_error = not ok and problem or nil;
    return ok, problem;
end

local function checkpoint(t, force)
    if not force and not saved_sessions:checkpoint_due(t) then return state.session_error == nil, state.session_error; end
    return session_result(saved_sessions:checkpoint(t, force));
end

local function current_view(t)
    local view = tracker:view(t, state.settings);
    for key, value in pairs(phoenix:view(t)) do view[key] = value; end
    phoenix:apply_chain(view, t);
    view.rings = state.rings or { available = false, entries = {} };
    view.notice = notifications:view(t);
    return view;
end

local function ring_demand()
    local s = state.settings;
    if not s.window.open or s.window.tab ~= 'Details' then state.rings_details = false; end
    local alert = s.alerts.events.ring_ready;
    return s.display.enabled.ring == true or alert.visual == true or alert.sound == true or state.rings_details == true;
end

local function refresh_rings(snapshot, t)
    local needed = ring_demand();
    if not needed or not snapshot or not snapshot.valid then
        state.rings, state.rings_at, state.rings_needed = nil, nil, false;
        return;
    end
    if not state.rings_needed or not state.rings_at or t < state.rings_at or t - state.rings_at >= 1
        or state.rings_id ~= snapshot.id or state.rings_zone ~= snapshot.zone then
        -- A settings change can request a read between player samples.
        state.rings = rings.read(player.utc() or os.time());
        state.rings_at, state.rings_id, state.rings_zone = t, snapshot.id, snapshot.zone;
    end
    state.rings_needed = true;
end

local function quiet_notifications()
    return state.settings.alerts.quiet_events ~= false and player.hidden({ event = true });
end

local function apply_shared(data)
    local old = state.settings;
    local enabled = data.enabled == true and type(data.layout) == 'table';
    if (enabled) then
        local next_settings = history.copy(state.own);
        profiles.apply(next_settings, data.layout);
        next_settings.window, next_settings.job_links = state.own.window, state.own.job_links;
        next_settings.shared = true;
        if tidy(next_settings) then state.dirty = true; end
        state.settings = next_settings;
    else
        state.settings = state.own;
        state.settings.shared = false;
    end
    state.settings.window.open = old.window.open;
    state.shared_data = history.copy(data);
    state.edit_baseline = nil;
    undo:clear();
end

local function refresh_shared()
    local data, err = store.read(shared_file);
    if (data == nil) then
        if (not state.shared_error) then say(err .. ' Check shared_layout.json.'); end
        state.shared_error = true;
        return;
    end
    state.shared_error = false;
    if (not history.equal(data, state.shared_data)) then apply_shared(data); end
end

local function save()
    if (state.retry_at and now() < state.retry_at) then return false; end
    tidy(state.settings);
    state.own.job_links = state.settings.job_links;
    if (state.settings.shared) then
        local current, err = store.read(shared_file);
        if (current == nil) then say(err); state.retry_at = now() + 10; return false; end
        local data = { enabled = true, layout = profiles.capture(state.settings) };
        ashita.fs.create_dir(folder);
        local ok;
        ok, err = store.write(shared_file, data);
        if (not ok) then say(err); state.retry_at = now() + 10; return false; end
        state.shared_data = history.copy(data);
    end
    local ok, err = pcall(settings.save);
    if (not ok or err == false) then
        say('Could not save settings: ' .. tostring(ok and 'Ashita could not save the settings.' or err));
        state.retry_at = now() + 10;
        return false;
    end
    state.retry_at = nil;
    state.dirty = false;
    return true;
end

local function finish_edit()
    if (state.before ~= nil) then
        if (not history.layout_equal(state.before, state.settings)) then undo:push(state.before); end
        state.before = nil;
    end
    state.edit_baseline = nil;
    if (state.dirty) then save(); end
end

local function close_window()
    state.settings.window.open = false;
    state.rings_details = false;
    window.close();
    hud.cancel_layout_gesture();
    state.dirty = true;
    finish_edit();
end

local function update_auto_layout()
    local s = state.settings;
    if not s.display.auto_layout then state.auto_layout = nil; return; end
    local snapshot = state.snapshot;
    local mode = tracker_module.earning_mode(snapshot);
    if not mode then return; end
    local previous = state.auto_layout;
    if previous and previous.settings == s and previous.id == snapshot.id and previous.job == snapshot.job and previous.mode == mode then return; end
    if imgui.IsMouseDown(ImGuiMouseButton_Left) or imgui.IsAnyItemActive() then return; end
    if state.before or state.dirty then
        finish_edit();
        if state.dirty then return; end
    end
    local name = mode == 'lp' and 'Merits' or 'Leveling';
    defaults.apply_starter(s, name);
    -- Rebase an idle editor so this automatic switch is not a saved edit.
    if state.edit_baseline then defaults.apply_starter(state.edit_baseline, name); end
    state.auto_layout = { settings = s, id = snapshot.id, job = snapshot.job, mode = mode };
end

local function change(callback)
    finish_edit();
    hud.cancel_layout_gesture();
    local before = history.copy(state.settings);
    local ok, err = callback(state.settings);
    if (ok == false) then if (err) then say(err); end; return false; end
    tidy(state.settings);
    if (not history.equal(before, state.settings)) then
        if (not history.layout_equal(before, state.settings)) then undo:push(before); end
        state.dirty = true;
        save();
    end
    state.handled = true;
    return true;
end

local services = {};
services.save = function() state.dirty = true; end;
services.undo = function()
    finish_edit();
    if (undo:undo(state.settings)) then
        tidy(state.settings);
        state.dirty = true;
        save();
    end
    state.handled = true;
end;
services.can_undo = function() return #undo.entries > 0; end;
services.reset = function()
    return change(function(s)
        local window_settings, links, shared = s.window, s.job_links, s.shared;
        history.replace(s, defaults.make());
        s.window, s.job_links, s.shared = window_settings, links, shared;
    end);
end;
services.reset_section = function(section)
    return change(function(s)
        local fresh = defaults.make();
        if (fresh[section] ~= nil and section ~= 'window' and section ~= 'job_links') then s[section] = fresh[section]; end
        if (section == 'tracking') then s.visibility, s.display.mode = fresh.visibility, fresh.display.mode; end
    end);
end;
local profile_names, profile_names_at;
services.profile_names = function(force)
    local t = now();
    if force or not profile_names_at or t < profile_names_at or t - profile_names_at >= 1 then
        profile_names, services.profile_error = saved_profiles:names();
        profile_names_at = t;
    end
    return profile_names;
end;
services.save_profile = function(name)
    finish_edit();
    local ok, err = saved_profiles:save(name, state.settings);
    profile_names_at = nil;
    if (not ok) then say(err); end
    return ok, err;
end;
services.load_profile = function(name)
    return change(function(s)
        local ok, problem = saved_profiles:load(name, s);
        if ok then state.auto_layout = nil; end
        return ok, problem;
    end);
end;
services.delete_profile = function(name)
    local ok, err = saved_profiles:delete(name);
    profile_names_at = nil;
    if (not ok) then say(err); end
    return ok, err;
end;
services.job_link = function(job, name)
    return change(function(s)
        s.job_links[tostring(job)] = name ~= '' and name or nil;
        state.own.job_links = s.job_links;
    end);
end;
services.shared = function(enabled)
    finish_edit();
    local current, err = store.read(shared_file);
    if (current == nil) then say(err); return false, err; end
    local data = { enabled = enabled == true, layout = profiles.capture(state.settings) };
    ashita.fs.create_dir(folder);
    local ok;
    ok, err = store.write(shared_file, data);
    if (not ok) then say(err); return false, err; end
    if (not enabled) then profiles.apply(state.own, data.layout); end
    apply_shared(data);
    state.dirty, state.handled = true, true;
    save();
    return true;
end;
services.copy = function(text) imgui.SetClipboardText(text); end;
services.session_pause = function(paused)
    tracker:pause(now(), paused);
    notifications:set_paused(tracker.paused);
    checkpoint(now(), true);
end;
services.session_new = function(name)
    if name == '' then name = nil; end
    local next_tracker, problem = saved_sessions:new_session(now(), name);
    if not next_tracker then return session_result(false, problem); end
    tracker = next_tracker;
    notifications:reset_session(current_view(now()));
    if state.settings.preview.show then
        state.settings.preview.show = false;
        state.dirty = true;
    end
    window.use_live_preview();
    return session_result(problem == nil, problem);
end;
services.session_reset = function() return services.session_new(); end;
services.session_save = function(name)
    local current = saved_sessions:current();
    if not current then return false, 'Wait for your EXP and LP to load before saving a session.'; end
    if name and name ~= '' then
        local ok, problem = saved_sessions:rename(current.id, name);
        if not ok then return session_result(ok, problem); end
    end
    return checkpoint(now(), true);
end;
services.session_list = function() return saved_sessions:list(state.player_id); end;
services.session_history = function() return saved_sessions:history(state.player_id); end;
services.session_current = function() return saved_sessions:current(); end;
services.session_rename = function(id, name) return session_result(saved_sessions:rename(id, name)); end;
services.session_delete = function(id) return session_result(saved_sessions:delete(id)); end;
services.session_problem = function() return saved_sessions:problem(); end;
services.sync_plan = phoenix_status.plan;
services.sync_tiers = function() return phoenix_status.tiers; end;
services.fonts = fonts.names;
services.capabilities = player.capabilities;
services.sound_files = sound.files;
services.sound_refresh = sound.refresh;
services.sound_problem = function() return sound.problem(state.settings.alerts.food_sound); end;
services.dock_problem = function() return state.dock_problem; end;
services.chat_width = function() return state.chat_width; end;
services.preview_context = function() return { chat = state.chat, chat_checked = true, now = now() }; end;
services.rings_visible = function(open)
    state.rings_details = open == true;
    refresh_rings(state.snapshot, now());
    return state.rings;
end;
services.placement = function(mode)
    return change(function(s)
        local display = imgui.GetIO().DisplaySize;
        local context = { chat = chat_window.read(display.x, display.y), preview = s.preview.show };
        local view = s.preview.show and readouts.sample(s.preview.scenario) or current_view(now());
        return hud.place(s, view, context, mode);
    end);
end;

local function play_food_sound(retry)
    local alerts = state.settings.alerts;
    if (alerts.food_sound == '') then return false, 'Pick a sound first.'; end
    if (sound.use(alerts.food_sound, retry) and sound.play(alerts.food_volume)) then return true; end
    return false, sound.problem(alerts.food_sound) or 'That sound could not play. Try another file.';
end

services.sound_play = function()
    local ok, err = play_food_sound(true);
    if (not ok) then say(err); end
    return ok, err;
end;

services.notification_test = function(id)
    local row = state.settings.alerts.events[id];
    state.notification_problems = state.notification_problems or {};
    local problem;
    if not row or (not row.visual and not row.sound) then
        problem = 'Check Show notice or Play sound to test this alert.';
    else
        if row.visual then
            local label = id;
            for _, event in ipairs(defaults.ALERTS) do if event[1] == id then label = event[2]; end end
            notifications:preview(id, 'Test: ' .. label, now());
        end
        if row.sound then
            if row.file == '' then problem = 'Pick a sound first.';
            elseif not (sound.use(row.file, true) and sound.play(row.volume)) then
                problem = sound.problem(row.file) or 'That sound could not play. Try another file.';
            end
        end
    end
    state.notification_problems[id] = problem;
    return problem == nil, problem;
end;
services.notification_problem = function(id)
    local row = state.settings.alerts.events[id];
    return state.notification_problems and state.notification_problems[id] or row and sound.problem(row.file) or nil;
end;

local function apply_alerts()
    local alerts = state.settings.alerts;
    if (state.food_enabled ~= alerts.food_enabled or state.food_sound ~= alerts.food_sound) then
        sound.close();
        if (state.food_enabled ~= alerts.food_enabled) then food:discontinuity(); end
        state.food_pending = nil;
        state.food_enabled, state.food_sound = alerts.food_enabled, alerts.food_sound;
        if (alerts.food_enabled) then sound.use(alerts.food_sound, true); end
    end
end

local function sample(t)
    local snapshot = player.read();
    state.award_ready = false;
    if snapshot.valid then
        local selected, _, ready = saved_sessions:select(snapshot, t, state.settings);
        tracker, state.award_ready = selected, ready == true;
        if not state.award_ready then snapshot = { valid = false }; end
    end
    tracker:observe(snapshot, t);
    phoenix:observe(snapshot, t);
    refresh_rings(snapshot, t);
    notifications:observe(current_view(t), snapshot, t, state.settings, quiet_notifications());
    state.snapshot = snapshot;
    apply_alerts();
    food:observe(snapshot, t, state.settings.alerts.food_enabled);
    if (not snapshot.valid) then state.food_pending = nil; end
    if (snapshot.valid) then
        if (state.last_job ~= snapshot.job) then
            state.last_job = snapshot.job;
            local linked = state.settings.job_links[tostring(snapshot.job)];
            if (linked and not state.settings.shared) then services.load_profile(linked); end
        end
        state.player_id = snapshot.id;
    end
end

ashita.events.register('load', 'momentum_load', function()
    fonts.load();
    job_icons.prepare();
    player.load();
    chat_window.load();
    sound.refresh();
    refresh_shared();
    sample(now());
end);

ashita.events.register('packet_in', 'momentum_packets', function(event)
    if (not packets.valid(event, 4)) then return; end
    local t = now();
    local id = packets.zone_id(event);
    if (id) then
        tracker:discontinuity(t);
        phoenix:discontinuity();
        notifications:discontinuity();
        food:discontinuity();
        state.rings, state.rings_at, state.snapshot = nil, nil, nil;
        state.food_pending = nil;
        player.on_zone(id);
        state.player_id, state.sampled = id, -1;
        return;
    end
    if (event.id == 0x061 and packets.valid(event, 96)) then player.on_status(); state.sampled = -1; end
    if (event.id == 0x063) then state.sampled = -1; end
    if (event.id == 0x017) then
        local feed = packets.status(event, state.player_id or player.id());
        if feed then
            sample(t);
            if phoenix:message(feed, t) then
                notifications:confirmed(feed, t, state.settings, quiet_notifications());
                event.blocked = true;
                state.sampled = -1;
            end
        else
            local chain_feed = packets.chain_status(event, state.player_id or player.id());
            if chain_feed then
                sample(t);
                if phoenix:chain_message(chain_feed, t) then
                    event.blocked = true;
                    state.sampled = -1;
                end
            end
        end
    end
    if (event.id == 0x029) then
        local ended = packets.food_end(event, state.player_id);
        if (ended and food:message(ended, t, state.settings.alerts.food_enabled)) then state.food_pending = t; end
        local dedication_ended = packets.dedication_end(event, state.player_id);
        if dedication_ended then
            notifications:message('dedication_end', 'Dedication ended.', t, state.settings, quiet_notifications(), dedication_ended.token);
            phoenix:dedication_end();
        end
        local reason = packets.no_exp(event, state.player_id);
        if reason and phoenix:reason(reason, t) then
            local text = reason.reason == 'distance' and 'Too far away to gain EXP.' or 'No EXP: sync target is dead or out of range.';
            notifications:message('no_exp', text, t, state.settings, quiet_notifications(), reason.token);
        end
    end
    if (event.id == 0x02D or event.id == 0x028) then
        if not packets.reward_candidate(event, player.id()) then return; end
        sample(t);
        local item = packets.item_use(event, state.player_id or player.id());
        if item then
            local resource = AshitaCore:GetResourceManager():GetItemById(item.item_id);
            local name = resource and resource.Name and resource.Name[1];
            if type(name) == 'string' then phoenix:item(item, t, name:gsub('[^ -~]', '')); end
        end
        for _, award in ipairs(packets.awards(event, state.player_id or player.id())) do
            if state.award_ready then tracker:award(award, t); end
            phoenix:award(award, t);
        end
    end
end);

local function render()
    if state.settings.window.open and bit.band(ffi.C.GetAsyncKeyState(0x1B), 0x8000) ~= 0 then
        close_window();
    end
    if state.broken then return; end
    local t = now();
    if (t - state.sampled >= 0.2 or state.food_pending ~= nil) then sample(t); state.sampled = t; end
    apply_alerts();
    if (state.food_pending ~= nil) then
        local recent = t - state.food_pending <= 2;
        state.food_pending = nil;
        if (recent and state.settings.alerts.food_enabled and not quiet_notifications()
            and not (state.settings.alerts.quiet_paused ~= false and tracker.paused)
            and (not state.last_notification_sound or t - state.last_notification_sound >= 1)) then
            local ok, err = play_food_sound(false);
            if ok then state.last_notification_sound = t; end
            if (not ok and state.settings.alerts.food_sound ~= '') then say(err); end
        end
    end
    if (t - state.shared_at >= 2 and not state.dirty and state.before == nil and not state.settings.window.open) then
        refresh_shared();
        state.shared_at = t;
    end
    local quiet = quiet_notifications() or (state.settings.alerts.quiet_paused ~= false and tracker.paused);
    for _, event in ipairs(notifications:take(t, quiet)) do
        local row = state.settings.alerts.events[event.id];
        if row and row.sound and event.sound and event.file ~= '' and not quiet_notifications()
            and not (state.settings.alerts.quiet_paused ~= false and tracker.paused)
            and (not state.last_notification_sound or t - state.last_notification_sound >= 1) then
            if sound.use(event.file, false) and sound.play(event.volume) then state.last_notification_sound = t; end
        end
    end
    checkpoint(t, false);
    update_auto_layout();
    if player.hidden(state.settings.visibility) then hud.cancel_layout_gesture(); finish_edit(); return; end
    local typing = player.typing();
    local hide_idle = state.settings.tracking.hide_idle and tracker:_elapsed(math.max(t, tracker.last_time or t)) == 0;
    local hud_visible = ((not state.hidden and not hide_idle) or state.settings.preview.show)
        and not (state.settings.bar.hide_typing and typing);
    if not hud_visible and not state.settings.window.open then hud.cancel_layout_gesture(); finish_edit(); return; end
    refresh_rings(state.snapshot, t);
    local view = current_view(t);
    local shift = bit.band(ffi.C.GetAsyncKeyState(0x10), 0x8000) ~= 0;
    local context = { shift = shift, typing = typing, now = t, preview = state.settings.preview.show };
    local display = imgui.GetIO().DisplaySize;
    local chat_problem;
    context.chat, chat_problem = chat_window.read(display.x, display.y);
    state.chat = context.chat;
    state.chat_width = context.chat and context.chat.width or nil;
    local dock = layout.dock(state.settings.bar, display.x, display.y, context.chat);
    state.dock_problem = dock.hidden and (chat_problem or dock.reason) or nil;
    local editable = state.settings.window.open or shift;
    if editable and not state.edit_baseline then state.edit_baseline = history.copy(state.settings); end
    local before = editable and state.edit_baseline or nil;
    state.handled = false;
    local changed = false;
    if hud_visible then
        local shown = context.preview and readouts.sample(state.settings.preview.scenario) or view;
        changed = hud.draw(state.settings, shown, context) or changed;
    end
    if (state.settings.window.open) then changed = window.draw(state.settings, view, services) or changed; end
    if (before and not history.equal(before, state.settings)) then changed = true; end
    if (changed and not state.handled) then
        state.before = state.before or before;
        state.dirty = true;
    end
    if (state.dirty and not imgui.IsMouseDown(0) and not imgui.IsAnyItemActive()) then finish_edit(); end
    if not editable or state.handled then state.edit_baseline = nil; end
end

ashita.events.register('d3d_present', 'momentum_present', function()
    local ok, err = pcall(render);
    if (not ok) then
        state.broken = true;
        say('The bar stopped drawing: ' .. tostring(err) .. '. Type /momentum to try again.');
    end
end);

ashita.events.register('command', 'momentum_command', function(event)
    local args = event.command:args();
    if (args[1] == nil or args[1]:lower() ~= '/momentum') then return; end
    event.blocked = true;
    local command = (args[2] or ''):lower();
    if (command == '') then
        if state.settings.window.open then close_window();
        else state.settings.window.open = true; sound.refresh(); end
        state.broken = false;
    elseif (command == 'show') then state.hidden = false;
    elseif (command == 'hide') then state.hidden = true;
    elseif (command == 'lock' or command == 'unlock') then change(function(s) s.bar.locked = command == 'lock'; end);
    elseif (command == 'free') then services.placement('free');
    elseif (command == 'dock') then
        local side = (args[3] or state.settings.bar.anchor):lower();
        if side == 'top' or side == 'bottom' then services.placement(side);
        else say('Use /momentum dock top or /momentum dock bottom.'); end
    elseif (command == 'dockinfo') then say(chat_window.describe());
    elseif (command == 'pause' or command == 'resume') then services.session_pause(command == 'pause');
    elseif (command == 'reset') then if services.session_reset() then say('Previous session saved. New session started.'); end
    elseif (command == 'undo') then services.undo();
    elseif (command == 'preview') then state.settings.preview.show = not state.settings.preview.show;
    elseif (command == 'mode' and (args[3] == 'auto' or args[3] == 'exp' or args[3] == 'lp')) then
        change(function(s) s.display.mode = args[3]; end);
    elseif (command == 'divider' and args[3] ~= nil) then change(function(s) s.display.divider = args[3]; end);
    elseif (command == 'order' and args[3] ~= nil) then
        local known, order, seen = {}, {}, {};
        for _, row in ipairs(defaults.READOUTS) do known[row.id] = true; end
        for i = 3, #args do
            if (not known[args[i]] or seen[args[i]]) then say('Use each readout name once. The order was kept.'); return; end
            order[#order + 1], seen[args[i]] = args[i], true;
        end
        for _, key in ipairs(state.settings.display.order) do if (not seen[key]) then order[#order + 1] = key; end end
        change(function(s) s.display.order = order; end);
    elseif (command == 'profile' and args[4]) then
        local name = table.concat(args, ' ', 4);
        if (args[3] == 'save') then services.save_profile(name);
        elseif (args[3] == 'load') then services.load_profile(name);
        elseif (args[3] == 'delete') then services.delete_profile(name);
        else say('Use profile save, load or delete followed by a name.'); end
    else
        say('Use /momentum for settings. Commands: show, hide, lock, unlock, dock, free, pause, resume, reset, undo, preview, mode, divider, order, profile.');
    end
end);

ashita.events.register('unload', 'momentum_unload', function()
    finish_edit();
    checkpoint(now(), true);
    sound.close();
    job_icons.destroy();
end);
settings.register('settings', 'momentum_settings', function(loaded)
    if (loaded == nil) then return; end
    window.close();
    local detached, session_problem = saved_sessions:detach(now());
    tracker = detached;
    session_result(session_problem == nil, session_problem);
    -- The settings library already selected the new character's file.
    if (state.settings.shared and state.dirty) then
        local existing = store.read(shared_file);
        if (existing ~= nil) then store.write(shared_file, { enabled = true, layout = profiles.capture(state.settings) }); end
    end
    hud.cancel_layout_gesture();
    food:discontinuity();
    phoenix:discontinuity();
    notifications:discontinuity();
    state.rings, state.rings_at, state.rings_details, state.rings_needed, state.snapshot = nil, nil, nil, nil, nil;
    sound.close();
    state.food_pending, state.food_enabled, state.food_sound = nil, nil, nil;
    migration_pending = false;
    state.own = own_settings(loaded);
    state.settings = state.own;
    state.before, state.edit_baseline, state.dirty, state.last_job, state.shared_data = nil, nil, migration_pending, nil, nil;
    state.player_id, state.sampled = nil, -1;
    undo:clear();
    refresh_shared();
end);

if (MOMENTUM_TEST_MODE) then
    MOMENTUM_TEST = { settings = function() return state.settings; end, tracker = function() return tracker; end,
        state = state, services = services, sample = sample, view = current_view,
        sessions = saved_sessions, phoenix = phoenix, notifications = notifications };
end
