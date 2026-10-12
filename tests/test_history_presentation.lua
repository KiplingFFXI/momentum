local defaults = require('ui.defaults');
local details = require('ui.details');
local settings = defaults.make();
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local date, dates, history_calls, legacy_calls = os.date, 0, 0, 0;
os.date = function(...) dates = dates + 1; return date(...); end;
local rows = {
    { id = '1:new', name = 'Latest camp', job_name = 'WAR', created = 1700000000, saved = 1700000500 },
    { id = '1:old', name = 'Earlier camp', job_name = 'WHM', created = 1699990000, saved = 1699990500 },
};
local services = {
    session_history = function() history_calls = history_calls + 1; return rows; end,
    session_list = function() legacy_calls = legacy_calls + 1; error('The stable history service should be used.'); end,
};
local seen, open;
local ui = {
    section = function(title) return title == 'Saved sessions' and open ~= false; end,
    note = function(text) seen.words[#seen.words + 1] = text; end,
    tip = function() end, help = function() end,
    combo = function(_, label, choices, callback) seen.label, seen.choices, seen.choose = label, choices, callback; end,
    buttons = function() end,
};
local function draw()
    seen = { words = {} };
    details.sessions(settings, {}, services, ui);
    return seen;
end
local first = draw();
eq(#first.choices, 2, 'Both completed sessions are listed');
eq(first.choices[1].value, '1:new', 'Archive order is preserved');
eq(dates, 4, 'Archive dates are formatted once per record');
for _ = 1, 120 do draw(); end
eq(seen.choices, first.choices, 'Unchanged history reuses the choice array');
eq(dates, 4, 'Steady rendering does not reformat history dates');
eq(legacy_calls, 0, 'Stable history avoids the fresh-copy list service');
eq(rows[1].label, nil, 'Presentation never adds fields to manager records');
first.choose('1:old');
draw();
eq(seen.label, first.choices[2].name, 'Selected older record remains selected');
eq(dates, 4, 'Changing selection uses the cached dates');
eq(table.concat(seen.words, '\n'):find('Started ' .. date('%Y-%m-%d %H:%M', rows[2].created), 1, true) ~= nil, true,
    'Selected dates belong to the selected record');
rows = { rows[1], { id = '1:old', name = 'Renamed camp', job_name = 'WHM', created = 1699990000, saved = 1699990600 } };
draw();
eq(seen.label:find('Renamed camp', 1, true) == 1, true, 'Successful rename refreshes selected label');
eq(seen.choices == first.choices, false, 'New archive identity rebuilds choices');
eq(dates, 8, 'Changed archive refreshes dates');
rows = { rows[1] };
draw();
eq(seen.choices[1].value, '1:new', 'Deleted selection falls back to the remaining record');
eq(dates, 10, 'Delete refreshes only remaining records');
rows = { { id = '2:new', name = 'Other character', job = 3 } };
draw();
eq(seen.label, 'Other character - 3 - Date unknown', 'Character change replaces all old labels');
eq(table.concat(seen.words, '\n'):find('Started Unknown   |   Saved Unknown', 1, true) ~= nil, true, 'Unknown timestamps stay unknown');
eq(dates, 10, 'Unknown dates are not formatted as epoch zero');
rows = {};
draw();
eq(seen.choices, nil, 'Empty archive removes the selector');
local calls_before = history_calls;
open = false;
draw();
eq(history_calls, calls_before, 'Collapsed history does not query archives');
open = true;
local current = { id = 'legacy:active', name = 'Current' };
local archived = { id = 'legacy:old', name = 'Legacy old', created = 1 };
services.session_history = nil;
services.session_current = function() return current; end;
services.session_list = function() return { current, archived }; end;
draw();
eq(#seen.choices, 1, 'Fallback service still excludes the current session');
eq(seen.choices[1].value, archived.id, 'Fallback retains archived records');
archived.name = 'Changed externally';
draw();
eq(seen.label:find('Changed externally', 1, true) == 1, true, 'Fallback fresh lists are not cached by record identity');
os.date = date;
return { count = count };
