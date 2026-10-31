local sound = require('core.sound');
local function available(name) MOCK.fs[sound.FOLDER .. name] = true; end
local function finish(name, at, code)
    assert(sound.use(name, false));
    assert(sound.play(0));
    sound.update(at);
    MOCK.sound_workers[#MOCK.sound_workers].process.code = code;
    sound.update(at + 0.5);
end
available('broken.wav'); available('another.wav'); available('working.wav');
finish('broken.wav', 0, 3221225477);
finish('another.wav', 1, 7);
local original_problem = sound.problem('broken.wav');
assert(type(original_problem) == 'string');
for index = 1, 4 do
    finish('working.wav', index * 30, 0);
    assert(not sound.use('broken.wav', false), 'A working alert must not rearm another broken file');
    assert(not sound.use('BROKEN.WAV', false), 'A case-only filename alias must not bypass failure protection');
    assert(sound.problem('broken.wav') == original_problem, 'Other alerts must leave this error visible');
end
assert(#MOCK.sound_workers == 6, 'Only the two original failures and working alerts may launch');
assert(sound.use('', true));
assert(not sound.use('broken.wav', false) and not sound.use('another.wav', false), 'Choosing None for an alert must leave failed-file protection intact');
assert(sound.use('broken.wav', true), 'An explicit retry clears just this file');
assert(sound.problem('broken.wav') == nil and sound.problem('another.wav') ~= nil);
finish('broken.wav', 150, 7);
sound.invalidate();
sound.files();
assert(not sound.use('broken.wav', false), 'Reopening the lazy sound list must not retry a broken file');
sound.refresh();
assert(sound.problem('broken.wav') == nil and sound.problem('another.wav') == nil, 'Explicit Refresh retries repaired files');
finish('broken.wav', 180, 0);
sound.close(true);
return 'Per-file failures survive other alerts, case aliases, and lazy refresh; explicit retry remains available';
