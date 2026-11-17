-- One validated reward transaction; safe from gameobject and GUI callers.
-- Default: one Checkpoint.batch save; nested grants ride the outer save.
-- Frequent grants may use durable=false and ride the next save (abilities can
-- still autosave). Callers changing their own state commit first in the same
-- batch, with once_key; retries treat already_granted as done. Disk failure
-- keeps committed memory, reports saved=false; callers show the standard save
-- failure notice. Death save suspension discards unsaved gains on restore.
-- Listeners and provider apply/defaults never save/autosave; providers never grant.
-- Final gives cannot generally be undone; only their new stat ledger keys can.
local Spec = require "mvtk.game.grant_spec"
local Wallet = require "mvtk.core.wallet"
local Inventory = require "mvtk.core.inventory"
local Flags = require "mvtk.core.flags"
local Events = require "mvtk.core.game_events"
local Checkpoint = require "mvtk.core.checkpoint"
local Ability = require "mvtk.abilities.ability_manager"
local Progression = require "mvtk.game.progression.progression_manager"
local Travel = require "mvtk.core.fast_travel"
local Collectibles = require "mvtk.collectibles.collectible_manager"
local Stats = require "mvtk.player.permanent_stats"
local Delivery = require "mvtk.game.delivery"
local C = require "mvtk.core.constants"
local Keys = require "mvtk.core.key_ids"
local M = { APPLIERS = {} }

function M.runtime_env()
    local env = Spec.authoring_env({ items = require "developer.config.items",
        collectible_types = require "developer.config.collectible_types", key_ids = Keys,
        upgrades = require "developer.config.upgrades", weapons = require "developer.config.weapons",
        charms = require "developer.config.charms",
        reward_text = require "developer.config.reward_text", format_currency = Wallet.format })
    env.leveling_enabled = require("developer.config.runtime_settings").section("leveling", require "developer.config.leveling").enabled == true
    env.ability_info = Ability.get_ability_info
    env.is_known_point = Travel.is_known_point
    env.travel_points = Travel.points
    -- Preserve registered names while allowing ids from unloaded rooms until
    -- the world-census consumer installs a complete validation predicate.
    env.skip_travel_validation = not Travel.is_known_point
    return env
end
local function exhausted(e, env)
    if e.kind == "weapon_tier" then return require("mvtk.combat.weapon_state").tier(e.weapon) >= e.tier end
    if e.kind == "ability" then return Ability.is_ability_unlocked(e.id) end
    if e.kind == "upgrade" then return Stats.has("upgrade:" .. e.id) end
    if e.kind == "flag" then return Flags.has(e.id) end
    if e.kind == "fast_travel" then return Travel.is_unlocked(e.id) end
    if e.kind == "item" then
        return Spec.is_unique(e.id, env) and Inventory.has(e.id, 1)
    end
    return false
end
local function refusal(code, ds, message) return nil, { code = code, diags = ds or {}, message = message or code } end
local function totals(entries)
    local money, items = 0, {}
    for _, e in ipairs(entries) do
        if e.kind == "currency" then money = money + e.amount
        elseif e.kind == "item" then items[e.id] = (items[e.id] or 0) + e.count end
    end
    return money, items
end
local function affordable(entries)
    local money, items = totals(entries)
    if not Wallet.can_afford(money) then return false, {key="gameplay.requires_cost", params={cost={currency=money}}} end
    for id, count in pairs(items) do
        if not Inventory.has(id, count) then
            local name = Spec.item_name(id, M.runtime_env())
            return false, {key="gameplay.requires_item", params={name=type(name)=="table" and name or {text=name}, count=count}}
        end
    end
    return true
