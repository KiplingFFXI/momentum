local sound = require('core.sound');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function key(path) return path:gsub('/', '\\'):gsub('\\+$', ''):lower(); end
local function setup(name)
    sound.close(true);
    sound.invalidate();
    MOCK.fs[sound.BUILT_IN], MOCK.fs[sound.FOLDER] = true, true;
    MOCK.fs[sound.BUILT_IN .. name], MOCK.fs[sound.FOLDER .. name] = true, false;
    MOCK.sound_attributes, MOCK.sound_copies, MOCK.sound_copy_error = {}, {}, nil;
    MOCK.sound_contents = { [sound.BUILT_IN .. name] = 'original audio' };
end

local checked_exists, original_exists = 0, ashita.fs.exists;
ashita.fs.exists = function(path) checked_exists = checked_exists + 1; return original_exists(path); end;
local scans = MOCK.find_opened or 0;
local name = 'storage-test.wav';
setup(name);
equal(#MOCK.sound_copies, 0, 'Loading and invalidating do not copy custom sounds');
equal(MOCK.find_opened or 0, scans, 'Location protection does not enumerate sound folders');
local location = sound.location(name);
equal(location.kind, 'addon', 'Addon-local custom sound has an explicit origin');
equal(location.can_save, true, 'Addon-local custom sound can be copied explicitly');
equal(location.path, sound.BUILT_IN .. name, 'The existing playback source remains visible');
local first_reads = checked_exists;
local first_attributes = MOCK.sound_attribute_reads;
for _ = 1, 120 do equal(sound.location(name), location, 'Origin reuses the selected-sound snapshot'); end
equal(checked_exists, first_reads, 'Visible warning frames do not poll the file system');
equal(MOCK.sound_attribute_reads, first_attributes, 'Cached origin and permanent-copy checks do not repeat native filesystem reads');
equal(sound.use(name, true), true, 'Custom sound remains selectable before saving');
equal(sound.play(35), true, 'Custom playback still starts normally');
local active = MOCK.sound_workers[#MOCK.sound_workers];
local workers, stopped = #MOCK.sound_workers, MOCK.sound_terminations or 0;
local saved, message = sound.save_custom(name);
equal(saved, true, 'The explicit action copies the custom sound');
equal(type(message), 'string', 'A successful copy provides clear feedback');
equal(#MOCK.sound_copies, 1, 'Only one native copy is requested');
equal(MOCK.sound_copies[1].source, sound.BUILT_IN .. name, 'The source is inside the addon sound folder');
equal(MOCK.sound_copies[1].destination, sound.FOLDER .. name, 'The destination is outside the replaceable addon');
equal(MOCK.fs[sound.BUILT_IN .. name], true, 'The original sound remains in place');
equal(MOCK.sound_contents[sound.FOLDER .. name], 'original audio', 'The permanent copy retains the audio');
equal(#MOCK.sound_workers, workers, 'Copying never launches an audio decoder');
equal(MOCK.sound_terminations or 0, stopped, 'Copying never stops active playback');
equal(active.process.code, 259, 'The active worker keeps running');
equal(sound.is_open(name), true, 'The selected sound is unchanged');
equal(sound.location(name).saved_copy, true, 'Successful copying is acknowledged until refresh');
equal(sound.location(name).can_save, false, 'The same successful copy is not offered repeatedly');
MOCK.fs[sound.BUILT_IN .. name] = false;
sound.invalidate();
equal(sound.location(name).kind, 'permanent', 'After addon replacement the permanent copy is available');
equal(sound.use(name, true), true, 'The old filename remains selectable after addon replacement');
equal(sound.play(35), true, 'Playback survives replacement of the addon sound file');
equal(MOCK.sound_workers[#MOCK.sound_workers].path, sound.FOLDER .. name, 'Playback falls back to permanent storage');

name = 'collision-test.mp3';
setup(name);
MOCK.fs[sound.FOLDER .. name] = true;
MOCK.sound_contents[sound.FOLDER .. name] = 'different existing audio';
saved, message = sound.save_custom(name);
equal(saved, false, 'An existing permanent filename is never overwritten');
equal(message, 'A file with this name already exists in the permanent folder. Rename one of the files and try again.', 'A conflict gives a clear next step');
equal(#MOCK.sound_copies, 0, 'A known conflict does not attempt a copy');
equal(MOCK.sound_contents[sound.FOLDER .. name], 'different existing audio', 'A collision preserves the existing audio');
equal(sound.location(name).saved_copy, false, 'An unrelated same-named file is not claimed as a saved copy');
MOCK.fs[sound.FOLDER .. name] = nil;
MOCK.fs[sound.FOLDER .. name:upper()] = true;
saved = sound.save_custom(name);
equal(saved, false, 'Case-only filename collisions remain protected');
equal(#MOCK.sound_copies, 0, 'Case-only conflicts also avoid copying');

name = 'failure-test.wav';
setup(name);
MOCK.sound_copy_error = 5;
saved, message = sound.save_custom(name);
equal(saved, false, 'A denied copy reports failure');
equal(type(message), 'string', 'Copy failures are visible');
equal(MOCK.fs[sound.BUILT_IN .. name], true, 'Copy failure preserves the original');
equal(sound.location(name).saved_copy, false, 'A failed copy is not reported as protected');
equal(sound.use(name, true), true, 'The original custom sound remains usable after failure');

for _, override in ipairs({
    { source = true, flags = 0x480 },
    { folder = sound.BUILT_IN, flags = 0x410 }, { folder = sound.FOLDER, flags = 0x410 },
    { folder = sound.FOLDER:match('^(.-)[\\/]sounds[\\/]$'), flags = 0x410 },
}) do
    setup(name);
    local target = override.source and sound.BUILT_IN .. name or override.folder;
    MOCK.sound_attributes[key(target)] = override.flags;
    equal(sound.save_custom(name), true, 'Intentional linked files and folders remain compatible');
    equal(MOCK.sound_contents[sound.FOLDER .. name], 'original audio', 'Linked-path copying preserves the sound bytes');
    equal(MOCK.fs[sound.BUILT_IN .. name], true, 'A linked source remains untouched');
end
for _, override in ipairs({
    { source = true, flags = 0x10 }, { source = true, flags = false },
    { folder = sound.FOLDER, flags = 0x80 }, { folder = sound.FOLDER, flags = false },
}) do
    setup(name);
    local target = override.source and sound.BUILT_IN .. name or override.folder;
    MOCK.sound_attributes[key(target)] = override.flags;
    equal(sound.save_custom(name), false, 'Missing files and invalid file/folder types are refused');
    equal(#MOCK.sound_copies, 0, 'An invalid source or destination folder never reaches CopyFile');
end
setup(name);
MOCK.sound_attributes[key(sound.FOLDER .. name)] = 0x400;
equal(sound.save_custom(name), false, 'An existing destination link remains a filename collision');
equal(#MOCK.sound_copies, 0, 'A destination link is never overwritten');

name = string.rep('x', 196) .. '.wav';
setup(name);
equal(sound.save_custom(name), true, 'The full supported custom filename can be copied');
equal(MOCK.sound_copies[1].destination, sound.FOLDER .. name, 'The filename is not truncated');
for _, invalid in ipairs({ '../bad.wav', 'folder/file.mp3', 'C:bad.wav', string.rep('x', 197) .. '.wav', 'bad.txt' }) do
    equal(sound.save_custom(invalid), false, 'Invalid sound names cannot select a copy destination');
end
name = 'FF VII Save.mp3';
setup(name);
equal(sound.location(name).kind, 'bundled', 'Bundled sound priority and origin are unchanged');
equal(sound.save_custom(name), false, 'Bundled assets are not copied as custom audio');
equal(#MOCK.sound_copies, 0, 'Bundled choices perform no copy');
equal(MOCK.find_opened or 0, scans, 'All explicit copy tests leave directory enumeration unchanged');
ashita.fs.exists = original_exists;
sound.close(true);
return { count = count };
