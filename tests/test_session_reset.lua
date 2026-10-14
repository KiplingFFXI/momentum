local defaults = require('ui.defaults');
local history = require('ui.history');
local readouts = require('ui.readouts');
local rules = require('data.phoenix_rules');
local imgui = require('imgui');
local hud = require('ui.hud');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function check(value, label) equal(not not value, true, label); end

local settings = defaults.make();
settings.window.open, settings.window.tab = true, 'Session';
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y, settings.bar.width, settings.bar.height = 20, 700, 1400, 24;
settings.display.order = { 'progress', 'exp_rate', 'lp_rate', 'eta', 'merit_eta' };
settings.display.divider = ' | ';
settings.display.labels.exp_rate, settings.display.labels.eta = 'Pace', 'Next';
settings.display.dividers.eta = false;
for id in pairs(settings.display.enabled) do settings.display.enabled[id] = false; end
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
settings.tracking.window = 0;
MOCK.settings_file = settings;

local drawn, inline;
local draw, draw_inline = hud.draw, hud.draw_inline;
hud.draw = function(current, view, context)
    local from = #MOCK.imgui_calls;
    local changed = draw(current, view, context);
    drawn = { view = history.copy(view), parts = {}, text = {}, preview = context.preview };
    for _, part in ipairs(readouts.cached(current, view)) do drawn.parts[part.id] = part.value; end
    for i = from + 1, #MOCK.imgui_calls do
        local call = MOCK.imgui_calls[i];
        if call[1] == 'draw:AddText' then drawn.text[#drawn.text + 1] = call[6]; end
    end
    return changed;
end;
hud.draw_inline = function(current, view, width, height, context)
    inline = { view = history.copy(view), preview = context and context.preview };
    return draw_inline(current, view, width, height, context);
end;
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
local function frame(seconds)
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 0.25);
    equal(app.state.broken, false, 'Full entry render remains healthy');
end
local function advance(seconds)
    for _ = 1, seconds do MOCK.frame(1); end
end
local function command(text) MOCK.fire('command', { command = text }); end
local function award(kind, amount)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, MOCK.player.server_id);
    MOCK.put(bytes, 8, 4, MOCK.player.server_id);
    MOCK.put(bytes, 16, 4, amount);
    MOCK.put(bytes, 24, 2, kind == 'lp' and 371 or 8);
    MOCK.fire('packet_in', MOCK.packet(0x02D, bytes));
    local key = kind == 'lp' and 'limit_points' or 'exp';
    MOCK.player[key] = MOCK.player[key] + amount;
    frame();
end
local function archive(id)
    for _, row in ipairs(app.services.session_history()) do if row.id == id then return row; end end
end
local function arrangement()
    local current = app.settings();
    return history.copy({ bar = current.bar, display = current.display, tracking = current.tracking, style = current.style });
end
local function cleared(label)
    local view = app.view(MOCK.now);
    equal(view.session_exp, 0, label .. ': EXP total clears');
    equal(view.session_lp, 0, label .. ': LP total clears');
    equal(view.net_exp, 0, label .. ': net EXP clears');
    equal(view.net_lp, 0, label .. ': net LP clears');
    equal(view.elapsed, 0, label .. ': elapsed time clears');
    equal(view.exp.rate, nil, label .. ': EXP/HR clears');
    equal(view.lp.rate, nil, label .. ': LP/HR clears');
    equal(view.eta, nil, label .. ': Next clears');
    equal(view.lp.eta, nil, label .. ': next merit estimate clears');
    equal(view.exp.current, MOCK.player.exp, label .. ': current EXP stays');
    equal(view.lp.current, MOCK.player.limit_points, label .. ': current LP stays');
    equal(view.merits, MOCK.player.merits, label .. ': stored merit points stay');
    for _, id in ipairs({ 'exp_rate', 'lp_rate', 'eta', 'merit_eta' }) do
        equal(drawn.parts[id], '--', label .. ': cached ' .. id .. ' displays unknown');
    end
    local blanks = 0;
    for _, text in ipairs(drawn.text) do if text == '--' then blanks = blanks + 1; end end
    equal(blanks, 4, label .. ': actual HUD draws all four cleared readings');
    equal(inline.view.exp.rate, nil, label .. ': settings preview EXP/HR clears');
    equal(inline.view.lp.rate, nil, label .. ': settings preview LP/HR clears');
end
local function click_reset()
    MOCK.clicks['Reset session'] = true;
    frame();
    frame();
end

frame();
award('exp', 600);
advance(61);
frame();
check(drawn.view.exp.rate > 0, 'EXP/HR has a real rate before reset');
check(drawn.view.eta > 0, 'Next has a real level estimate before reset');
check(drawn.parts.exp_rate ~= '--' and drawn.parts.eta ~= '--', 'Cached EXP readings are populated before reset');
local previous = app.services.session_current().id;
local layout = arrangement();
click_reset();
check(app.services.session_current().id ~= previous, 'One Reset session click starts a new session');
cleared('Button reset');
equal(archive(previous).session_exp, 600, 'Reset archives the EXP gained');
check(history.equal(arrangement(), layout), 'Button reset preserves placement, readouts, labels, colors, and tracking choices');
local first_new = app.services.session_current().id;
click_reset();
check(app.services.session_current().id ~= first_new, 'A second reset starts another fresh session');
cleared('Repeated reset');
equal(archive(first_new).session_exp, 0, 'Repeated reset archives the empty session');

