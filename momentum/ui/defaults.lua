local theme = require('ui.theme');
local defaults = {};

defaults.READOUTS = {
    { id = 'job', name = 'Job and level', label = '', enabled = true, help = 'Shows your main job, normal level, and synced level while Level Sync is active.' },
    { id = 'progress', name = 'EXP / LP progress', label = '', enabled = true, help = 'Shows your current EXP or limit points (LP) and how much you need for the next level or merit point. Choose which one to show in Tracking.' },
    { id = 'remaining', name = 'TNL / LP needed', label = 'TNL', enabled = true, help = 'Shows the EXP needed for your next level, or the LP needed for your next merit point. At level 75, EXP shows how much room is left in your EXP buffer.' },
    { id = 'rate', name = 'EXP/HR', label = '', enabled = true, help = 'Shows your EXP per hour over the time period chosen in Tracking. It changes to LP/HR when the bar shows limit points. Choose EXP/HR (always) or LP/HR (always) to show one of these all the time.' },
    { id = 'eta', name = 'Time to next level or merit', label = 'Next', enabled = false, help = 'Estimates how long it will take to fill the EXP or LP bar at your current rate. -- means Momentum does not have enough information yet. Spend merits means you must spend a stored merit point before earning another.' },
    { id = 'chain', name = 'EXP chain', label = 'Chain', enabled = true, help = 'Shows the last EXP chain number and its bonus. The chain may have ended since that reward.' },
    { id = 'chain_time', name = 'EXP chain timer', label = 'Next chain', enabled = false, help = 'Estimates the time left to earn the next EXP chain using Phoenix rules. ~ means the timer is estimated, and the chain may last longer. If Phoenix sends an end time, the timer uses it instead.' },
    { id = 'last', name = 'Last EXP / LP reward', label = 'Last', enabled = false, help = 'Shows the last EXP or LP reward. When your EXP or LP is capped, the reward can be larger than the amount you keep.' },
    { id = 'percent', name = 'Progress percent', label = '', enabled = false, help = 'Shows how full your EXP or LP bar is, as a percentage.' },
    { id = 'merits', name = 'Stored merit points', label = 'Merits', enabled = false, help = 'Shows your unspent merit points and how many you can hold, such as 3 / 10. Every 10,000 LP earns one merit point when you have room for it.' },
    { id = 'merit_rate', name = 'Merit points per hour', label = 'Merits/hr', enabled = false, help = 'Shows how many merit points your LP/HR is worth. For example, 12,500 LP/HR equals 1.25 merit points per hour. This also works while the main bar shows EXP.' },
    { id = 'goal', name = 'Goal progress', label = 'Goal', enabled = false, help = 'Shows what is left to reach the goal you chose in Tracking. Time left is an estimate based on your EXP/HR or LP/HR.' },
    { id = 'buffer', name = 'EXP buffer', label = 'Buffer', enabled = false, help = 'Shows your current EXP and the amount needed to fill your EXP bar, even while tracking merit points. At level 75, this is your EXP buffer. -- means the amount is not known yet.' },
    { id = 'session', name = 'Session EXP / LP received', label = 'Earned', enabled = false, help = 'Adds up EXP or LP rewards received during this session, using whichever one the bar shows. EXP recovered from Raise does not count here.' },
    { id = 'net', name = 'Session progress', label = 'Net', enabled = false, help = 'Shows how much your EXP or LP has changed this session. EXP lost on death and recovered from Raise count here, along with other EXP changes. Points lost because you were capped do not count.' },
    { id = 'elapsed', name = 'Session time', label = 'Time', enabled = false, help = 'Shows how long this session has been running. Time while paused or while Momentum was unloaded does not count.' },
    { id = 'average', name = 'Average EXP / LP gain', label = 'Average', enabled = false, help = 'Shows the average EXP or LP reward for this session, using whichever one the bar shows.' },
    { id = 'best_chain', name = 'Best EXP chain', label = 'Best chain', enabled = false, help = 'Shows the highest EXP chain number recorded during this session.' },
    { id = 'dedication', name = 'Dedication', label = '', enabled = false, help = 'Shows whether Dedication is active and how much time is left when that time is known.' },
    { id = 'status', name = 'Tracking status', label = '', enabled = false, help = 'Shows whether the session is tracking, paused, waiting to calculate a rate, or at the EXP or LP cap.' },
    { id = 'sync', name = 'Level Sync', label = 'Sync', enabled = false, help = 'Shows your normal level and synced level. It only shows an EXP penalty when Phoenix has sent your current penalty.' },
    { id = 'no_exp', name = 'No EXP reason', label = '', enabled = false, help = 'Shows why you missed EXP when Phoenix provides a reason. A missing reward alone cannot tell Momentum what happened.' },
    { id = 'exp_progress', name = 'EXP progress', label = 'EXP', enabled = false, help = 'Shows your current EXP and the amount needed to fill your EXP bar, even while the main bar shows LP.' },
    { id = 'lp_progress', name = 'LP toward next merit point', label = 'LP', enabled = false, help = 'Shows your LP toward the next merit point, out of 10,000, even while the main bar shows EXP. When your merit points are full, spend at least one before earning another.' },
    { id = 'exp_rate', name = 'EXP/HR (always)', label = 'EXP/HR', enabled = false, help = 'Shows EXP per hour even while the main bar shows LP. Choose the time period and which EXP changes count in Tracking.' },
    { id = 'lp_rate', name = 'LP/HR (always)', label = 'LP/HR', enabled = false, help = 'Shows limit points per hour even while the main bar shows EXP. Choose the time period and which LP changes count in Tracking.' },
    { id = 'exp_session', name = 'Session EXP', label = 'EXP earned', enabled = false, help = 'Adds up the EXP rewards received during this session.' },
    { id = 'lp_session', name = 'Session LP', label = 'LP earned', enabled = false, help = 'Adds up the LP rewards received during this session.' },
    { id = 'average3', name = 'Average of last 3 gains', label = 'Avg3', enabled = false, help = 'Shows the average of your last three EXP or LP rewards, using whichever one the bar shows. With fewer than three rewards, it uses the ones available. Rewards are not a kill count.' },
    { id = 'average10', name = 'Average of last 10 gains', label = 'Avg10', enabled = false, help = 'Shows the average of your last ten EXP or LP rewards, using whichever one the bar shows. With fewer than ten rewards, it uses the ones available.' },
    { id = 'average_n', name = 'Average recent gains', label = 'Avg N', enabled = false, help = 'Shows the average of your recent EXP or LP rewards. Choose how many rewards to use in Tracking.' },
    { id = 'sample_count', name = 'Gains counted', label = 'Samples', enabled = false, help = 'Shows how many recent EXP or LP gains are available and how many you asked to use. If you asked for ten but have only six, the average uses those six.' },
    { id = 'minimum', name = 'Lowest recent gain', label = 'Low', enabled = false, help = 'Shows the smallest EXP or LP reward among the recent rewards you chose to count.' },
    { id = 'maximum', name = 'Highest recent gain', label = 'High', enabled = false, help = 'Shows the largest EXP or LP reward among the recent rewards you chose to count.' },
    { id = 'median', name = 'Middle recent gain', label = 'Median', enabled = false, help = 'Shows the middle value when recent EXP or LP gains are sorted from lowest to highest. With an even number of gains, it averages the two middle values.' },
    { id = 'food', name = 'Food effect', label = 'Food', enabled = false, help = 'Shows your food effect and its time left. The food name and timer only appear when Momentum knows them.' },
    { id = 'ring', name = 'EXP ring', label = 'Ring', enabled = false, help = 'Shows the charges and recast for an EXP ring you own when the game provides them. Momentum does not use the ring for you.' },
    { id = 'dedication_budget', name = 'Dedication bonus EXP left', label = 'Bonus left', enabled = false, help = 'Shows how much bonus EXP is left from Dedication. -- means Phoenix has not sent a current amount. The Dedication icon alone cannot tell Momentum how much is left.' },
    { id = 'merits_session', name = 'Merit points earned this session', label = 'Merits earned', enabled = false, help = 'Counts whole merit points earned since this session started. Spending merit points does not lower this count. LP you already had can help earn the first merit point.' },
    { id = 'merit_headroom', name = 'Merit points before cap', label = 'Merit slots', enabled = false, help = 'Shows how many more merit points you can hold. For example, 3 out of 10 leaves room for 7. At zero, spend a merit point before earning another.' },
    { id = 'lp_remaining', name = 'LP to next merit point', label = 'LP needed', enabled = false, help = 'Shows the LP needed for your next merit point, even while the main bar shows EXP. Spend merits means you must spend a merit point before earning another.' },
    { id = 'merit_eta', name = 'Time to next merit point', label = 'Next merit', enabled = false, help = 'Estimates when you will earn your next merit point at your current LP/HR. -- means Momentum does not know your LP/HR or how many merit points you can hold yet. Spend merits means your merit points are full.' },
    { id = 'dyna_zone', name = 'Dynamis zone', label = '', enabled = false, help = 'Shows the Dynamis zone for this run.' },
    { id = 'dyna_time', name = 'Dynamis time left', label = 'Time', enabled = false, help = 'Time left on your Perpetual Hourglass. Time extensions update it automatically. Resetting or pausing your EXP session does not stop it. -- means unknown; ~ means your computer clock is being used until server time is available.' },
    { id = 'dyna_extensions', name = 'Dynamis time extensions', label = 'TE', enabled = false, help = 'Shows the total minutes added to this run. Open Dynamis for the extensions seen so far. Joining late can recover the minutes from your hourglass without knowing which monsters were defeated.' },
    { id = 'dyna_currency', name = 'Dynamis currency found', label = 'Currency', enabled = false, help = 'Adds up currency seen in the treasure pool. A hundred-piece counts as 100. This is the run total seen by Momentum, not just what you received.' },
    { id = 'dyna_af2', name = 'Relic armor found', label = 'AF2', enabled = false, help = 'Counts relic armor drops seen in the treasure pool. Open Dynamis for item names and jobs.' },
    { id = 'dyna_currency_received', name = 'Dynamis currency received', label = 'Mine', enabled = false, help = 'Currency awarded to you during this run, counted in singles. Trading or moving currency between bags does not add to it.' },
    { id = 'dyna_currency_rate', name = 'Dynamis currency per hour', label = 'Currency/HR', enabled = false, help = 'Currency found per hour since tracking started or totals were cleared. Partial runs can include offline time and missing drops. Hundred-pieces count as 100.' },
    { id = 'dyna_af2_received', name = 'Relic armor received', label = 'My AF2', enabled = false, help = 'Counts relic armor awarded to you during this run.' },
    { id = 'dyna_bynes', name = 'Byne bills found', label = 'Bynes', enabled = false, help = 'Byne bills seen in the treasure pool, counted in singles. One 100 Byne Bill counts as 100.' },
    { id = 'dyna_bronze', name = 'Bronzepieces found', label = 'Bronze', enabled = false, help = 'San d\'Orian currency seen in the treasure pool, counted in singles. One M. Silverpiece counts as 100.' },
    { id = 'dyna_shells', name = 'Whiteshells found', label = 'Shells', enabled = false, help = 'Windurstian currency seen in the treasure pool, counted in singles. One L. Jadeshell counts as 100.' },
    { id = 'dyna_bynes_received', name = 'Byne bills received', label = 'My bynes', enabled = false, help = 'Byne bills awarded to you, counted in singles.' },
    { id = 'dyna_bronze_received', name = 'Bronzepieces received', label = 'My bronze', enabled = false, help = 'San d\'Orian currency awarded to you, counted in singles.' },
    { id = 'dyna_shells_received', name = 'Whiteshells received', label = 'My shells', enabled = false, help = 'Windurstian currency awarded to you, counted in singles.' },
    { id = 'dyna_kills', name = 'Dynamis monsters defeated', label = 'Defeated', enabled = false, help = 'Counts monster deaths seen by Momentum. Monsters outside your range may be missed. This is not the number left in the zone.' },
    { id = 'dyna_objectives', name = 'Dynamis objectives', label = 'Objectives', enabled = false, help = 'Shows confirmed objectives completed out of the listed objectives for this zone. Unseen objectives stay unknown. Open Dynamis for the full list.' },
    { id = 'dyna_pool', name = 'Dynamis treasure pool', label = 'Pool', enabled = false, help = 'Shows how many items are waiting in the treasure pool. Open Dynamis to see them.' },
    { id = 'dyna_subjob', name = 'Dynamis support job', label = 'Support job', enabled = false, help = 'Shows whether your support job is restricted. This follows your actual status effect.' },
    { id = 'dyna_weakness', name = 'Dynamis Weakness timer', label = 'Weakness', enabled = false, help = 'Shows your current Weakness timer. Re-entering an active Phoenix Dynamis run applies 10 minutes of Weakness.' },
    { id = 'dyna_next_entry', name = 'Next Dynamis entry', label = 'Next entry', enabled = false, help = 'Time left from this character\'s observed registration. Phoenix uses a 72-hour account lockout. Other characters\' registrations and entry requirements are not checked. -- means no registration was observed.' },
};

