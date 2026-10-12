local app = assert(MOMENTUM_TEST, 'Run this fixture with --full');
local imgui = require('imgui');
local hud = require('ui.hud');
local history = require('ui.history');
local settings = app.settings();
local draw = PREVIEW.draw;

settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y, settings.bar.width, settings.bar.height = 40, 40, 1000, 28;
settings.window.open, settings.window.tab = true, 'Session';
settings.window.x, settings.window.y, settings.window.width, settings.window.height = 40, 120, 920, 660;
settings.display.order = { 'progress', 'rate', 'eta', 'session' };
settings.display.divider = ' | ';
settings.display.auto_layout = false;
for id in pairs(settings.display.enabled) do settings.display.enabled[id] = false; end
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
settings.tracking.window = 0;
settings.preview.show, settings.preview.scenario = true, 'Leveling';

MOCK.now = 1;
app.sample(MOCK.now);
local bytes = MOCK.bytes(28);
MOCK.put(bytes, 4, 4, MOCK.player.server_id);
MOCK.put(bytes, 8, 4, MOCK.player.server_id);
MOCK.put(bytes, 16, 4, 1000);
MOCK.put(bytes, 24, 2, 8);
MOCK.fire('packet_in', MOCK.packet(0x02D, bytes));
MOCK.player.exp = MOCK.player.exp + 1000;
MOCK.now = 1.25;
app.sample(MOCK.now);
MOCK.now = 181;
local initial = app.view(MOCK.now);
assert(initial.session_exp == 1000 and initial.rate > 0 and initial.eta > 0, 'Seeded real EXP rate and Next estimate');
assert(app.services.session_save('Before mouse reset'));
local previous_id = app.services.session_current().id;
local arrangement;

PREVIEW.reset_calls, PREVIEW.paint_text = 0, {};
local reset = app.services.session_reset;
app.services.session_reset = function(...)
    PREVIEW.reset_calls = PREVIEW.reset_calls + 1;
    return reset(...);
end;

-- Observe the actual ImGui text without replacing drawing or mouse handling.
local get_list = imgui.GetWindowDrawList;
imgui.GetWindowDrawList = function(...)
    local list = get_list(...);
    local add_text = list.AddText;
    list.AddText = function(self, font, size, position, color, value)
        local target = PREVIEW.paint_target;
        if target then
            local texts = PREVIEW.paint_text[target];
            texts[#texts + 1] = value;
        end
        return add_text(self, font, size, position, color, value);
    end;
    return list;
end;
local draw_hud, draw_inline = hud.draw, hud.draw_inline;
hud.draw = function(current, view, context)
    PREVIEW.hud_view = { preview = context.preview, rate = view.rate, eta = view.eta };
    PREVIEW.paint_target = 'hud';
    local result = draw_hud(current, view, context);
    PREVIEW.paint_target = nil;
    return result;
end;
hud.draw_inline = function(current, view, width, height, context)
    PREVIEW.inline_view = { preview = context.preview, rate = view.rate, eta = view.eta };
    PREVIEW.paint_target = 'inline';
    local result = draw_inline(current, view, width, height, context);
    PREVIEW.paint_target = nil;
    return result;
end;

function PREVIEW.assert_sample()
    local live = app.view(MOCK.now);
    assert(live.session_exp == 1000 and live.rate > 0 and live.eta > 0, 'Real session still tracks behind samples');
    assert(PREVIEW.reset_calls == 0, 'No reset before the mouse click');
    for _, target in ipairs({ 'hud', 'inline' }) do
        local view = PREVIEW[target .. '_view'];
        local text = table.concat(PREVIEW.paint_text[target], ' '):gsub('%s+', ' ');
        assert(view.preview and view.rate == 8500 and view.eta == 3198, target .. ': sample rate and Next are active');
        assert(text:find('8,500', 1, true) and text:find('~53:18', 1, true), target .. ': sample numbers actually draw: ' .. text);
    end
    PREVIEW.samples_verified = true;
    arrangement = history.copy({ bar = settings.bar, display = settings.display, tracking = settings.tracking, style = settings.style });
end

function PREVIEW.assert_reset()
    assert(PREVIEW.samples_verified, 'Both sample displays were verified before the click');
    assert(PREVIEW.reset_calls == 1, 'Exactly one mouse click invokes reset once');
    assert(app.services.session_current().id ~= previous_id, 'One click starts a fresh session');
    local live = app.view(MOCK.now);
    assert(live.session_exp == 0 and live.session_lp == 0 and live.net_exp == 0 and live.net_lp == 0, 'Session totals clear');
    assert(live.rate == nil and live.eta == nil and live.exp.rate == nil and live.lp.rate == nil, 'Both rates and Next clear');
    assert(live.exp.current == MOCK.player.exp and live.lp.current == MOCK.player.limit_points, 'Character balances remain intact');
    assert(settings.preview.show == false, 'The game bar returns to live readings');
    for _, target in ipairs({ 'hud', 'inline' }) do
        local view = PREVIEW[target .. '_view'];
        local text = table.concat(PREVIEW.paint_text[target], ' '):gsub('%s+', ' ');
        assert(not view.preview and view.rate == nil and view.eta == nil, target .. ': live readings clear on the next frame');
        assert(text:find('EXP/HR --', 1, true) and text:find('Next --', 1, true), target .. ': cleared readings actually draw: ' .. text);
        assert(not text:find('8,500', 1, true) and not text:find('~53:18', 1, true), target .. ': old sample text disappears');
    end
    local archived;
    for _, entry in ipairs(app.services.session_history()) do if entry.id == previous_id then archived = entry; end end
    assert(archived and archived.closed and archived.session_exp == 1000 and archived.name == 'Before mouse reset', 'Old session is archived with its name and EXP');
    assert(history.equal(arrangement, { bar = settings.bar, display = settings.display, tracking = settings.tracking, style = settings.style }), 'Reset preserves the bar and tracking choices');
    assert(not app.state.broken, 'Full entry remains healthy');
    PREVIEW.passed = true;
end

return function()
    PREVIEW.paint_text = { hud = {}, inline = {} };
    draw();
    if PREVIEW.frame == PREVIEW.last_frame then
        assert(PREVIEW.passed, 'The reset replay reached its final assertions');
        PREVIEW.log('PASS: one real mouse click archives EXP and clears sample HUD and settings EXP/HR and Next.');
    end
end;
