-- Same-slot replay transaction. Requests survive the boot/main collection boundary.
local Checkpoint = require "mvtk.core.checkpoint"
local Multipliers = require "mvtk.combat.multipliers"
local Copy = require("mvtk.core.save_migrations").copy
local M = {}
local cycle, pending, cached, cached_revision = 0, nil, nil, nil

local function integer(value)
    return type(value) == "number" and value == value and value < math.huge
        and math.max(0, math.floor(value)) or 0
end
function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if not cached or cached_revision ~= revision then
        cached = Runtime.section("new_game_plus", require "developer.config.new_game_plus")
        cached_revision = revision
    end
    return cached
end
function M.cycle() return cycle end
function M.current_cycle_mults()
    local cfg = M.settings()
    if cfg.enabled ~= true or cycle == 0 then return nil end
    return (cfg.cycles or {})[math.min(cycle, #(cfg.cycles or {}))]
end
M.MULTIPLIER_SOURCE = {
    id = "new_game_plus", order = 20, challenge = true, range = {0.1, 10},
    factor = function(channel) return Multipliers.table_factor(M.current_cycle_mults(), channel) end,
}
Checkpoint.register_provider("new_game_plus", {
    version = 1, order = 205,
    capture = function() return {cycle = cycle} end,
    apply = function(data) cycle = integer(type(data) == "table" and data.cycle) end,
    defaults = function() cycle = 0 end,
})

local function status(raw, cfg)
    local modules = raw and raw.modules or {}
    local completion = modules.game_completion and modules.game_completion.data
    completion = type(completion) == "table" and completion or {}
    local stored_cycle = modules.new_game_plus and modules.new_game_plus.data
    stored_cycle = type(stored_cycle) == "table" and stored_cycle or {}
    local ending_cfg = require("developer.config.runtime_settings").section(
        "game_completion", require "developer.config.game_completion")
    local allowed = #(cfg.endings or {}) == 0
    for _, id in ipairs(cfg.endings or {}) do if id == completion.id then allowed = true end end
    return {cycle = integer(stored_cycle.cycle), eligible = raw ~= nil and cfg.enabled == true
        and require("mvtk.game.endings").find(ending_cfg, completion.id) ~= nil and allowed}
end
function M.slot_status(slot)
    local raw = Checkpoint.inspect_slot(slot)
    return status(raw, M.settings())
end
function M.request(slot)
    pending = nil
    if type(slot) ~= "number" or slot < 1 or slot % 1 ~= 0 or slot == math.huge then return false end
    if not M.slot_status(slot).eligible then return false end
    pending = {slot = slot}
    return true
end

-- Pure allowlist: unknown providers and world flags always reset. Retain stored
-- versions so reapply_providers remains the sole migration/mirror authority.
function M.build_carry(modules, cfg)
    modules, cfg = modules or {}, cfg or {}
    local rules, out = cfg.carry or {}, {}
    local function keep(id, data)
        local entry = modules[id]
        if entry then out[id] = {version = entry.version, data = Copy(data or entry.data)} end
    end
    keep("difficulty")
    if rules.level and modules.progression then
        local data = modules.progression.data or {}
        keep("progression", {level = data.level, experience = data.experience})
    end
    if modules.inventory then
        local data, items = modules.inventory.data or {}, {}
        for id, n in pairs(data.items or {}) do
            local gear = type(id) == "string" and (id:sub(1,7) == "weapon_" or id:sub(1,6) == "charm_")
            if (gear and rules.equipment) or (not gear and rules.items) then items[id] = n end
        end
        keep("inventory", {items = items, currency = rules.currency and data.currency or 0})
    end
    if rules.equipment then keep("weapons"); keep("charms") end
    if rules.currency then keep("bank") end
    if rules.abilities then keep("abilities") end
    if rules.upgrades then
        keep("permanent_stats") -- Includes container, fragment and purchased upgrade ledger keys.
        if modules.healing then keep("healing", {bonus_sources = (modules.healing.data or {}).bonus_sources}) end
    end
    if rules.bestiary then keep("bestiary") end
    if rules.cutscenes_seen and modules.flags then
        local flags = {}
        for key, value in pairs(modules.flags.data or {}) do
            if type(key) == "string" and key:sub(1,14) == "cutscene_seen_" then flags[key] = Copy(value) end
        end
        keep("flags", flags)
    end
    return out
end

local function failed(reason)
    require("mvtk.core.util").safe_post("main:/toast_gui#toast", "toast", {key = "save.new_game_plus_failed"})
    return false, reason
end
function M.apply_pending(ctx)
    local request = pending
    pending = nil -- A different session/slot must never inherit an old request.
    if not request or not ctx or request.slot ~= ctx.slot then return false end
    if Checkpoint.is_save_suspended() then return false, "save_suspended" end
    if Checkpoint.slot ~= ctx.slot then return false, "slot_mismatch" end
    local raw, reason = Checkpoint.inspect_slot(ctx.slot)
    local cfg = M.settings()
    local info = status(raw, cfg)
    if not info.eligible then return false, reason or "ineligible" end
    local key = Checkpoint.key_for(ctx.slot)
    -- sys.save has no success return; both host operations can raise. Rewrite
    -- this backup on every request, including the second and later cycles.
    local written, result = pcall(sys.save, key .. "_pre_ngplus", raw)
    if not written or result == false then return failed("backup_write") end
    local checked, backup = pcall(sys.load, key .. "_pre_ngplus")
    local verified, equal = pcall(function()
        return Checkpoint.compute_checksum(backup) == Checkpoint.compute_checksum(raw)
    end)
    if not checked or not verified or not equal then return failed("backup_verify") end
    local ok, err = pcall(function()
        local carried = M.build_carry(Checkpoint.data.modules, cfg)
        Checkpoint.reset(ctx.slot)
        carried.new_game_plus = {version = 1, data = {cycle = info.cycle + 1}}
        Checkpoint.data.modules = carried
        local applied, apply_error = Checkpoint.reapply_providers()
        if not applied then error(apply_error or "reapply_failed") end
        local saved, save_error = Checkpoint.save({slot = ctx.slot, reason = "new_game_plus"})
        if not saved then error(save_error or "save_failed") end
    end)
    if ok then return true end
    -- Also roll back a refused final save. The verified copy remains available
    -- for recovery even if the host cannot restore the primary immediately.
    local restored, restore_result = pcall(sys.save, key, backup)
    local loaded, load_result = pcall(Checkpoint.load, ctx.slot)
    if not restored or restore_result == false or not loaded or not load_result then
        return failed("restore_failed:" .. tostring(err))
    end
    return failed(tostring(err))
end
function M.section()
    return {id = "new_game_plus", order = 80,
        visible = function() return cycle > 0 end,
        header = function() return {key = "records.new_game_plus"} end,
        lines = function() return {{label = {key = "records.ng_cycle", params = {cycle = cycle}}, value = ""}} end}
end
function M.on_session_start()
    require("mvtk.ui.screens.journal_records").add_section(M.section())
end
return M
