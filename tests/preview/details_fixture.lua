-- Synthetic server observations for UI review, not a client capture.
local view = PREVIEW.view;
view.sync_active, view.sync_level, view.effective_level, view.sync_gap = true, 50, 50, 11;
view.sync_source, view.sync_penalty, view.sync_rate, view.sync_age = 'server', 16, 15, 3;
view.food, view.food_name, view.food_seconds = true, 'Meat Mithkabob', 840;
view.dedication, view.dedication_pool, view.dedication_bonus, view.dedication_seconds = true, 850, 50, 1830;
view.no_exp_reason = 'sync_target';
local ring = require('ui.defaults').copy(require('data.phoenix_rules').rings[15762]);
ring.id, ring.key, ring.charges, ring.recast, ring.ready, ring.equip_delay = 15762, 'fixture', 4, 125, false, 8;
view.rings = { available = true, entries = { ring } };
PREVIEW.session_rows = {
    { id = 'current', name = 'Current session', job = 1, job_name = 'WAR', created = 1700000000, elapsed = 2700,
        session_exp = 6375, session_lp = 0, net_exp = 6200, net_lp = 0, merits_gained = 0, best_chain = 5, active = true },
    { id = 'saved', name = 'Saved camp', job = 1, job_name = 'WAR', created = 'fixture', elapsed = 3600,
        session_exp = 8500, session_lp = 0, net_exp = 8500, net_lp = 0, merits_gained = 0, best_chain = 5, active = false },
};