defaults.ALERTS = {
    { 'level', 'Level gained' }, { 'merit', 'Merit point gained' }, { 'goal', 'Goal reached' }, { 'cap', 'Merit points almost full' },
    { 'food_soon', 'Food effect ending soon' }, { 'dedication_end', 'Dedication wore off' },
    { 'dedication_low', 'Dedication bonus EXP low' }, { 'ring_ready', 'EXP ring ready' },
    { 'sync_change', 'Level Sync changed' }, { 'no_exp', 'No EXP reason' }, { 'chain_soon', 'EXP chain timer low' },
    { 'dyna_time', 'Dynamis time running low' }, { 'dyna_extension', 'Dynamis time extended' },
    { 'dyna_wanted', 'Wanted Dynamis drop' }, { 'dyna_pool', 'Treasure pool item expiring' },
    { 'dyna_clear', 'Dynamis clear obtained' }, { 'dyna_subjob', 'Support job unlocked' },
};

defaults.STARTER_LAYOUTS = {
    Minimal = { 'progress', 'remaining', 'rate' },
    Leveling = { 'job', 'progress', 'remaining', 'rate', 'chain' },
    Merits = { 'lp_rate', 'merits', 'lp_remaining', 'merit_eta' },
    Dynamis = { 'dyna_zone', 'dyna_time', 'dyna_extensions', 'dyna_currency', 'dyna_af2' },
};

