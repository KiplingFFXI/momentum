local ffi = require('ffi');
local original_load, libraries = ffi.load, {};
ffi.load = function(name) libraries[name] = (libraries[name] or 0) + 1; return original_load(name); end;
local sound = require('core.sound');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
MOCK.fs[sound.BUILT_IN], MOCK.fs[sound.FOLDER] = true, true;
MOCK.dirs = {
    [sound.BUILT_IN] = { 'FF VII Save.mp3', 'FF IX Moogle.mp3', 'README.txt' },
    [sound.FOLDER] = { 'ff vii save.MP3', 'B.wav', 'a.MP3', '../bad.wav', 'bad".wav', 'junk.txt' },
};
for _, name in ipairs({ 'FF VII Save.mp3', 'FF IX Moogle.mp3' }) do MOCK.fs[sound.BUILT_IN .. name] = true; end
for _, name in ipairs({ 'a.MP3', 'B.wav' }) do MOCK.fs[sound.FOLDER .. name] = true; end
sound.refresh();
equal(table.concat(sound.files(), '|'), 'FF IX Moogle.mp3|FF VII Save.mp3|a.MP3|B.wav', 'Safe sounds remain sorted, bundled first');
equal(sound.find('ff vii save'), 'FF VII Save.mp3', 'Find without extension');
equal(sound.find('b.WAV'), 'B.wav', 'Find ignores case');
equal(sound.find('absent'), nil, 'Absent sound stays absent');
equal(libraries.winmm, nil, 'Refreshing never loads a decoder in the game');
equal(MOCK.sound_workers, nil, 'Refreshing never starts playback');
for _, name in ipairs({ '../bad.wav', 'folder/file.mp3', 'folder\\file.wav', 'C:bad.mp3', 'bad".wav', 'bad\n.wav', 'bad..wav', 'a.txt', 123 }) do
    equal(sound.use(name, true), false, 'Unsafe sound name rejected');
end
equal(sound.use('missing.wav', true), false, 'Missing sound rejected');
equal(MOCK.sound_workers, nil, 'Rejected selections never start playback');
equal(sound.use('FF VII Save.mp3', true), true, 'Bundled MP3 can be selected');
equal(sound.is_open('FF VII Save.mp3'), true, 'Selected sound remains available through the public getter');
equal(MOCK.sound_workers, nil, 'Selection does not open a decoder or launch a worker');
MOCK.fs[sound.WORKER] = false;
equal(sound.play(50), false, 'Missing helper gives a useful failure');
equal(type(sound.problem('FF VII Save.mp3')), 'string', 'Missing helper failure is visible');
MOCK.fs[sound.WORKER] = true;
MOCK.fs[sound.LAUNCHER] = false;
equal(sound.use('FF VII Save.mp3', true), true, 'Selection still works without the launcher');
equal(sound.play(50), false, 'A missing launcher is reported before launch');
equal(MOCK.sound_requests, nil, 'A missing launcher does not submit a sound');
MOCK.fs[sound.LAUNCHER] = true;
equal(sound.use('FF VII Save.mp3', true), true, 'An explicit retry selects the sound');
equal(sound.play(50), true, 'Playback launches the isolated worker');
local first = MOCK.sound_workers[1];
equal(first.path, sound.BUILT_IN .. 'FF VII Save.mp3', 'Playback uses the bundled file');
equal(first.volume, 500, 'Percent volume converted');
equal(first.application, sound.WORKER, 'Only the bundled helper launches');
equal(first.inherit, 0, 'Worker does not inherit game handles');
equal(first.flags, 0x08000000, 'Worker runs without a console window');
equal(first.startup.wShowWindow, 0, 'Worker window stays hidden');
equal(libraries.winmm, nil, 'Playback never loads WinMM in the game');
equal(sound.use('B.wav', true), true, 'Custom WAV can be selected');
equal(first.process.code, 259, 'Changing a selection leaves the current sound alone');
equal(#MOCK.sound_workers, 1, 'Changing a selection never launches another sound');
equal(sound.play(150), true, 'The next Play replaces the current sound');
equal(first.process.code, 1, 'The previous worker is cancelled');
equal(first.process.closed, true, 'The previous process handle closes');
equal(MOCK.sound_workers[2].path, sound.FOLDER .. 'B.wav', 'Custom sounds keep their folder');
equal(MOCK.sound_workers[2].volume, 1000, 'High volume is clamped');
equal(sound.play(-1), true, 'A sound can play at zero volume');
equal(MOCK.sound_workers[3].volume, 0, 'Low volume is clamped');
sound.close();
equal(sound.is_open('B.wav'), false, 'Close clears the selection');
equal(MOCK.sound_workers[3].process.closed, true, 'Close releases the worker handle');
equal(sound.play(50), false, 'A closed selection cannot play');
sound.use('a.MP3', true);
equal(sound.play(75), true, 'Custom MP3 launches');
local active = MOCK.sound_workers[#MOCK.sound_workers];
sound.update(9);
active.process.code = 3221225477;
sound.update(10);
equal(type(sound.problem('a.MP3')), 'string', 'A decoder crash becomes a sound error');
equal(active.process.closed, true, 'A crashed decoder handle closes');
equal(sound.use('a.MP3', false), false, 'Failed playback does not retry on every alert');
equal(sound.use('a.MP3', true), true, 'Play can explicitly retry a failed sound');
equal(sound.play(75), true, 'An explicit retry launches a fresh worker');
active = MOCK.sound_workers[#MOCK.sound_workers];
sound.update(10.5);
active.process.code = 0;
sound.update(11);
equal(sound.problem('a.MP3'), nil, 'Successful playback clears the previous failure');
local polls = MOCK.sound_polls;
for index = 1, 100 do sound.update(11 + index / 100); end
equal(MOCK.sound_polls, polls, 'Idle frames do not poll a finished worker');
MOCK.sound_create_error = true;
equal(sound.play(75), true, 'A launch request stays asynchronous');
sound.update(13);
equal(type(sound.problem('a.MP3')), 'string', 'A launch error is visible');
MOCK.sound_create_error = nil;
equal(sound.use('', true), true, 'An empty selection disables future playback');
equal(sound.problem('a.MP3'), nil, 'Disabling clears the old error');
equal(libraries.winmm, nil, 'No scenario loads a decoder DLL in the game');
return { count = count };
