local imgui = require('imgui');
local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local rules = require('data.phoenix_rules');
local details = {};
local history_selected;
local history_name = { '' };
local history_confirmation;
local history_status;
local current_selected;
local current_name = { '' };
local current_status;
local food_sound_status;
local history_cache;

local num, time = readouts.format_number, readouts.format_time;
local function known(value, suffix)
    return type(value) == 'number' and num(value) .. (suffix or '') or 'Unknown';
end

local function row(ui, text, help)
    ui.note(text);
    ui.tip(help);
    ui.help(help);
end

local sync_help = 'Phoenix has to send your current Level Sync penalty before Momentum can show it. Your level difference alone cannot tell us the penalty. EXP/HR already uses the EXP you gain, so you do not need to subtract it again.';

function details.sync_summary(view)
    if view.sync_active == false then return 'Level Sync is off'; end
    if view.sync_active ~= true then return 'Level Sync status unknown'; end
    if view.sync_source == 'server' and type(view.sync_penalty) == 'number' then
        return 'Level Sync penalty: ' .. known(view.sync_penalty, '%');
    end
    return 'Level Sync penalty unknown';
end

local function sync_details(settings, view, services, ui)
    if ui.section('Level sync', sync_help, true) then
        local report_help = sync_help;
        if view.sync_active == true and view.sync_source == 'server' then
            if type(view.sync_age) == 'number' then report_help = report_help .. ' Last updated ' .. time(view.sync_age) .. ' ago.'; end
            if type(view.sync_rate) == 'number' then
                report_help = report_help .. ' Phoenix currently reports ' .. tostring(view.sync_rate / 10)
                    .. '% per level for its population bracket. Your penalty may have been set at a different rate. This does not show how many players are online.';
            end
        end
        row(ui, details.sync_summary(view), report_help);
        if view.sync_active then
            row(ui, 'Your level: ' .. known(view.level) .. '   |   Synced to: ' .. known(view.sync_level or view.effective_level),
                'Your level is your main job\'s level. Synced to is the level you are playing at during Level Sync. The difference is ' .. known(view.sync_gap) .. ' levels.');
            if view.sync_source ~= 'server' or type(view.sync_penalty) ~= 'number' then
                ui.note('Phoenix has not sent your current Level Sync penalty.');
            end
            row(ui, 'EXP/HR already includes your Level Sync penalty.',
                'Both rate calculations use the EXP you actually receive. Do not subtract the Level Sync penalty again.');
        end
        local reasons = {
            sync_target = 'No EXP: Level Sync target unavailable',
            distance = 'No EXP: too far from the monster',
        };
        local reason_help = {
            sync_target = 'Phoenix reported that your Level Sync target was KO\'d or too far from the monster when it died. This explains a recent missed EXP gain.',
            distance = 'Phoenix reported that you were too far from the monster to gain EXP when it died. This explains a recent missed EXP gain.',
        };
        if reasons[view.no_exp_reason] then row(ui, reasons[view.no_exp_reason], reason_help[view.no_exp_reason]); end
    end
    if not ui.section('Advanced sync estimate', 'Try a Level Sync level and an estimated number of players online to see the possible penalty. This does not show your current penalty or the current server population.', false) then return; end
    ui.note('This is an estimate for the choices below, not your current penalty.');
    local maximum = type(view.level) == 'number' and math.min(75, view.level) or 75;
    local planned_level = math.max(10, math.min(maximum, settings.planner.level));
    if settings.planner.level ~= planned_level then settings.planner.level = planned_level; ui.changed(); end
    imgui.BeginDisabled(maximum < 10);
    ui.slider(settings.planner, 'level', 'Level Sync level', 10, math.max(10, maximum));
    ui.help('Choose a level to check. This does not change your party\'s Level Sync.');
    imgui.EndDisabled();
    settings.planner.level = math.floor(settings.planner.level + 0.5);
    ui.pick(settings.planner, 'population', 'Estimated players online', {
        { name = 'Below 500', value = 0 }, { name = '500 to 999', value = 500 },
        { name = '1,000 to 1,999', value = 1000 }, { name = '2,000 or more', value = 2000 },
    }, 'Choose an estimate for how many players are online. Momentum cannot read that count. This choice is only used for this estimate.');
    local planned = services.sync_plan and services.sync_plan(view.level, settings.planner.level, settings.planner.population);
    if type(planned) == 'table' then planned = planned.penalty; end
    row(ui, 'Estimated penalty: ' .. known(planned, '%'),
        'Uses your main job\'s level, the choices above, and Phoenix\'s Level Sync rules. Your current penalty may have been set with different conditions.');
    if maximum < 10 then ui.note('Level Sync is unavailable below level 10.'); end
