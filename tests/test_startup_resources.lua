local count = 0;
local function check(value, message)
    count = count + 1;
    assert(value, message);
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end

local ffi = require('ffi');
local load_library = ffi.load;
local library_loads = 0;
ffi.load = function(name)
    if name == 'winmm' then library_loads = library_loads + 1; end
    return load_library(name);
end;
package.loaded['core.sound'] = nil;
local sound = require('core.sound');
equal(library_loads, 0, 'Import leaves the audio library unloaded');
sound.refresh();
sound.close();
check(sound.use('', true), 'An empty sound choice still disables audio');
equal(sound.use('missing-startup-test.wav', true), false, 'Missing sound remains unavailable');
equal(library_loads, 0, 'Listing, closing, disabling and missing files do not load audio');
MOCK.fs[sound.BUILT_IN .. 'startup-test.wav'] = true;
check(sound.use('startup-test.wav', true), 'First requested sound is selected');
equal(library_loads, 0, 'Selecting a sound leaves audio unloaded');
MOCK.fs[sound.WORKER] = true;
check(sound.play(50), 'Deferred sound can play');
equal(library_loads, 0, 'Playback never loads WinMM into the game');
sound.close();
check(sound.use('startup-test.wav', true), 'Another sound request can select the file');
equal(library_loads, 0, 'Reselecting never opens an audio library');
sound.close();

local saved_worker = package.loaded['core.sound_worker'];
MOCK.no_kernel32 = true;
package.loaded['core.sound'] = nil;
package.loaded['core.sound_worker'] = nil;
local unavailable = require('core.sound');
equal(library_loads, 0, 'Unavailable playback also stays deferred on import');
check(unavailable.use('startup-test.wav', true), 'Selection is independent of playback resources');
equal(unavailable.play(50), false, 'Missing process library is handled');
check(unavailable.problem('startup-test.wav') ~= nil, 'Unavailable sound keeps its error message');
equal(library_loads, 0, 'Failed playback never falls back to in-game WinMM');
MOCK.no_kernel32 = false;
ffi.load = load_library;
package.loaded['core.sound'] = sound;
package.loaded['core.sound_worker'] = saved_worker;

local imgui = require('imgui');
local get_io, add_font, push_font = imgui.GetIO, imgui.AddFontFromFileTTF, imgui.PushFont;
local exists = ashita.fs.exists;
local locked, font_checks, font_loads, io_reads = true, 0, 0, 0;
local pushed;
imgui.GetIO = function()
    io_reads = io_reads + 1;
    return { Fonts = { Locked = locked } };
end;
ashita.fs.exists = function(path)
    font_checks = font_checks + 1;
    return path:match('tahoma%.ttf$') == nil;
end;
imgui.AddFontFromFileTTF = function(path)
    font_loads = font_loads + 1;
    if path:match('arial%.ttf$') then error('Test font unavailable'); end
    if path:match('verdana%.ttf$') then return nil; end
    return 'loaded-' .. path:match('([^\\]+)%.ttf$');
end;
imgui.PushFont = function(face) pushed = face; end;
package.loaded['ui.fonts'] = nil;
local fonts = require('ui.fonts');
equal(font_loads, 0, 'Import does not register fonts');
equal(fonts.load(), true, 'Default Ashita needs no custom font');
equal(fonts.load('Ashita'), true, 'Ashita is available while the atlas is locked');
equal(fonts.load('Unknown font'), true, 'Unknown font choices use the fallback');
equal(io_reads, 0, 'Default and unknown fonts do not read the atlas');
equal(font_checks, 0, 'Default and unknown fonts do not check files');
equal(fonts.load('Segoe UI'), false, 'A locked atlas leaves the selected font pending');
equal(font_checks, 0, 'Pending fonts do not scan files during drawing');
equal(font_loads, 0, 'Pending fonts do not modify the locked atlas');
locked = false;
equal(fonts.load('Segoe UI'), true, 'An unlocked atlas loads the selected font');
equal(font_checks, 1, 'Only the selected font file is checked');
equal(font_loads, 1, 'Only the selected font is registered');
equal(fonts.failed('Segoe UI'), false, 'A loaded font remains available');
fonts.push('Segoe UI', 18);
equal(pushed, 'loaded-segoeui', 'A loaded font is selected normally');
fonts.push('Arial', 18);
equal(pushed, 'default', 'An unloaded font uses the Ashita font');
equal(font_checks, 1, 'Drawing does not check another font file');
equal(font_loads, 1, 'Drawing does not register another font');
local reads = io_reads;
locked = true;
for _ = 1, 5 do equal(fonts.load('Segoe UI'), true, 'An already loaded font remains available during drawing'); end
equal(io_reads, reads, 'Cached loading does not poll the atlas');
equal(font_checks, 1, 'Cached loading does not check font files');
equal(font_loads, 1, 'Cached loading does not add duplicate fonts');
equal(fonts.load('Arial'), false, 'A newly selected font still waits for an unlocked atlas');
equal(font_checks, 1, 'A new locked selection does not scan files');

locked = false;
equal(fonts.load('Arial'), true, 'A registration error completes with fallback');
equal(fonts.failed('Arial'), true, 'A registration error keeps the fallback');
equal(fonts.load('Tahoma'), true, 'A missing selected font completes with fallback');
equal(fonts.failed('Tahoma'), true, 'A missing font keeps the fallback');
equal(fonts.load('Verdana'), true, 'An empty font result completes with fallback');
equal(fonts.failed('Verdana'), true, 'An empty font result keeps the fallback');
equal(font_checks, 4, 'Each new selected font is checked once');
equal(font_loads, 3, 'The missing font is not registered');
reads = io_reads;
locked = true;
for _, name in ipairs({ 'Arial', 'Tahoma', 'Verdana' }) do
    equal(fonts.load(name), true, 'A failed font is not retried during drawing');
    fonts.push(name, 18);
    equal(pushed, 'default', 'A failed selection uses the Ashita font');
end
equal(io_reads, reads, 'Failed cached selections do not poll the atlas');
equal(font_checks, 4, 'Failed cached selections do not check files again');
equal(font_loads, 3, 'Failed cached selections do not retry registration');
local names = fonts.names();
equal(#names, 7, 'All font choices remain in the menu');
for index, name in ipairs({ 'Ashita', 'Segoe UI', 'Arial', 'Tahoma', 'Verdana', 'Calibri', 'Consolas' }) do
    equal(names[index], name, 'The font menu keeps its existing order');
end
locked = false;
equal(fonts.load('Calibri'), true, 'Another font can be selected later');
equal(fonts.load('Consolas'), true, 'The final font choice can also be selected');
equal(font_checks, 6, 'All six custom fonts are checked only after being selected');
equal(font_loads, 5, 'All present selected fonts receive one registration attempt');
fonts.push('Calibri', 18);
equal(pushed, 'loaded-calibri', 'A later font selection uses its registered face');
imgui.GetIO, imgui.AddFontFromFileTTF, imgui.PushFont = get_io, add_font, push_font;
ashita.fs.exists = exists;
return count .. ' startup resource checks';
