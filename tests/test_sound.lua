local sound = require('core.sound');
local count = 0;
local function check(value, message)
    count = count + 1;
    assert(value, message);
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function commands(prefix)
    local found = 0;
    for _, command in ipairs(MOCK.mci or {}) do
        if command:sub(1, #prefix) == prefix then found = found + 1; end
    end
    return found;
end
MOCK.fs[sound.BUILT_IN] = true;
MOCK.fs[sound.FOLDER] = true;
MOCK.dirs = {
    [sound.BUILT_IN] = { 'FF VII Save.mp3', 'FF IX Moogle.mp3', 'README.txt' },
    [sound.FOLDER] = { 'ff vii save.MP3', 'B.wav', 'a.MP3', '../bad.wav', 'C:\bad.mp3', 'bad".wav', 'junk.txt' },
};
for _, name in ipairs({ 'FF VII Save.mp3', 'FF IX Moogle.mp3' }) do MOCK.fs[sound.BUILT_IN .. name] = true; end
for _, name in ipairs({ 'a.MP3', 'B.wav' }) do MOCK.fs[sound.FOLDER .. name] = true; end
sound.refresh();
equal(#sound.files(), 4, 'Sound list filters unsafe names and duplicates');
equal(sound.files()[1], 'FF IX Moogle.mp3', 'Bundled sounds sorted first');
equal(sound.files()[2], 'FF VII Save.mp3', 'Second bundled sound');
equal(sound.files()[3], 'a.MP3', 'Custom sounds sorted separately');
equal(sound.files()[4], 'B.wav', 'WAV accepted');
equal(sound.find('ff vii save'), 'FF VII Save.mp3', 'Find without extension');
equal(sound.find('b.WAV'), 'B.wav', 'Find ignores case');
equal(sound.find('absent'), nil, 'Absent sound stays absent');
equal(#(MOCK.mci or {}), 0, 'Refresh never plays or opens a sound');

for _, name in ipairs({ '../bad.wav', 'folder/file.mp3', 'folder\\file.wav', 'C:bad.mp3', 'bad".wav', 'bad\n.wav', 'bad..wav', 'a.txt', 123 }) do
    equal(sound.use(name, true), false, 'Unsafe sound name rejected');
end
equal(commands('open '), 0, 'Unsafe names never reach MCI');
equal(sound.use('missing.wav', true), false, 'Missing file rejected');
equal(commands('open '), 0, 'Missing file never reaches MCI');
check(sound.use('FF VII Save.mp3', true), 'Open bundled sound');
check(sound.is_open('FF VII Save.mp3'), 'Selected file held open');
check(sound.play(50), 'Play selected sound');
equal(commands('setaudio '), 1, 'Volume set once');
check(MOCK.mci[#MOCK.mci - 1]:find('volume to 500', 1, true), 'Percent volume converted');
check(sound.play(50), 'Repeat playback');
equal(commands('setaudio '), 1, 'Unchanged volume reused');
check(sound.play(150), 'High volume clamped');
check(MOCK.mci[#MOCK.mci - 1]:find('volume to 1000', 1, true), 'Maximum volume clamped');
check(sound.play(-1), 'Low volume clamped');
check(MOCK.mci[#MOCK.mci - 1]:find('volume to 0', 1, true), 'Minimum volume clamped');
check(sound.use('B.wav', true), 'Switch to custom sound');
check(MOCK.mci[#MOCK.mci]:find(sound.FOLDER .. 'B.wav', 1, true), 'Custom sound uses custom folder');
sound.close();
equal(sound.is_open('B.wav'), false, 'Close releases handle');
equal(sound.play(50), false, 'Cannot play a closed handle');

MOCK.mci = {};
MOCK.mci_code = function (command) return command:match('^open ') and 1 or 0; end;
equal(sound.use('FF VII Save.mp3', true), false, 'Open failure contained');
check(sound.problem('FF VII Save.mp3') ~= nil, 'Open failure visible to settings');
local attempts = commands('open ');
for _ = 1, 10 do sound.use('FF VII Save.mp3'); end
equal(commands('open '), attempts, 'Failed open is not retried each frame');
sound.use('FF VII Save.mp3', true);
equal(commands('open '), attempts + 1, 'Explicit retry tries once');

MOCK.mci = {};
MOCK.mci_code = nil;
check(sound.use('FF VII Save.mp3', true), 'Sound recovers after explicit retry');
local plays = 0;
MOCK.mci_code = function (command)
    if command:match('^play ') then plays = plays + 1; return plays == 1 and 1 or 0; end
    return 0;
end;
check(sound.play(75), 'Playback retries once after reopening');
equal(plays, 2, 'Transient playback failure has exactly two attempts');
equal(commands('open '), 2, 'Playback reopens once');

MOCK.mci = {};
MOCK.mci_code = function (command) return command:match('^play ') and 1 or 0; end;
equal(sound.play(75), false, 'Persistent playback failure contained');
equal(commands('play '), 2, 'Persistent playback failure has bounded retry');
equal(commands('open '), 1, 'Persistent failure reopens only once');
check(sound.problem('FF VII Save.mp3') ~= nil, 'Persistent playback failure visible');
equal(sound.is_open('FF VII Save.mp3'), false, 'Failed handle closed');
check(sound.use('', true), 'Empty choice disables playback');
equal(sound.problem('FF VII Save.mp3'), nil, 'Disabling clears the error');

MOCK.no_winmm = true;
package.loaded['core.sound'] = nil;
local unavailable = require('core.sound');
equal(unavailable.use('FF VII Save.mp3', true), false, 'Missing Windows audio library contained');
equal(unavailable.play(100), false, 'Missing audio library stays quiet');
MOCK.no_winmm = false;
package.loaded['core.sound'] = sound;
MOCK.mci_code = nil;
return count .. ' silent sound checks';
