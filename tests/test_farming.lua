local farming = require('core.farming')
local json = require('json')
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function near(actual, expected, message)
    checks = checks + 1
    assert(actual and math.abs(actual - expected) < 0.0001, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function copy(value) return json.decode(json.encode(value)) end

local state = farming.new()
local config = { selected_item = 100, goal = 2, goal_unit = 'stacks', stack_size = 12,
    wanted = { ['100'] = true }, prices = { ['100'] = 25, ['101'] = 0 } }
equal(state:view(0, config).total, 0, 'A new session has zero receipts')
equal(state:view(0, config).rate, nil, 'A new session has no rate')
equal(state:view(0, config).estimated_value, nil, 'No priced loot is unknown rather than zero value')
equal(state:received(100, 1, 0, config), false, 'No receipts before a valid character baseline')
equal(state:found(100, 1, 0), false, 'No pool totals before a valid character baseline')
equal(state:mob_gil(50, 0), false, 'No mob gil before a valid character baseline')
equal(state:observe(true, 10), true, 'Current character enables tracking')
equal(state:found(100, 2, 10), true, 'Observed pool quantity accepted separately')
equal(state:mob_gil(50, 10), true, 'Observed mob gil accepted separately')
equal(state:view(20, config).elapsed, 0, 'Pool appearances and mob gil do not start the item clock')
equal(state:received(100, 12, 20, config), true, 'Received quantity is counted in units')
local view = state:view(20, config)
equal(view.total, 12, 'A stack of twelve is twelve items')
equal(view.selected.count, 12, 'Selected quantity follows the same unit count')
equal(view.selected.goal, 24, 'Two stack goal uses the selected stack size')
equal(view.selected.goal_remaining, 12, 'Goal remaining is in individual units')
near(view.selected.goal_fraction, 0.5, 'Goal fill uses actual units')
equal(view.selected.goal_complete, false, 'Half a goal is incomplete')
equal(view.estimated_value, 300, 'Unit price values only received loot')
equal(view.mob_gil, 50, 'Mob gil remains separate from estimated item value')
equal(view.pool_found, 2, 'Pool found remains separate from personal receipts')
local alerts = state:take_alerts()
equal(#alerts, 1, 'Wanted receipt creates one alert')
equal(alerts[1].id, 'farm_item', 'Wanted alert has its own type')
equal(alerts[1].count, 12, 'Wanted alert retains quantity')
equal(#state:take_alerts(), 0, 'Taking alerts does not replay them')
state:received(100, 12, 30, config)
alerts = state:take_alerts()
equal(#alerts, 2, 'Reaching the target creates the wanted and goal notices')
equal(alerts[2].id, 'farm_goal', 'Goal alert is separate')
equal(alerts[2].goal, 24, 'Goal alert carries the individual-unit target')
state:received(101, 2, 40, config)
equal(state:view(79, config).rate, nil, 'Rate needs a full active minute after the first receipt')
view = state:view(80, config)
near(view.rate, 26 * 60, 'Overall items per hour uses the common item clock')
near(view.selected.rate, 24 * 60, 'Selected rate uses the same common clock')
equal(view.elapsed, 60, 'Clock starts at the first accepted receipt')
equal(view.last_seconds, 40, 'Last item age uses active farming time')
equal(view.selected.last_seconds, 50, 'Watched item age has its own last receipt')
equal(view.selected.goal_remaining, 0, 'Completed goal has nothing remaining')
equal(view.selected.goal_complete, true, 'Completed goal is known')
equal(view.estimated_value, 600, 'A known zero price remains priced')
equal(view.unpriced_count, 0, 'All recorded quantities have prices')
near(view.value_rate, 36000, 'Estimated item value rate excludes mob gil and wallet changes')
local first_rows = state:rows(80, config)
equal(#first_rows, 2, 'Item table has one row per distinct item')
equal(first_rows[1].item_id, 100, 'Most received item appears first')
equal(first_rows[1].count, 24, 'Item table preserves quantity')
equal(first_rows[2].price, 0, 'A zero manual price remains distinct from unknown')
equal(state:rows(80.2, config), first_rows, 'Repeated table requests in the same displayed second are cached')
equal(state:view(80.3, config), view, 'Repeated summary requests are cached')
config.prices['100'] = 30
state:invalidate()
equal(state:view(80.4, config).estimated_value, 720, 'In-place price changes invalidate the cached summary')
equal(state:rows(80.5, config)[1].price, 30, 'Price edits also update cached table rows')

state:set_paused(true, 90)
equal(state:received(100, 99, 100, config), false, 'Paused receipts do not count')
equal(state:found(100, 1, 101), false, 'Paused pool totals do not count')
equal(state:mob_gil(999, 102), false, 'Paused mob gil does not count')
view = state:view(190, config)
equal(view.total, 26, 'Pause preserves personal quantity')
equal(view.pool_found, 2, 'Pause preserves pool found')
equal(view.mob_gil, 50, 'Pause preserves mob gil')
equal(view.elapsed, 70, 'Pause freezes item time')
state:set_paused(false, 200)
state:received(102, 1, 210, config)
view = state:view(220, config)
equal(view.elapsed, 90, 'Paused duration is excluded')
equal(view.total, 27, 'Resume never catches up ignored receipts')
equal(view.unpriced_count, 1, 'Missing prices are reported')
equal(view.estimated_value, 720, 'Unpriced items do not get an invented price')
equal(#state:take_alerts(), 0, 'Unwatched receipt and resume do not replay alerts')
state:discontinuity(230)
equal(state:view(1000, config).elapsed, 100, 'An unavailable character stops the item clock')
equal(state:received(100, 1, 1001, config), false, 'A gap cannot create receipts')
state:observe(true, 1010)
view = state:view(1020, config)
equal(view.elapsed, 110, 'A fresh valid baseline resumes the clock without offline time')
equal(view.total, 27, 'Reconnecting does not invent missed loot')

local saved = copy(state:export(1020))
local restored = farming.new()
equal(restored:restore(saved, 5000), true, 'Farming totals survive a JSON round trip')
equal(restored:view(6000, config).elapsed, 110, 'Restore waits for a fresh character baseline')
equal(restored:received(100, 1, 6001, config), false, 'Restore cannot count before a fresh baseline')
restored:observe(true, 6010)
equal(restored:view(6020, config).elapsed, 120, 'Restored active time continues after the new baseline')
equal(restored:view(6020, config).total, 27, 'Restored item totals are retained')
equal(restored:view(6020, config).pool_found, 2, 'Restored pool totals are retained')
equal(restored:view(6020, config).mob_gil, 50, 'Restored mob gil is retained')
equal(#restored:take_alerts(), 0, 'Restore does not replay old goal or item notices')
local target = restored:view(6020, config).total
for _, change in ipairs({
    { 'version', 2 }, { 'total', -1 }, { 'total', 1.25 }, { 'total', 28 },
    { 'pool_found', -1 }, { 'mob_gil', '50' }, { 'elapsed', -1 },
    { 'elapsed', math.huge }, { 'paused', 1 }, { 'partial', nil }, { 'started', false },
    { 'last_elapsed', 1000 }, { 'items', {} }, { 'recent', false },
}) do
    local bad = copy(saved)
    bad[change[1]] = change[2]
    equal(restored:restore(bad, 0), false, 'Malformed payload rejected: ' .. change[1])
    equal(restored:view(6020, config).total, target, 'Rejected restore leaves the active session intact')
end
local bad = copy(saved)
bad.items[2].item_id = bad.items[1].item_id
equal(restored:restore(bad, 0), false, 'Repeated saved item IDs are rejected')
bad = copy(saved); bad.items[1].last_elapsed = -1
equal(restored:restore(bad, 0), false, 'Negative item receipt time is rejected')
bad = copy(saved); bad.recent[1].item_id = 65535
equal(restored:restore(bad, 0), false, 'Recent rows must belong to received items')
bad = copy(saved); bad.recent[1].count = 999
equal(restored:restore(bad, 0), false, 'Recent rows cannot invent more than recorded quantities')
bad = copy(saved); bad.recent[1].at = -1
equal(restored:restore(bad, 0), false, 'Negative recent times are rejected')
bad = copy(saved); bad.items.extra = bad.items[1]
equal(restored:restore(bad, 0), false, 'Saved item arrays cannot contain hidden map rows')

restored:set_paused(true, 6030)
restored:reset(6040)
view = restored:view(6050, config)
equal(restored.paused, true, 'Reset keeps the paused choice')
equal(view.total, 0, 'Reset clears item totals')
equal(view.pool_found, 0, 'Reset clears pool totals')
equal(view.mob_gil, 0, 'Reset clears mob gil')
equal(view.rate, nil, 'Reset clears the item rate immediately')
equal(view.last_seconds, nil, 'Reset clears last receipt')
equal(view.elapsed, 0, 'Reset clears farming elapsed')
equal(#view.recent, 0, 'Reset clears recent items')
equal(view.selected.goal_complete, false, 'Reset clears goal progress')
equal(restored:received(100, 1, 6060, config), false, 'Reset does not resume a paused session')
restored:set_paused(false, 6070)
equal(restored:received(100, 24, 6070, config), true, 'Reset keeps the valid character baseline')
equal(#restored:take_alerts(), 2, 'A new session can reach its goal again')
config.goal = 1
equal(restored:view(6070, config).selected.goal_complete, true, 'Lowering a goal updates its view')
equal(#restored:take_alerts(), 0, 'Changing a goal does not create a retroactive alert')
restored:received(100, 1, 6071, config)
alerts = restored:take_alerts()
equal(#alerts, 1, 'Already achieved goal does not alert again')
equal(alerts[1].id, 'farm_item', 'Only the new wanted receipt alerts')

local bounded = farming.new()
bounded:observe(true, 0)
for id = 1, 1024 do equal(bounded:received(id, 1, 0), true, 'Distinct received item within cap') end
equal(bounded:received(1025, 1, 0), false, 'New distinct item beyond cap is rejected')
equal(bounded:view(0).partial, true, 'Bounded totals disclose incomplete tracking')
equal(bounded:view(0).total, 1024, 'Bounded total matches its recorded item rows')
equal(bounded:received(1, 1, 0), true, 'An existing item still counts at the distinct cap')
equal(#bounded:view(0).recent, 25, 'Recent receipts remain bounded')
equal(#bounded:rows(0), 1024, 'The requested item table remains bounded')
equal(bounded:restore(copy(bounded:export(0)), 0), true, 'A full bounded session restores')

local capped_alerts = farming.new()
capped_alerts:observe(true, 0)
for index = 1, 100 do capped_alerts:received(100, 1, index, config) end
equal(#capped_alerts:take_alerts(), 64, 'Pending alerts remain bounded during a burst')
equal(capped_alerts:view(100, config).total, 100, 'Alert limits never discard item totals')
local blank = farming.new()
equal(blank:restore(copy(blank:export(0)), 0), true, 'Empty sessions round trip')
blank:observe(true, 0)
blank:mob_gil(100, 1)
equal(blank:restore(copy(blank:export(1)), 100), true, 'Mob-gil-only sessions round trip without an item clock')
equal(blank:view(200).elapsed, 0, 'Mob-gil-only session does not invent item time')
local maximum = { version = 1, total = 1000000000000, pool_found = 1000000000000,
    mob_gil = 1000000000000, elapsed = 60, started = true, paused = false, partial = false,
    last_elapsed = 0, items = { { item_id = 100, count = 1000000000000, last_elapsed = 0 } }, recent = {} }
local limited = farming.new()
equal(limited:restore(maximum, 0), true, 'Documented maximum totals can be restored')
limited:observe(true, 0)
equal(limited:received(100, 1, 0), false, 'Receipt total cannot overflow its saved bound')
equal(limited:found(100, 1, 0), false, 'Pool total cannot overflow its saved bound')
equal(limited:mob_gil(1, 0), false, 'Mob gil cannot overflow its saved bound')
view = limited:view(0, { prices = { ['100'] = 999999999 } })
equal(view.partial, true, 'A total bound is visible as partial tracking')
equal(view.value_partial, true, 'An unsafe estimated value is marked incomplete')
equal(view.estimated_value, nil, 'Unsafe estimated values are not rounded into a false known amount')
equal(view.total, maximum.total, 'Bounds leave already recorded item totals intact')
local clean = farming.new()
clean:observe(true, 0)
for _, invalid in ipairs({ 0, -1, 65536, 1.5, '100', false, math.huge, {} }) do
    equal(clean:received(invalid, 1, 0), false, 'Invalid item ID cannot become loot')
end
for _, invalid in ipairs({ 0, -1, 1000, 1.5, '1', false, math.huge, {} }) do
    equal(clean:received(100, invalid, 0), false, 'Invalid receipt quantity cannot become loot')
end
clean:received(100, 1, 0)
local sorts, iterations = 0, 0
local old_sort, old_pairs = table.sort, pairs
table.sort = function(...) sorts = sorts + 1; return old_sort(...) end
pairs = function(value)
    if value == clean.items then iterations = iterations + 1 end
    return old_pairs(value)
end
for i = 1, 60 do clean:view(i / 100) end
equal(iterations, 1, 'Steady summary frames do not walk item totals repeatedly')
equal(sorts, 0, 'Summary views never sort the item list')
clean:rows(1)
equal(sorts, 1, 'The first requested breakdown sorts once')
clean:rows(2)
equal(sorts, 1, 'A new displayed second updates rates without sorting again')
clean:received(101, 2, 3)
equal(clean:rows(3)[1].item_id, 101, 'A changed quantity updates breakdown ordering')
equal(sorts, 2, 'Received loot invalidates the cached order once')
table.sort, pairs = old_sort, old_pairs
return { count = checks }