end
function M.prepare(gives, opts)
    if opts ~= nil and type(opts) ~= "table" then return refusal("invalid", {}, "Options must be a table.") end
    opts = opts or {}
    local env, options = M.runtime_env(), {}
    for k, v in pairs(opts) do options[k] = v end
    options.source, options.reason = opts.source or "reward", opts.reason or "reward"
    options.durable = opts.durable ~= false
    options.set_flags = {}
    local option_ds = {}
    for _, key in ipairs({ "source", "reason" }) do
        if opts[key] ~= nil and type(opts[key]) ~= "string" then
            return refusal("invalid", {}, key .. " must be text.")
        end
    end
    if opts.position ~= nil and not (type(opts.position) == "table" and type(opts.position.x) == "number"
        and type(opts.position.y) == "number" and math.abs(opts.position.x) < math.huge
        and math.abs(opts.position.y) < math.huge) then
        return refusal("invalid", { { severity = "error", code = "grant_needs_position", entry = 0,
            message = "Position must contain finite numeric x and y." } })
    end
    for _, key in ipairs({ "once_key", "instance_id" }) do
        if opts[key] ~= nil and (type(opts[key]) ~= "string" or opts[key]:match("^%s*$")) then
            option_ds[#option_ds + 1] = { severity = "error", code = "grant_needs_identity", message = key .. " must be nonempty text.", entry = 0 }
        end
    end
    if type(opts.set_flags or {}) ~= "table" then
        return refusal("invalid", {}, "set_flags must be a table.")
    end
    for k, v in pairs(opts.set_flags or {}) do
        local kind = type(v)
        if type(k) ~= "string" or k == "" or (kind ~= "string" and kind ~= "boolean"
            and (kind ~= "number" or v ~= v or math.abs(v) == math.huge)) then
            return refusal("invalid", {}, "set_flags requires text keys and scalar values.")
        end
        options.set_flags[k] = v
    end
    if #option_ds > 0 then return refusal("invalid", option_ds) end
    env.position, env.once_key, env.instance_id = opts.position, opts.once_key, opts.instance_id
    if opts.position then options.position = { x = opts.position.x, y = opts.position.y } end
    local ok, ds, entries = Spec.validate(gives, env)
    if not ok and not opts.drop_invalid then return refusal("invalid", ds) end
    local bad, filtered = {}, {}
    for _, d in ipairs(ds) do
        if d.severity == "error" then
            bad[d.entry] = true
            d.severity, d.code = "warning", "grant_dropped"
        end
    end
    for _, e in ipairs(entries) do if not bad[e.entry] then filtered[#filtered + 1] = e end end
    local costs_ok, cost_ds, costs = Spec.validate(opts.costs or {}, env)
    for _, e in ipairs(costs) do
        if e.kind ~= "currency" and e.kind ~= "item" then
            costs_ok = false
            cost_ds[#cost_ds + 1] = { severity = "error", code = "grant_wrong_kind", entry = e.entry,
                message = "Costs accept only currency and item entries." }
        end
    end
    if not costs_ok then return refusal("invalid", cost_ds) end
    for _, d in ipairs(cost_ds) do ds[#ds + 1] = d end
    if opts.once_key and Flags.has("grant_once:" .. opts.once_key) then return refusal("already_granted", ds) end
    local can_pay, message = affordable(costs)
    if not can_pay then return refusal("insufficient", ds, message) end
    local active, seen = {}, {}
    for _, e in ipairs(filtered) do
        local key = e.kind .. ":" .. tostring(e.id)
        local unique = e.kind == "item" and Spec.is_unique(e.id, env)
        if e.kind == "upgrade" and not exhausted(e, env)
            and not require("mvtk.economy.upgrades").requires_met(e.id) then
            return refusal("prerequisite", ds)
        end
        if e.kind == "weapon_tier" and not exhausted(e, env) then
            local state = require "mvtk.combat.weapon_state"
            if not state.owns(e.weapon) or state.tier(e.weapon) ~= e.tier - 1 then return refusal("prerequisite", ds) end
        end
        local single = e.kind == "weapon_tier" or unique or e.kind == "ability" or e.kind == "flag" or e.kind == "fast_travel" or e.kind == "upgrade"
        if not exhausted(e, env) and not (single and seen[key]) then
            if unique then e.count = 1 end
            active[#active + 1] = e; seen[key] = true
        end
    end
    if opts.refuse_if_exhausted and #active == 0 then return refusal("exhausted", ds) end
    return { entries = active, costs = costs, opts = options, env = env, diags = ds,
        text = Spec.describe(active, env) }
end
local function set_flag(tx, key, value)
    local old = Flags.get(key)
    tx.undo[#tx.undo + 1] = function()
        if old == nil then Flags.clear(key) else Flags.set(key, old) end
    end
    Flags.set(key, value)
end
M.APPLIERS.weapon_tier = function(e, tx)
    local state = require "mvtk.combat.weapon_state"
    local before = state.tier(e.weapon)
    assert(state.owns(e.weapon) and before == e.tier - 1, "Weapon tier prerequisite changed")
    -- Register first: setters may mutate and then throw.
    tx.undo[#tx.undo + 1] = function() assert(state.set_tier(e.weapon, before), "Weapon tier undo failed") end
    assert(state.set_tier(e.weapon, e.tier), "Weapon tier give failed")
end
M.APPLIERS.xp = function(e, tx)
    if require("developer.config.runtime_settings").section("leveling", require "developer.config.leveling").enabled then
        Progression.add_experience(e.amount, tx.plan.opts.source)
    end
end
M.APPLIERS.currency = function(e, tx)
    assert(Wallet.add(e.amount, tx.plan.opts.reason) ~= false, "Currency give failed")
end
M.APPLIERS.item = function(e) Inventory.add_item(e.id, e.count) end
M.APPLIERS.flag = function(e, tx) set_flag(tx, e.id, true) end
M.APPLIERS.fast_travel = function(e, tx)
    local was_unlocked = Travel.is_unlocked(e.id)
    tx.undo[#tx.undo + 1] = function() if not was_unlocked then Travel.revoke_reward(e.id) end end
    assert(Travel.grant_reward(e.id) ~= false, "Travel give failed")
    set_flag(tx, "fast_travel_" .. e.id, true)
end
M.APPLIERS.upgrade = function(e, tx)
    local key = "upgrade:" .. e.id
    local existed = Stats.has(key)
    local ok, applied = pcall(require("mvtk.economy.upgrades").apply, e.id)
    if not existed and Stats.has(key) then
        tx.undo[#tx.undo + 1] = function() Stats.forget(key) end
    end
    if not ok then error(applied, 0) end
    assert(applied or existed, "Upgrade give failed: " .. e.id)
end
M.APPLIERS.ability = function(e, tx)
    Progression.unlock_ability(e.id, { enabled = true, source = tx.plan.opts.source })
    assert(Ability.is_ability_unlocked(e.id), "Ability stayed locked: " .. e.id)
    Delivery.to_player(C.MSG.GRANT_ABILITY, { ability = e.id, enabled = true })
end
M.APPLIERS.collectible = function(e, tx)
    for _ = 1, e.count do
        tx.unit = tx.unit + 1
        local opts = tx.plan.opts
        local id = "grant:" .. (opts.once_key or opts.instance_id) .. (tx.unit > 1 and "#" .. tx.unit or "")
        local key = "pickup:" .. id
        local existed = Stats.has(key)
        -- Inspect even a throwing applier: it may record before the failure.
        local applied, result = pcall(Collectibles.execute_collection_behavior, { id = id, type = e.id,
            config = tx.plan.env.collectible_types[e.id], position = opts.position })
        if not existed and Stats.has(key) then
            tx.undo[#tx.undo + 1] = function() Stats.forget(key) end
        end
        if type(result) == "table" and type(result.undo) == "function" then
            tx.undo[#tx.undo + 1] = result.undo
        end
        if not applied then error(result, 0) end
        assert(result ~= false, "Collectible give failed: " .. e.id)
    end
end
function M.commit(plan)
    assert(type(plan) == "table" and plan.opts and not plan.used, "Expected an unused grant plan")
    plan.used = true
    local mark = Events.hold()
    local tx = { plan = plan, undo = {}, unit = 0 }
    local ok, err = pcall(function()
        -- Inventory owns currency too. Snapshot before any call, including calls
        -- that mutate and then throw or return false.
        local before = Inventory.export()
        tx.undo[#tx.undo + 1] = function() Inventory.import(before) end
        local can_pay = affordable(plan.costs)
        assert(can_pay, "Costs changed after preparation")
        if plan.opts.once_key then assert(not Flags.has("grant_once:" .. plan.opts.once_key), "Grant already committed") end
        for _, e in ipairs(plan.costs) do
            if e.kind == "currency" then assert(Wallet.spend(e.amount, plan.opts.reason), "Currency spend failed")
            else assert(Inventory.consume(e.id, e.count), "Item consume failed") end
        end
        for _, e in ipairs(plan.entries) do
            if Spec.KINDS[e.kind].reversible then M.APPLIERS[e.kind](e, tx) end
        end
        for key, value in pairs(plan.opts.set_flags) do set_flag(tx, key, value) end
        if plan.opts.once_key then set_flag(tx, "grant_once:" .. plan.opts.once_key, true) end
        for _, e in ipairs(plan.entries) do
            if not Spec.KINDS[e.kind].reversible then M.APPLIERS[e.kind](e, tx) end
        end
        Events.emit("reward_granted", { source = plan.opts.source, reason = plan.opts.reason,
            entry_count = #plan.entries, once_key = plan.opts.once_key or "" })
    end)
    if not ok then
        for i = #tx.undo, 1, -1 do
            local undone, why = pcall(tx.undo[i])
            if not undone then print("[GRANTS] Compensation failed: " .. tostring(why)) end
        end
        Events.discard(mark)
        error(err, 0)
    end
    Events.release(mark)
    return true
end
local function should_notice(plan)
    local visible = 0
    for _, e in ipairs(plan.entries) do
        if not plan.env.text.hidden_kinds[e.kind] then
            visible = visible + 1
            local def = e.kind == "collectible" and plan.env.collectible_types[e.id]
            if not def or not ((type(def.notification) == "string" and def.notification ~= "") or def.on_collect == "add_to_collection"
                or def.on_collect == "unlock_lore_entry" or def.on_collect == "add_fragment") then return true end
        end
    end
    return visible == 0 and plan.text ~= ""
end
function M.grant(gives, opts)
    local success, plan, refused = pcall(M.prepare, gives, opts)
    if not success then return false, { code = "invalid", diags = {}, message = tostring(plan) } end
    if not plan then return false, refused end
    local committed, saved, save_error = false, false, nil
    local function apply() M.commit(plan); committed = true end
    if plan.opts.durable then
        local called, result, err = pcall(Checkpoint.batch, plan.opts.reason, apply)
        saved = called and result == true
        if called then save_error = err else save_error = result end
    else
        local called, err = pcall(apply)
        if not called then save_error = err end
    end
    if not committed then return false, { code = "failed", diags = plan.diags, message = tostring(save_error) } end
    if plan.opts.notify and should_notice(plan) then Delivery.notice(plan.text, { duration = plan.env.text.notice_duration }) end
    return true, { text = plan.text, entries = plan.entries, diags = plan.diags, saved = saved, save_error = save_error }
end
function M.exchange(costs, gives, opts)
    if opts ~= nil and type(opts) ~= "table" then
        return false, { code = "invalid", diags = {}, message = "Options must be a table." }
    end
    local options = {}
    for k, v in pairs(opts or {}) do options[k] = v end
    options.costs, options.source = costs, options.source or "purchase"
    return M.grant(gives, options)
end
function M.describe(value) return Spec.describe(value, M.runtime_env()) end
function M.is_exhausted(value)
    local ok, _, entries = Spec.validate(value, M.runtime_env())
    if not ok then return false end
    for _, e in ipairs(entries) do if not exhausted(e, M.runtime_env()) then return false end end
    return true
end
function M.can_afford(costs)
    local ok, _, entries = Spec.validate(costs, M.runtime_env())
    if not ok then return false end
    for _, e in ipairs(entries) do if e.kind ~= "currency" and e.kind ~= "item" then return false end end
    return affordable(entries)
end
return M