function defaults.apply_starter(settings, name)
    local starter = defaults.STARTER_LAYOUTS[name];
    if not starter then return false; end
    local chosen, ordered = {}, {};
    for _, id in ipairs(starter) do chosen[id] = true; ordered[#ordered + 1] = id; end
    for _, item in ipairs(defaults.READOUTS) do
        settings.display.enabled[item.id] = chosen[item.id] == true;
        if not chosen[item.id] then ordered[#ordered + 1] = item.id; end
    end
    settings.display.order, settings.display.preset = ordered, name;
    return true;
end

local function copy(value)
    if type(value) ~= 'table' then return value; end
    local result = {};
    for key, entry in pairs(value) do result[key] = copy(entry); end
    return result;
end

defaults.copy = copy;

function defaults.make()
    local settings = {
        appearance_version = 0,
        bar = { docked = true, anchor = 'bottom', start = 0, auto_width = true, hide_typing = true,
            x = 0, y = 500, width = 640, height = 18, bottom = 2, locked = false, snap = true },
        display = { mode = 'auto', alignment = 'left', label_position = 'before', order = {}, enabled = {}, labels = {}, dividers = {}, colors = {}, divider = ' ', label_divider = ' ',
            groups_enabled = false, groups = {}, priority_overflow = false, priorities = {}, pinned = {}, conditions = {},
            chain_strip = true, short = false, spacing = 8, preset = 'Leveling', auto_layout = false, hover = true, show_fill = true, show_text = true },
        tracking = { window = 900, rate_basis = 'earned', goal_merits = 5, hide_idle = false, average_count = 10,
            goal_type = 'stored_merits', goal_level = 75, goal_exp = 10000, goal_session_merits = 1, goal_buffer = 10000 },
        sessions = { resume = true, retention = 30 },
        modes = { selected = 'auto', exp = {}, merits = {}, previous_display = {} },
        dynamis = { enabled = true, auto_layout = true, layout_active = false, wanted_jobs = {}, wanted_items = {}, retention = 30,
            warning_minutes = { 10, 5, 1 }, pool_warning_seconds = 60 },
        planner = { level = 50, population = 0 },
        alerts = { food_enabled = false, food_sound = 'FF VII Save.mp3', food_volume = 100, events = {},
            food_soon_seconds = 60, dedication_low_points = 100, chain_soon_seconds = 10, cap_headroom = 1,
            quiet_paused = true, quiet_events = true },
        style = { preset = 'Phoenix', palette_version = 0, font = 'Segoe UI', font_size = 13, opacity = 0.96, rounding = 5, fill_style = 'rail',
            fill_direction = 'right', border = false, text_shadow = false,
            colors = theme.colors('Phoenix'), window_colors = theme.window_colors('Phoenix') },
        visibility = { mode = 'placement', map = true, event = true, game_ui = true },
        window = { open = false, width = 920, height = 660, x = 80, y = 60, tab = 'Display', font_size = 18,
            sections = {}, compact_navigation = false },
        preview = { show = false, scenario = 'Leveling' }, shared = false, job_links = {},
    };
    for _, alert in ipairs(defaults.ALERTS) do
        settings.alerts.events[alert[1]] = { visual = false, sound = false, file = '', volume = 100, cooldown = 30 };
    end
    for _, item in ipairs(defaults.READOUTS) do
        settings.display.order[#settings.display.order + 1] = item.id;
        settings.display.enabled[item.id] = item.enabled;
        settings.display.labels[item.id] = item.label;
        settings.display.dividers[item.id] = true;
        settings.display.groups[item.id] = 'left';
        settings.display.priorities[item.id] = 50;
        settings.display.pinned[item.id] = false;
        settings.display.conditions[item.id] = 'always';
    end
    settings.dynamis.layout = copy(settings.display);
    defaults.apply_starter({ display = settings.dynamis.layout }, 'Dynamis');
    settings.dynamis.layout.divider = ' | ';
    return settings;
end

local function merge(target, source)
    for key, value in pairs(source) do
        if type(target[key]) ~= type(value) then
            target[key] = copy(value);
        elseif type(value) == 'table' then
            merge(target[key], value);
        end
    end
end

local function number(value, low, high, fallback)
    value = tonumber(value);
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback; end
    return math.max(low, math.min(high, value));
end

local function plain(value, limit)
    return tostring(value):gsub('[^ -~]', ''):sub(1, limit);
end

local function choice(value, choices, fallback)
    for _, valid in ipairs(choices) do if value == valid then return value; end end
    return fallback;
end

local function tidy_saved_display(display, fresh, known)
    local order = type(display.order) == 'table' and copy(display.order) or {};
    merge(display, fresh);
    display.order = {};
    local seen = {};
    for _, id in ipairs(order) do
        if known[id] and not seen[id] then display.order[#display.order + 1] = id; seen[id] = true; end
    end
    for _, item in ipairs(defaults.READOUTS) do
        local id = item.id;
        if not seen[id] then display.order[#display.order + 1] = id; end
        display.labels[id] = plain(display.labels[id], 32);
        display.groups[id] = choice(display.groups[id], { 'left', 'center', 'right' }, 'left');
        display.priorities[id] = math.floor(number(display.priorities[id], 0, 100, 50));
        display.conditions[id] = choice(display.conditions[id], { 'always', 'known', 'exp', 'lp', 'synced', 'chain', 'dedication', 'food' }, 'always');
    end
    display.spacing = number(display.spacing, 0, 24, 8);
    display.divider, display.label_divider = plain(display.divider, 16), plain(display.label_divider, 8);
    display.mode = choice(display.mode, { 'auto', 'exp', 'lp' }, 'auto');
    display.alignment = choice(display.alignment, { 'left', 'right' }, 'left');
    display.label_position = choice(display.label_position, { 'before', 'after' }, 'before');
    for id, color in pairs(display.colors) do
        if not known[id] or type(color) ~= 'table' then display.colors[id] = nil;
        else for i = 1, 4 do color[i] = number(color[i], 0, 1, 1); end end
    end
end

function defaults.tidy(settings)
    if type(settings) ~= 'table' then return defaults.make(); end
    local fresh = defaults.make();
    local order = type(settings.display) == 'table' and settings.display.order or nil;
    local saved_order = type(order) == 'table' and copy(order) or {};
    local dynamis = type(settings.dynamis) == 'table' and settings.dynamis or {};
    local dyna_order = type(dynamis.layout) == 'table' and dynamis.layout.order or nil;
    dyna_order = type(dyna_order) == 'table' and copy(dyna_order) or copy(fresh.dynamis.layout.order);
    local warnings = type(dynamis.warning_minutes) == 'table' and copy(dynamis.warning_minutes) or copy(fresh.dynamis.warning_minutes);
    merge(settings, fresh);
    local known, seen = {}, {};
    for _, item in ipairs(defaults.READOUTS) do known[item.id] = true; end
    settings.modes.selected = choice(settings.modes.selected, { 'auto', 'exp', 'merits', 'dynamis' }, 'auto');
    for _, key in ipairs({ 'exp', 'merits', 'previous_display' }) do
        if next(settings.modes[key]) then tidy_saved_display(settings.modes[key], fresh.display, known); end
    end
    if type(settings.dynamis.previous_display) == 'table' then tidy_saved_display(settings.dynamis.previous_display, fresh.display, known); end
    settings.display.order = {};
    for _, id in ipairs(saved_order) do
        if known[id] and not seen[id] then
            settings.display.order[#settings.display.order + 1] = id;
            seen[id] = true;
        end
    end
    for _, item in ipairs(defaults.READOUTS) do
        if not seen[item.id] then settings.display.order[#settings.display.order + 1] = item.id; end
        settings.display.labels[item.id] = plain(settings.display.labels[item.id], 32);
        settings.display.groups[item.id] = choice(settings.display.groups[item.id], { 'left', 'center', 'right' }, 'left');
        settings.display.priorities[item.id] = math.floor(number(settings.display.priorities[item.id], 0, 100, 50));
        settings.display.conditions[item.id] = choice(settings.display.conditions[item.id],
            { 'always', 'known', 'exp', 'lp', 'synced', 'chain', 'dedication', 'food' }, 'always');
    end
    local bar = settings.bar;
    bar.x = number(bar.x, -100000, 100000, fresh.bar.x);
    bar.y = number(bar.y, -100000, 100000, fresh.bar.y);
    bar.width = number(bar.width, 120, 16384, fresh.bar.width);
    bar.height = number(bar.height, 12, 120, fresh.bar.height);
    bar.bottom = number(bar.bottom, 2, 2000, fresh.bar.bottom);
    bar.anchor = choice(bar.anchor, { 'bottom', 'top' }, 'bottom');
    bar.start = math.floor(number(bar.start, 0, 16384, 0));
    settings.visibility.mode = choice(settings.visibility.mode, { 'placement', 'chat', 'keep', 'always' }, 'placement');
    settings.display.spacing = number(settings.display.spacing, 0, 24, 8);
    settings.display.divider = plain(settings.display.divider, 16);
    settings.display.label_divider = plain(settings.display.label_divider, 8);
    settings.display.mode = choice(settings.display.mode, { 'auto', 'exp', 'lp' }, 'auto');
    if not settings.dynamis.layout_active then
        if settings.modes.selected == 'exp' then settings.display.mode = 'exp';
        elseif settings.modes.selected == 'merits' then settings.display.mode = 'lp'; end
    end
    settings.display.alignment = choice(settings.display.alignment, { 'left', 'right' }, 'left');
    settings.display.label_position = choice(settings.display.label_position, { 'before', 'after' }, 'before');
    settings.style.font = plain(settings.style.font, 64);
    settings.style.font_size = number(settings.style.font_size, 8, 48, 13);
    settings.style.opacity = number(settings.style.opacity, 0.05, 1, 0.96);
    settings.style.rounding = number(settings.style.rounding, 0, 24, 5);
    settings.style.fill_style = choice(settings.style.fill_style, { 'rail', 'full' }, 'rail');
    settings.style.fill_direction = choice(settings.style.fill_direction, { 'right', 'left' }, 'right');
    settings.tracking.window = number(settings.tracking.window, 0, 3600, 900);
    settings.tracking.rate_basis = choice(settings.tracking.rate_basis, { 'earned', 'net' }, 'earned');
    settings.tracking.goal_merits = math.floor(number(settings.tracking.goal_merits, 1, 999, 5));
    settings.tracking.average_count = math.floor(number(settings.tracking.average_count, 1, 100, 10));
    settings.tracking.goal_type = choice(settings.tracking.goal_type, { 'stored_merits', 'level', 'session_exp', 'session_merits', 'buffer' }, 'stored_merits');
    settings.tracking.goal_level = math.floor(number(settings.tracking.goal_level, 1, 75, 75));
    settings.tracking.goal_exp = math.floor(number(settings.tracking.goal_exp, 1, 10000000, 10000));
    settings.tracking.goal_session_merits = math.floor(number(settings.tracking.goal_session_merits, 1, 999, 1));
    settings.tracking.goal_buffer = math.floor(number(settings.tracking.goal_buffer, 1, 100000, 10000));
    settings.sessions.retention = math.floor(number(settings.sessions.retention, 1, 100, 30));
    settings.dynamis.retention = math.floor(number(settings.dynamis.retention, 1, 100, 30));
    if type(settings.dynamis.previous_display) ~= 'table' then settings.dynamis.previous_display = nil; end
    settings.dynamis.pool_warning_seconds = math.floor(number(settings.dynamis.pool_warning_seconds, 10, 240, 60));
    settings.dynamis.warning_minutes = {};
    local warning_seen = {};
    for _, minutes in ipairs(warnings) do
        if (minutes == 10 or minutes == 5 or minutes == 1) and not warning_seen[minutes] then
            settings.dynamis.warning_minutes[#settings.dynamis.warning_minutes + 1] = minutes;
            warning_seen[minutes] = true;
        end
    end
    table.sort(settings.dynamis.warning_minutes, function(left, right) return left > right; end);
    local jobs = { WAR = true, MNK = true, WHM = true, BLM = true, RDM = true, THF = true, PLD = true, DRK = true, BST = true,
        BRD = true, RNG = true, SAM = true, NIN = true, DRG = true, SMN = true, BLU = true, COR = true, PUP = true };
    for job, enabled in pairs(settings.dynamis.wanted_jobs) do
        if not jobs[job] or enabled ~= true then settings.dynamis.wanted_jobs[job] = nil; end
    end
    local items = {};
    for id, enabled in pairs(settings.dynamis.wanted_items) do
        local item = tonumber(id);
        if enabled == true and item and item % 1 == 0 and item > 0 and item <= 65535 then items[tostring(item)] = true; end
    end
    settings.dynamis.wanted_items = items;
    local dyna = settings.dynamis.layout;
    local dyna_seen = {};
    dyna.order = {};
    for _, id in ipairs(dyna_order) do
        if known[id] and not dyna_seen[id] then dyna.order[#dyna.order + 1] = id; dyna_seen[id] = true; end
    end
    for _, item in ipairs(defaults.READOUTS) do
        local id = item.id;
        if not dyna_seen[id] then dyna.order[#dyna.order + 1] = id; end
        dyna.labels[id] = plain(dyna.labels[id], 32);
        dyna.groups[id] = choice(dyna.groups[id], { 'left', 'center', 'right' }, 'left');
        dyna.priorities[id] = math.floor(number(dyna.priorities[id], 0, 100, 50));
        dyna.conditions[id] = choice(dyna.conditions[id], { 'always', 'known', 'exp', 'lp', 'synced', 'chain', 'dedication', 'food' }, 'always');
    end
    dyna.spacing = number(dyna.spacing, 0, 24, 8);
    dyna.divider, dyna.label_divider = plain(dyna.divider, 16), plain(dyna.label_divider, 8);
    dyna.mode = choice(dyna.mode, { 'auto', 'exp', 'lp' }, 'auto');
    dyna.alignment = choice(dyna.alignment, { 'left', 'right' }, 'left');
    dyna.label_position = choice(dyna.label_position, { 'before', 'after' }, 'before');
    settings.planner.level = math.floor(number(settings.planner.level, 10, 75, 50));
    settings.planner.population = math.floor(number(settings.planner.population, 0, 100000, 0));
    settings.alerts.food_volume = math.floor(number(settings.alerts.food_volume, 0, 100, 100) + 0.5);
    settings.alerts.food_sound = settings.alerts.food_sound:match('[^\\/:]*$'):gsub('[%c"]', ''):sub(1, 160);
    if settings.alerts.food_sound:find('^%.*$') then settings.alerts.food_sound = ''; end
    for _, alert in ipairs(defaults.ALERTS) do
        local event = settings.alerts.events[alert[1]];
        event.volume = math.floor(number(event.volume, 0, 100, 100));
        event.cooldown = math.floor(number(event.cooldown, 0, 3600, 30));
        event.file = event.file:match('[^\\/:]*$'):gsub('[%c"]', ''):sub(1, 160);
        if event.file:find('^%.*$') then event.file = ''; end
    end
    settings.alerts.food_soon_seconds = math.floor(number(settings.alerts.food_soon_seconds, 5, 600, 60));
    settings.alerts.dedication_low_points = math.floor(number(settings.alerts.dedication_low_points, 1, 100000, 100));
    settings.alerts.chain_soon_seconds = math.floor(number(settings.alerts.chain_soon_seconds, 1, 60, 10));
    settings.alerts.cap_headroom = math.floor(number(settings.alerts.cap_headroom, 0, 30, 1));
    settings.window.width = number(settings.window.width, 320, 16384, 920);
    settings.window.height = number(settings.window.height, 240, 16384, 660);
    settings.window.x = number(settings.window.x, -100000, 100000, 80);
    settings.window.y = number(settings.window.y, -100000, 100000, 60);
    settings.window.font_size = number(settings.window.font_size, 12, 28, 18);
    settings.window.tab = choice(settings.window.tab, { 'Display', 'Tracking', 'Dynamis', 'Details', 'Alerts', 'Appearance', 'Preview', 'Session', 'Profiles' }, 'Display');
    settings.preview.scenario = choice(settings.preview.scenario, { 'Leveling', 'Merits', 'Dynamis', 'Capped', 'No data', 'Paused' }, 'Leveling');
    for key, color in pairs(settings.style.colors) do
        if fresh.style.colors[key] then
            for i = 1, 4 do color[i] = number(color[i], 0, 1, fresh.style.colors[key][i]); end
        end
    end
    for key, color in pairs(settings.style.window_colors) do
        if fresh.style.window_colors[key] then
            for i = 1, 4 do color[i] = number(color[i], 0, 1, fresh.style.window_colors[key][i]); end
        end
    end
    for _, display in ipairs({ settings.display, settings.dynamis.layout }) do
        for id, color in pairs(display.colors) do
            if not known[id] or type(color) ~= 'table' then display.colors[id] = nil;
            else for i = 1, 4 do color[i] = number(color[i], 0, 1, 1); end end
        end
    end
    return settings;
end

return defaults;
