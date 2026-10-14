local count = 0;
local function check(value, message)
    count = count + 1;
    assert(value, message);
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end

local ffi = require('ffi');
local original_load, original_string = ffi.load, ffi.string;
local libraries, bounded_reads = {}, 0;
ffi.load = function(name)
    libraries[name] = (libraries[name] or 0) + 1;
    return original_load(name);
end;
ffi.string = function(value, size)
    equal(size, 260, 'Directory names always use a bounded read');
    bounded_reads = bounded_reads + 1;
    return original_string(value, size);
end;
ashita.fs.get_directory = function() error('Regex directory listing must not be used'); end;

local sound = require('core.sound');
equal(libraries.kernel32, nil, 'Import does not load the directory library');
equal(libraries.winmm, nil, 'Import does not load the audio library');
MOCK.fs[sound.BUILT_IN], MOCK.fs[sound.FOLDER] = false, false;
sound.refresh();
equal(libraries.kernel32, nil, 'Absent directories do not load the library');
equal(#sound.files(), 0, 'Absent directories leave an empty list');

local ansi_name = 'caf' .. string.char(233) .. '.wav';
MOCK.fs[sound.BUILT_IN], MOCK.fs[sound.FOLDER] = true, true;
MOCK.dirs = {
    [sound.BUILT_IN] = {
        'Z.mp3', 'B.wav', 'readme.txt', { name = 'folder.wav', attributes = 0x10 },
        { name = 'hidden.wav', attributes = 0x02 }, { name = 'linked.wav', attributes = 0x400 },
    },
    [sound.FOLDER] = {
        'b.WAV', 'a.MP3', ansi_name, 'bad..wav', 'part/sub.wav',
        { name = 'tail.wav', raw = 'tail.wav\0ignored.wav' },
        { name = 'unterminated', raw = string.rep('a', 260) },
    },
};
sound.refresh();
equal(libraries.kernel32, 1, 'First scan loads the library once');
equal(libraries.winmm, nil, 'Scanning does not load audio');
equal(MOCK.find_opened, 2, 'Both folders are enumerated');
equal(MOCK.find_closed, 2, 'Both enumeration handles close');
equal(MOCK.find_calls[1], sound.BUILT_IN .. '*', 'Bundled scan uses the full folder');
equal(MOCK.find_calls[2], sound.FOLDER .. '*', 'Custom scan uses the full folder');
equal(table.concat(sound.files(), '|'), 'B.wav|hidden.wav|linked.wav|Z.mp3|a.MP3|' .. ansi_name .. '|tail.wav',
    'Sorting, bundled-first deduplication, ANSI bytes and filtering are preserved');
check(bounded_reads > 0, 'The scanner read filenames');
equal(sound.find('b.wav'), 'B.wav', 'The bundled duplicate remains selectable');
MOCK.fs[sound.FOLDER .. ansi_name] = true;
check(sound.use(ansi_name, true), 'An ANSI filename remains playable');
check(MOCK.mci[#MOCK.mci]:find(sound.FOLDER .. ansi_name, 1, true), 'Playback keeps the selected filename bytes');
sound.refresh();
equal(libraries.kernel32, 1, 'Later scans reuse the library');
equal(libraries.winmm, 1, 'Refreshing an open sound does not reopen audio');
check(sound.is_open(ansi_name), 'Refreshing keeps the selected sound open');
sound.close();

MOCK.dirs = { [sound.BUILT_IN] = {}, [sound.FOLDER] = {} };
local closed = MOCK.find_closed;
sound.refresh();
equal(#sound.files(), 0, 'Empty scans clear the old list');
equal(MOCK.find_closed, closed, 'INVALID_HANDLE_VALUE is never closed');

MOCK.dirs[sound.BUILT_IN] = { 'first.wav', 'second.wav' };
MOCK.find_next_error = true;
sound.refresh();
equal(sound.files()[1], 'first.wav', 'An enumeration error keeps already found files');
equal(#sound.files(), 1, 'An enumeration error stops the folder scan');
equal(MOCK.find_closed, closed + 1, 'An enumeration error closes its handle');
MOCK.find_next_error = nil;

local safe_string = ffi.string;
ffi.string = function() error('Filename conversion failed'); end;
closed = MOCK.find_closed;
sound.refresh();
equal(#sound.files(), 0, 'Filename conversion failure is contained');
equal(MOCK.find_closed, closed + 1, 'Filename conversion failure closes its handle');
ffi.string = safe_string;

MOCK.find_first_error = true;
closed = MOCK.find_closed;
sound.refresh();
equal(#sound.files(), 0, 'An opening error leaves an empty list');
equal(MOCK.find_closed, closed, 'An opening error has no handle to close');
MOCK.find_first_error = nil;
MOCK.find_close_error = true;
sound.refresh();
equal(#sound.files(), 2, 'A close error is contained without losing known files');
MOCK.find_close_error = nil;

local many = {};
for index = 1, 1025 do many[index] = ('sound-%04d.wav'):format(index); end;
MOCK.dirs[sound.BUILT_IN] = many;
sound.refresh();
equal(#sound.files(), 1025, 'All valid files remain available without an arbitrary cap');
equal(sound.files()[1025], 'sound-1025.wav', 'The last valid file is retained');

MOCK.no_kernel32 = true;
package.loaded['core.sound'] = nil;
local unavailable = require('core.sound');
local before = libraries.kernel32;
for _ = 1, 3 do unavailable.refresh(); end;
equal(libraries.kernel32, before + 1, 'An unavailable directory library is not retried each refresh');
equal(#unavailable.files(), 0, 'An unavailable library does not call the regex fallback');
MOCK.no_kernel32 = nil;
ffi.load, ffi.string = original_load, original_string;
package.loaded['core.sound'] = sound;
return count .. ' directory scan checks';