award('exp', 120);
check(app.view(MOCK.now).exp.rate == nil, 'New gains wait through the rate warmup');
advance(61);
frame();
equal(app.view(MOCK.now).session_exp, 120, 'New session excludes all prior rewards');
check(drawn.view.exp.rate > 0 and drawn.view.eta > 0, 'New rate and Next appear after warmup');
app.services.session_pause(true);
previous = app.services.session_current().id;
click_reset();
cleared('Paused reset');
equal(app.view(MOCK.now).paused, true, 'Reset preserves the existing pause choice');
equal(archive(previous).session_exp, 120, 'Paused reset archives the session totals');
app.services.session_pause(false);

award('exp', 75);
advance(61);
frame();
previous = app.services.session_current().id;
MOCK.file_replace_error = true;
click_reset();
equal(app.services.session_current().id, previous, 'Failed archive save keeps the current session');
equal(app.view(MOCK.now).session_exp, 75, 'Failed archive save preserves EXP gained');
check(drawn.view.exp.rate > 0 and drawn.view.eta > 0, 'Failed archive save preserves the rate and estimate');
equal(archive(previous), nil, 'Failed archive does not move the active record into history');
check(app.services.session_problem() ~= nil, 'Failed archive save exposes its error');
MOCK.file_replace_error = false;
click_reset();
cleared('Archive retry');
equal(archive(previous).session_exp, 75, 'Retry archives the preserved totals');

MOCK.player.main_job, MOCK.player.main_level = 2, 75;
MOCK.player.exp, MOCK.player.exp_needed = 10000, rules.tnl[75];
MOCK.player.limit_points, MOCK.player.mode = 2500, 'exp';
frame();
award('exp', 300);
MOCK.player.mode = 'lp';
frame();
award('lp', 900);
advance(61);
frame();
check(drawn.view.exp.rate > 0 and drawn.view.lp.rate > 0, 'Both EXP and LP rates are populated on the level-75 job');
check(drawn.view.eta > 0 and drawn.view.lp.eta > 0, 'Next and next-merit estimates are populated in LP mode');
check(drawn.parts.lp_rate ~= '--' and drawn.parts.merit_eta ~= '--', 'Cached LP readings are populated');
previous = app.services.session_current().id;
layout = arrangement();
click_reset();
cleared('Button LP reset');
equal(archive(previous).session_exp, 300, 'Button reset archives EXP from the level-75 session');
equal(archive(previous).session_lp, 900, 'Button reset archives LP from the level-75 session');
check(history.equal(arrangement(), layout), 'LP button reset preserves the arrangement');
MOCK.player.mode = 'exp';
frame();
award('exp', 100);
MOCK.player.mode = 'lp';
frame();
award('lp', 450);
advance(61);
frame();
check(drawn.view.exp.rate > 0 and drawn.view.lp.rate > 0 and drawn.view.eta > 0,
    'Both rates and Next are populated again before testing sample reset');
previous = app.services.session_current().id;
app.settings().preview.show, app.settings().preview.scenario = true, 'Merits';
local begin_combo = imgui.BeginCombo;
imgui.BeginCombo = function(label, ...) return label == '##Preview source' or begin_combo(label, ...); end;
MOCK.clicks.Sample = true;
frame();
imgui.BeginCombo = begin_combo;
equal(drawn.preview, true, 'Game bar sample is active before command reset');
equal(inline.preview, true, 'Settings sample is active before command reset');
command('/momentum reset');
frame();
check(app.services.session_current().id ~= previous, 'Command reset starts a new session');
equal(app.settings().preview.show, false, 'Command reset switches the game bar back to live readings');
equal(drawn.preview, false, 'Rendered game bar uses the fresh live session');
equal(inline.preview, false, 'Command reset switches the settings preview back to live readings');
cleared('Command LP reset');
equal(archive(previous).session_exp, 100, 'Command reset archives EXP totals from both modes');
equal(archive(previous).session_lp, 450, 'Command reset archives LP totals');
check(history.equal(arrangement(), layout), 'Command reset preserves layout and tracking choices');
award('lp', 150);
equal(app.view(MOCK.now).lp.rate, nil, 'Fresh LP rate waits through warmup');
equal(app.view(MOCK.now).lp.eta, nil, 'Fresh merit estimate waits through warmup');
advance(61);
frame();
equal(app.view(MOCK.now).session_exp, 0, 'Renewed LP gains do not restore old EXP totals');
equal(app.view(MOCK.now).session_lp, 150, 'Renewed LP gains exclude the old session');
check(drawn.view.lp.rate > 0 and drawn.view.eta > 0 and drawn.view.lp.eta > 0, 'Fresh LP rate and merit estimates appear after warmup');
equal(#MOCK.commands, 0, 'Reset testing sends no gameplay commands');
return { count = count };