end

function details.draw(settings, view, services, ui)
    if ui.section('EXP and limit points', 'Your current EXP and limit points (LP), plus what you have gained this session. Both are tracked even when the bar shows only one.', true) then
        for _, kind in ipairs({ 'exp', 'lp' }) do
            local progress = view[kind] or {};
            row(ui, string.upper(kind) .. '  ' .. known(progress.current) .. ' / ' .. known(progress.needed)
                .. '   |   ' .. known(progress.rate) .. '/HR',
                kind == 'lp' and 'LP toward your next merit point. Every 10,000 LP gives you one merit point if you have room for it. Your Tracking settings choose how LP/HR is calculated.'
                    or 'EXP toward your next level. At level 75, this is your EXP buffer. Your Tracking settings choose how EXP/HR is calculated.');
            row(ui, string.upper(kind) .. ' gained ' .. num(view['session_' .. kind]) .. '   |   Net change ' .. num(view['net_' .. kind]),
                'Gained counts EXP or LP awards during this session. Net change also includes losses, Raise recovery, and changes reported by the client. Neither includes gains from before this session.');
        end
    end
    if ui.section('Merit points', 'Stored merit points are ready to spend. LP is your progress toward the next merit point.', true) then
        row(ui, 'Stored merit points: ' .. known(view.merits) .. ' / ' .. known(view.merit_cap)
            .. '   |   Room for: ' .. known(view.merit_headroom),
            'Your unspent merit points and how many you can hold. Spending one makes room for another. Unknown means the client has not sent that number yet.');
        row(ui, 'Merit points gained this session: ' .. num(view.merits_gained),
            'Merit points gained since this session began. Spending them does not lower this count. LP you had before the session can help finish the first point.');
        local progress = view.lp or {};
        row(ui, 'Merit points per hour: ' .. (type(progress.rate) == 'number' and string.format('%.2f', progress.rate / rules.lp_per_merit) or 'Unknown'),
            'Your LP/HR divided by 10,000. This estimates how quickly you are earning merit points. With EXP/LP received selected under Tracking, it can include LP awards you could not keep at the cap.');
        if progress.blocked then
            ui.note(progress.reason or 'Spend some merit points to make room for another.');
        else
            row(ui, 'LP to next merit point: ' .. known(progress.remaining) .. '   |   Time: '
                .. (type(progress.eta) == 'number' and '~' .. time(progress.eta) or '--'),
                'LP needed for your next merit point and the estimated time at your current LP/HR. -- means there is no positive LP/HR yet or your merit point limit is still unknown.');
            if progress.reason then ui.note(progress.reason); end
        end
    end
    sync_details(settings, view, services, ui);
    if ui.section('Food and Dedication', 'Your food effect, Dedication, and time remaining. Hover a value for more information.', true) then
        local food = view.food == false and 'None' or view.food and (view.food_name or 'Active') or 'Unknown';
        local food_time = view.food and type(view.food_seconds) == 'number' and '   |   ' .. time(view.food_seconds) .. ' left' or '';
        row(ui, 'Food: ' .. food .. food_time,
            'Time left on your food effect. Momentum can show the food\'s name only if it was running when you ate it. If you loaded the addon afterward, the name may be unknown.');
        local dedication = view.dedication == nil and 'Unknown' or view.dedication and 'Active' or 'Inactive';
        local dedication_time = view.dedication and type(view.dedication_seconds) == 'number' and '   |   ' .. time(view.dedication_seconds) .. ' left' or '';
        row(ui, 'Dedication: ' .. dedication .. dedication_time,
            'Dedication is the bonus EXP effect from an EXP ring. The status icon tells us it is active, but not which ring you used or how much bonus EXP is left.');
        if view.dedication then
            local pool_known, bonus_known = type(view.dedication_pool) == 'number', type(view.dedication_bonus) == 'number';
            local values = {};
            if pool_known then values[#values + 1] = 'Bonus left: ' .. known(view.dedication_pool); end
            if bonus_known then values[#values + 1] = 'Bonus: ' .. known(view.dedication_bonus, '%'); end
            if #values > 0 then
                row(ui, table.concat(values, '   |   '), 'The bonus EXP left and bonus percentage for your current Dedication effect, as reported by Phoenix.');
            end
            if not pool_known or not bonus_known then
                local missing = not pool_known and (not bonus_known and 'Bonus values' or 'Remaining bonus') or 'Bonus percentage';
                ui.note(missing .. ' unknown. Needs extra Phoenix server support.');
                ui.help('Phoenix must send these numbers through its optional server support. Your Dedication icon and timer cannot tell Momentum how much bonus EXP is left. Unknown does not mean you have none left.');
            end
        end
    end
    local rings_open = ui.section('Owned EXP rings', 'Charges and recast for EXP rings the client can read in your bags. Equip and use your rings yourself.', false);
    local ring_snapshot = services.rings_visible and services.rings_visible(rings_open);
    if rings_open then
        local rings = ring_snapshot or view.rings or {};
        if not rings.available then ui.note('Your EXP rings cannot be read right now.');
        elseif #(rings.entries or {}) == 0 then ui.note('No EXP rings found.');
        else
            if rings.incomplete then ui.note('Some items could not be read. You may have other EXP rings that are not listed.'); end
            for _, ring in ipairs(rings.entries) do
                row(ui, (ring.name or 'EXP ring') .. '   |   ' .. known(ring.charges) .. ' / ' .. known(ring.max_charges) .. ' charges'
                    .. '   |   ' .. (ring.ready and 'Ready' or type(ring.recast) == 'number' and time(ring.recast) .. ' recast' or 'Recast unknown'),
                    'Ready means the ring has charges and its recast has finished. You still need to equip and use it, including the wait after equipping. Only bags the client has loaded can be checked.');
                row(ui, 'Bonus ' .. known(ring.bonus, '%') .. '   |   Cap ' .. known(ring.cap) .. '   |   '
                    .. (type(ring.duration) == 'number' and time(ring.duration) or 'Unknown') .. ' duration',
                    'These are the ring\'s bonus and duration on Phoenix. They do not show how much bonus EXP is left on your current Dedication effect. Wait after equipping: '
                        .. (type(ring.use_delay) == 'number' and time(ring.use_delay) or 'unknown') .. '.');
                if type(ring.equip_delay) == 'number' then
                    row(ui, 'Wait after equipping: ' .. time(ring.equip_delay), 'Time left before you can use the ring after equipping it, when the client can read it.');
                end
            end
        end
    end
    if ui.section('Recent rewards', 'Compare recent EXP or LP gains for the mode you are viewing. A gain does not always mean a monster was defeated.', false) then
        for _, entry in ipairs({ { 'Last 3', view.recent3 }, { 'Last 10', view.recent10 }, { 'Your setting', view.recent } }) do
            local value = entry[2] or {};
            row(ui, entry[1] .. ': ' .. num(value.count) .. ' / ' .. num(value.requested) .. ' gains'
                .. '   |   Average ' .. num(value.average),
                'Only EXP or LP gains seen during this session are counted. Recent gains to average under Tracking sets the count for Your setting.');
            row(ui, 'Median ' .. num(value.median) .. '   |   Low ' .. num(value.min) .. '   |   High ' .. num(value.max),
                'Median is the middle gain when sorted by amount. Low and High are the smallest and largest gains in this group.');
        end
    end
end

local alert_help = {
    level = 'Notify when you gain a level. Loading the addon or changing jobs does not trigger this alert.',
    merit = 'Notify when you gain a merit point. Spending merit points does not trigger this alert.',
    goal = 'Notify when you reach the goal chosen under Tracking.',
    cap = 'Warn before your stored merit points are full. Choose how many more merit points you can hold when the warning appears.',
    food_end = 'Play a sound once when Phoenix reports that your food effect wore off. Removing food can trigger it too. Loading, zoning, and turning this on stay quiet. This alert supports sound only.',
    food_soon = 'Warn when your food effect has this much time left. Choose Food effect wore off for a sound when it ends.',
    dedication_end = 'Notify when the game reports that your Dedication effect wore off. Loading the addon or zoning does not trigger this alert.',
    dedication_low = 'Warn when Dedication has this much bonus EXP left. Needs extra Phoenix server support. An unknown amount does not trigger an alert.',
    ring_ready = 'Notify when an EXP ring with charges finishes its recast. You still need to equip and use it yourself.',
    sync_change = 'Notify when your Level Sync penalty changes. Needs extra Phoenix server support. Starting Level Sync or changing its level does not trigger this by itself. Changing the estimate stays quiet too.',
    no_exp = 'Notify when Phoenix says why you missed EXP, such as being too far from the monster. Simply gaining no EXP does not trigger an alert.',
    chain_soon = 'Warn when the EXP chain timer reaches the time below. Estimated timing uses Phoenix rules; timing sent by Phoenix is used when available. Your next kill still has to qualify for an EXP chain.',
    dyna_time = 'Warn when your Dynamis hourglass reaches one of the times below. Time extensions update the warnings. Unknown time stays quiet.',
    dyna_extension = 'Notify when your Dynamis run gains a time extension. Loading or rejoining a run stays quiet.',
    dyna_wanted = 'Notify when a wanted item enters the treasure pool. Choose jobs and items under Dynamis > Wanted drops.',
    dyna_pool = 'Warn when an item has been waiting in the treasure pool this long before its usual expiry. The time is estimated; an item can leave sooner when everyone lots or passes.',
    dyna_clear = 'Notify when you obtain the clear key item for the current Dynamis zone. Owning it from an earlier run does not trigger an alert.',
    dyna_subjob = 'Notify when your support job restriction is removed during a Dynamis run.',
};

local alert_groups = {
    { 'Food', 'Food wearing off or running low.', { 'food_end', 'food_soon' } },
    { 'EXP chains', 'A warning before your EXP chain timer runs out.', { 'chain_soon' } },
    { 'Dedication', 'Dedication wearing off or running low on bonus EXP.', { 'dedication_end', 'dedication_low' } },
    { 'EXP rings', 'An EXP ring with charges is ready to use.', { 'ring_ready' } },
    { 'Levels and merit points', 'Levels, merit points, nearly full merits, and your tracking goal.', { 'level', 'merit', 'cap', 'goal' } },
    { 'Level Sync and missed EXP', 'Level Sync penalty changes and reasons Phoenix gives for missed EXP.', { 'sync_change', 'no_exp' } },
    { 'Dynamis', 'Time, time extensions, wanted drops, the treasure pool, clears, and support job unlocks.', { 'dyna_time', 'dyna_extension', 'dyna_wanted', 'dyna_pool', 'dyna_clear', 'dyna_subjob' } },
};
local alert_names = { food_end = 'Food effect wore off' };
for _, event in ipairs(defaults.ALERTS) do alert_names[event[1]] = event[2]; end

local function food_alert(settings, services, ui, files)
    ui.checkbox(settings.alerts, 'food_enabled', 'Play sound', 'Play your chosen sound when your food effect wears off. Uncheck this to turn it off.');
    ui.combo('Sound', settings.alerts.food_sound ~= '' and settings.alerts.food_sound or '(none)', files, function(value)
        settings.alerts.food_sound, food_sound_status = value, nil;
        ui.changed();
    end);
    if settings.alerts.food_sound == '' then ui.note('Choose a sound to hear this alert.'); end
    if #files == 1 then ui.note('No .mp3 or .wav files were found. Add one, then press Refresh.'); end
    if imgui.Button('Refresh##food_sound') then
        if services.sound_refresh then services.sound_refresh(); end
        food_sound_status = nil;
    end
    ui.tip('Refresh the list after adding a sound file.');
    ui.slider(settings.alerts, 'food_volume', 'Sound volume', 0, 100, '%.0f%%', 'Volume for the food effect alert. Zero is silent.');
    settings.alerts.food_volume = math.floor(settings.alerts.food_volume + 0.5);
    imgui.BeginDisabled(settings.alerts.food_sound == '');
    if imgui.Button('Play##food_sound') and services.sound_play then
        local okay, problem = services.sound_play();
        food_sound_status = okay == false and (problem or 'That sound could not play. Try another file.') or nil;
    end
    ui.tip('Plays the selected sound at this volume. You can test it while the notification is off.');
    imgui.EndDisabled();
    local problem = services.sound_problem and services.sound_problem() or food_sound_status;
    if problem then ui.note(problem); end
end

local function event_alert(settings, id, services, ui, sound_files)
    local event = settings.alerts.events[id];
    ui.checkbox(event, 'visual', 'Show notice', 'Show a short notice on the bar for this alert.');
    ui.checkbox(event, 'sound', 'Play sound', 'Play the sound chosen below for this alert.');
    if not event.visual and not event.sound then return; end
    if event.sound then
        local files = sound_files();
        ui.combo('Sound', event.file ~= '' and event.file or '(none)', files, function(value) event.file = value; ui.changed(); end);
        if event.file == '' then ui.note('Choose a sound to hear this alert.'); end
        if #files == 1 then ui.note('No .mp3 or .wav files were found. Add one, then press Refresh.'); end
        if imgui.Button('Refresh##alert_sound') and services.sound_refresh then services.sound_refresh(); end
        ui.tip('Refresh the list after adding a sound file.');
        ui.slider(event, 'volume', 'Sound volume', 0, 100, '%.0f%%', 'Volume for this alert. Zero is silent.');
    end
    if id == 'food_soon' then
        ui.slider(settings.alerts, 'food_soon_seconds', 'Food warning time', 5, 600, '%.0f seconds',
            'Warn when your food effect has this many seconds left.');
    elseif id == 'dedication_low' then
        ui.slider(settings.alerts, 'dedication_low_points', 'Bonus EXP remaining', 1, 100000, nil,
            'Warn when Dedication has this much bonus EXP left. Needs extra Phoenix server support. Unknown amounts stay quiet.');
    elseif id == 'chain_soon' then
        ui.slider(settings.alerts, 'chain_soon_seconds', 'EXP chain warning time', 1, 60, '%.0f seconds',
            'Warn when the EXP chain timer has this many seconds left. An estimated timer can end early. No alert plays when the time is unknown.');
    elseif id == 'cap' then
        ui.slider(settings.alerts, 'cap_headroom', 'Merit points from full', 0, 30, nil,
            'Warn when you can hold this many more merit points. Zero warns when your merit points are full.');
    elseif id == 'dyna_time' then
        local chosen = {};
        for _, minutes in ipairs(settings.dynamis.warning_minutes) do chosen[minutes] = true; end
        for _, minutes in ipairs({ 10, 5, 1 }) do
            ui.checkbox(chosen, minutes, minutes .. (minutes == 1 and ' minute left' or ' minutes left'), 'Warn when your hourglass reaches this time.');
        end
        settings.dynamis.warning_minutes = {};
        for _, minutes in ipairs({ 10, 5, 1 }) do if chosen[minutes] then settings.dynamis.warning_minutes[#settings.dynamis.warning_minutes + 1] = minutes; end end
    elseif id == 'dyna_pool' then
        ui.slider(settings.dynamis, 'pool_warning_seconds', 'Pool warning time', 10, 240, '%.0f seconds',
            'Warn with about this much time left before an item leaves the treasure pool. The item may leave earlier when everyone lots or passes.');
    end
    ui.slider(event, 'cooldown', 'Time between alerts', 0, 3600, '%.0f seconds',
        'Wait at least this long before repeating this alert. Other alerts have their own wait times.');
    if imgui.Button('Test notification') and services.notification_test then services.notification_test(id); end
    ui.tip('Try this alert with the choices above. Your EXP and run totals stay the same.');
    local problem = services.notification_problem and services.notification_problem(id);
    if problem then ui.note(problem); end
end

function details.alerts(settings, _, services, ui)
    ui.note('Open an alert type, then check Show notice, Play sound, or both. Uncheck both to turn an alert off.');
    local files;
    local function sound_files()
        if not files then
            files = { { name = '(none)', value = '' } };
            for _, file in ipairs(services.sound_files and services.sound_files() or {}) do files[#files + 1] = file; end
        end
        return files;
    end
    for _, group in ipairs(alert_groups) do
        local enabled = 0;
        for _, id in ipairs(group[3]) do
            local event = settings.alerts.events[id];
            if id == 'food_end' and settings.alerts.food_enabled
                or event and (event.visual or event.sound) then enabled = enabled + 1; end
        end
        if ui.section(group[1], group[2], false, enabled .. ' on') then
            for index, id in ipairs(group[3]) do
                if index > 1 then imgui.Spacing(); imgui.Separator(); end
                imgui.PushID(id);
                row(ui, alert_names[id], alert_help[id]);
                if id == 'food_end' then food_alert(settings, services, ui, sound_files());
                else event_alert(settings, id, services, ui, sound_files); end
                imgui.PopID();
            end
        end
    end
    if ui.section('Quiet conditions', 'Choose when alerts should stay quiet. The test buttons still work.', false) then
        ui.checkbox(settings.alerts, 'quiet_paused', 'Mute alerts while paused', 'Mute all alerts, including the food effect sound, while the session is paused.');
        ui.checkbox(settings.alerts, 'quiet_events', 'Mute alerts during events', 'Mute all alerts, including the food effect sound, during events and cutscenes.');
    end
end

local function action(callback, success, ...)
    if not callback then return 'This session action is unavailable.', false; end
    local okay, problem = callback(...);
    return okay == false and (problem or 'The session action failed.') or success, okay ~= false;
end

function details.current_session(_, _, services, ui)
    local current = services.session_current and services.session_current();
    local id = current and current.id;
    local buttons = {};
    if current_selected ~= id then
        current_selected, current_name[1] = id, current and current.name or '';
        current_status = nil;
    end
    if current then
        imgui.TextUnformatted('Current session name');
        imgui.SetNextItemWidth(math.min(400, (imgui.GetContentRegionAvail())));
        imgui.InputText('##Current session name', current_name, 49);
        ui.help('Give this session a name. Saving keeps your current totals and lets you continue tracking.');
        buttons[#buttons + 1] = { 'Rename current session', function()
            current_status = action(services.session_rename, 'Current session renamed.', current.id, current_name[1]);
        end, 'Apply the name above to the current run.' };
    end
    buttons[#buttons + 1] = { 'Save current session', function()
        current_status = action(services.session_save, 'Current session saved.');
    end,
        'Save your current session totals and keep tracking. This does not start a new session.' };
    ui.buttons(buttons);
    if current_status then ui.note(current_status); end
end

local function history_records(services)
    local source = services.session_history and services.session_history();
    if source and history_cache and history_cache.source == source then return history_cache; end
    local rows = source;
    if not rows then
        local current = services.session_current and services.session_current();
        rows = {};
        for _, entry in ipairs(services.session_list and services.session_list() or {}) do
            if entry.active ~= true and not (current and entry.id == current.id) then rows[#rows + 1] = entry; end
        end
    end
    local result = { source = source, rows = rows, choices = {}, entries = {}, labels = {}, dates = {} };
    for _, entry in ipairs(rows) do
        local created = type(entry.created) == 'number' and os.date('%Y-%m-%d %H:%M', entry.created) or nil;
        local saved = type(entry.saved) == 'number' and os.date('%Y-%m-%d %H:%M', entry.saved) or 'Unknown';
        local label = (entry.name or 'Session') .. ' - ' .. (entry.job_name or tostring(entry.job or '?')) .. ' - ' .. (created or 'Date unknown');
        result.choices[#result.choices + 1] = { name = label, value = entry.id };
        result.entries[entry.id], result.labels[entry.id] = entry, label;
        result.dates[entry.id] = 'Started ' .. (created or 'Unknown') .. '   |   Saved ' .. saved;
    end
    if source then history_cache = result; end
    return result;
end

function details.sessions(settings, _, services, ui)
    if ui.section('Saved sessions', 'View, rename, or delete your saved sessions. Reset session saves your current totals and starts a new session.', true) then
        local records = history_records(services);
        local selected = records.entries[history_selected];
        if not selected then
            selected = records.rows[1];
            history_selected = selected and selected.id;
            history_name[1], history_confirmation = selected and selected.name or '', nil;
        end
        if selected then
            ui.combo('Session record', records.labels[history_selected], records.choices, function(id)
                history_selected, history_confirmation, history_status = id, nil, nil;
                local entry = records.entries[id];
                history_name[1] = entry and entry.name or '';
            end);
            ui.help('Choose a saved session for this character. Looking at it does not resume it or change your current session.');
        else
            ui.note('No other sessions saved yet.');
        end
        if selected then
            row(ui, (selected.job_name or 'Job ' .. tostring(selected.job or '?')) .. '   |   Time ' .. time(selected.elapsed)
                .. '   |   EXP gained ' .. num(selected.session_exp) .. '   |   LP gained ' .. num(selected.session_lp),
                'Totals saved for this session. Time offline is not counted. Your current session is shown above.');
            row(ui, 'Net EXP ' .. num(selected.net_exp) .. '   |   Net LP ' .. num(selected.net_lp)
                .. '   |   Merit points ' .. num(selected.merits_gained) .. '   |   Best EXP chain ' .. num(selected.best_chain),
                'Net includes gains, losses, Raise recovery, and other changes the addon saw. Merit points counts those gained during this session. Best EXP chain is the highest chain seen.');
            row(ui, records.dates[selected.id], 'Dates are shown in your computer\'s local time.');
            imgui.TextUnformatted('Session name');
            imgui.SetNextItemWidth(math.min(400, (imgui.GetContentRegionAvail())));
            imgui.InputText('##Session name', history_name, 49);
            ui.help('Enter a name, then click Rename selected to rename this saved session.');
        end
        if selected then
            ui.buttons({ { 'Rename selected', function()
                history_status = action(services.session_rename, 'Session renamed.', history_selected, history_name[1]);
            end,
                'Use the name above for this saved session.' } });
            imgui.BeginDisabled(selected.active == true);
            if imgui.Button('Delete selected session') then history_confirmation = 'delete'; end
            ui.tip('Delete this saved session. Your current session cannot be deleted here.');
            imgui.EndDisabled();
            ui.help('This removes only the selected saved session. Your current session and character EXP stay the same.');
        end
        if history_confirmation == 'delete' then
            ui.note('Delete this saved session? This cannot be undone.');
            ui.buttons({ { 'Delete record now', function()
                local okay;
                history_status, okay = action(services.session_delete, 'Session deleted.', history_selected);
                if okay then
                    history_selected, history_confirmation = nil, nil;
                end
            end, 'Delete this saved session permanently.' },
                { 'Cancel session action', function() history_confirmation = nil; end, 'Keep the record.' } });
        end
    end
    local problem = services.session_problem and services.session_problem();
    if problem or history_status then ui.note(problem or history_status); end
    if ui.section('Session storage', 'Choose whether to resume sessions and how many to keep for this character.', false) then
        ui.checkbox(settings.sessions, 'resume', 'Resume this character and job after a reload',
            'Continue the saved session for this character and job after reloading. Time offline is not counted. Tracking picks up from your current EXP and LP.');
        ui.slider(settings.sessions, 'retention', 'Sessions to keep', 1, 100);
        ui.help('When this limit is reached, the oldest saved sessions are removed first. Your current session is kept.');
        settings.sessions.retention = math.floor(settings.sessions.retention + 0.5);
    end
end

function details.cancel_pending()
    history_confirmation = nil;
end

return details;
