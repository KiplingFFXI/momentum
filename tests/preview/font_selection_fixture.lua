local app = assert(MOMENTUM_TEST, 'Run font selection checks with --full');
local imgui = require('imgui');
local fonts = require('ui.fonts');
local add_font, push_font = imgui.AddFontFromFileTTF, imgui.PushFont;
local settings = app.settings();
settings.style.font = 'Ashita';
settings.window.open, settings.window.tab = true, 'Appearance';
settings.window.sections['Appearance/Skin and text'] = true;
settings.preview.show = false;
PREVIEW.font_adds, PREVIEW.font_pushes = 0, 0;
local drawing = false;

imgui.AddFontFromFileTTF = function(...)
    assert(not drawing, 'Font registration ran during the UI frame');
    PREVIEW.font_adds = PREVIEW.font_adds + 1;
    return add_font(...);
end;
imgui.PushFont = function(...)
    if drawing then PREVIEW.font_pushes = PREVIEW.font_pushes + 1; end
    return push_font(...);
end;

function PREVIEW.assert_font(name, additions)
    assert(settings.style.font == name, 'The Font dropdown kept ' .. settings.style.font .. ' instead of ' .. name);
    assert(PREVIEW.font_adds == additions, 'Font selection added duplicate or unused faces');
    assert(not fonts.failed(name), 'The selected font fell back instead of loading');
    assert(PREVIEW.font_pushes >= 2, 'The selected font did not draw both the settings and bar');
    assert(app.state.broken == false, 'Font selection broke the full addon render');
end;

function PREVIEW.assert_pending_font(name, additions)
    assert(settings.style.font == name, 'The Font dropdown did not select the new face');
    assert(PREVIEW.font_adds == additions, 'The new font loaded before the next frame boundary');
    assert(fonts.failed(name), 'The new font was already registered inside the UI frame');
end;

local draw = PREVIEW.draw;
PREVIEW.draw = function()
    local selected, additions = settings.style.font, PREVIEW.font_adds;
    PREVIEW.font_pushes = 0;
    drawing = true;
    draw();
    drawing = false;
    if settings.style.font ~= selected then
        assert(PREVIEW.font_adds == additions, 'The dropdown registered a font while drawing');
    end
end;
