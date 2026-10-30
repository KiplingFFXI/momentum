local app = assert(MOMENTUM_TEST, 'Run shared-character checks with --full');
local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local main_settings, alt_settings;

local function open_profiles()
    local settings = app.settings();
    settings.window.open, settings.window.tab = true, 'Profiles';
    settings.window.sections['Profiles/Characters'] = true;
    settings.preview.show = false;
    PREVIEW.settings = settings;
end

app.settings().display.labels.progress = 'Main EXP';
app.settings().display.show_subjob = true;
app.settings().preview.show = false;
require('ui.settings_window').use_live_preview();
MOCK.now = MOCK.now + .3;
app.sample(MOCK.now);
main_settings = defaults.copy(app.settings());
alt_settings = defaults.make();
alt_settings.appearance_version, alt_settings.style.palette_version = 2, 1;
alt_settings.display.labels.progress = 'Alt EXP';
alt_settings.display.show_subjob = false;
open_profiles();

function PREVIEW.switch_shared_character(which)
    if which == 'main' then
        MOCK.player.name, MOCK.player.server_id, MOCK.player.main_job = 'Tester', 1001, 1;
        MOCK.player.sub_job, MOCK.player.sub_level = 13, 25;
        MOCK.settings.switch_character(main_settings);
    else
        MOCK.player.name, MOCK.player.server_id, MOCK.player.main_job = 'Second', 1002, 2;
        MOCK.player.sub_job, MOCK.player.sub_level = 6, 20;
        MOCK.settings.switch_character(alt_settings);
    end
    local gap = app.view(MOCK.now);
    assert(gap.valid == false and gap.subjob_name == nil, 'Character switching retained old job information');
    MOCK.now = MOCK.now + .3;
    app.sample(MOCK.now);
    open_profiles();
end

function PREVIEW.assert_shared_character(which, shared)
    local settings, view = app.settings(), app.view(MOCK.now);
    local expected_label = which == 'alt' and not shared and 'Alt EXP' or PREVIEW.main_label or 'Main EXP';
    assert(settings.shared == shared, 'The actual sharing checkbox did not keep its choice');
    assert(settings.display.labels.progress == expected_label, 'The character loaded the wrong layout label');
    assert(settings.display.show_subjob == (shared or which == 'main'), 'The character loaded the wrong subjob toggle');
    local expected_job = which == 'main' and 'WAR 50 / NIN 25' or shared and 'MNK 50 / THF 20' or 'MNK 50';
    assert(readouts.value('job', view, settings) == expected_job, 'The shared layout retained another character\'s jobs or levels');
    assert(app.state.broken == false, 'Sequential sharing broke the entry render');
end

function PREVIEW.save_unshared_main()
    PREVIEW.main_label = 'Main after sharing';
    app.settings().display.labels.progress = PREVIEW.main_label;
    app.services.save();
end

function PREVIEW.remember_main()
    assert(app.state.dirty == false, 'The unshared main edit did not finish saving');
    main_settings = defaults.copy(app.settings());
end

local draw = PREVIEW.draw;
PREVIEW.draw = function()
    draw();
    PREVIEW.settings = app.settings();
end;
