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
    return path:match('segoeui%.ttf$') ~= nil or path:match('arial%.ttf$') ~= nil;
end;
imgui.AddFontFromFileTTF = function(path)
    font_loads = font_loads + 1;
    if path:match('arial%.ttf$') then error('Test font unavailable'); end
    return 'loaded-segoeui';
end;
imgui.PushFont = function(face) pushed = face; end;
package.loaded['ui.fonts'] = nil;
local fonts = require('ui.fonts');
equal(font_loads, 0, 'Import does not register fonts');
equal(fonts.load(), false, 'A locked atlas leaves font loading pending');
equal(font_checks, 0, 'Pending fonts do not scan files during drawing');
equal(font_loads, 0, 'Pending fonts do not modify the locked atlas');
locked = false;
equal(fonts.load(), true, 'An unlocked atlas completes font loading');
equal(font_checks, 6, 'Available font files are checked once');
equal(font_loads, 2, 'Only present font files are registered');
equal(fonts.failed('Segoe UI'), false, 'A loaded font remains available');
equal(fonts.failed('Arial'), true, 'A failed font retains its fallback');
equal(fonts.failed('Tahoma'), true, 'A missing font retains its fallback');
fonts.push('Segoe UI', 18);
equal(pushed, 'loaded-segoeui', 'A loaded font is selected normally');
fonts.push('Arial', 18);
equal(pushed, 'default', 'A failed font uses the Ashita font');
local reads = io_reads;
locked = true;
for _ = 1, 5 do equal(fonts.load(), true, 'Completed loading remains complete during drawing'); end
equal(io_reads, reads, 'Completed loading does not poll the atlas');
equal(font_checks, 6, 'Completed loading does not scan fonts again');
equal(font_loads, 2, 'Completed loading does not add duplicate fonts');

locked = false;
ashita.fs.exists = function() return false; end;
package.loaded['ui.fonts'] = nil;
local missing = require('ui.fonts');
equal(missing.load(), true, 'No installed fonts still completes with fallback');
equal(missing.failed('Segoe UI'), true, 'No installed fonts keeps the fallback visible');
equal(font_loads, 2, 'No installed fonts creates no new font objects');
imgui.GetIO, imgui.AddFontFromFileTTF, imgui.PushFont = get_io, add_font, push_font;
ashita.fs.exists = exists;
return count .. ' startup resource checks';
