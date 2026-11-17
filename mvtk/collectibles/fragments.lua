-- Pure fragment accounting; dependencies may be supplied by a headless caller.
local M = {}
local cached, revision

function M.settings()
    local RuntimeSettings = require "developer.config.runtime_settings"
    local current = RuntimeSettings.revision()
    if not cached or revision ~= current then
        cached = RuntimeSettings.section("fragments", require "developer.config.fragments")
        revision = current
    end
    return cached
end

function M.add(set_id, piece_key, deps)
    deps = deps or {}
    local set = ((deps.config or M.settings()).sets or {})[set_id]
    if not set then
        (deps.warn or print)("[FRAGMENTS] Unknown fragment set: " .. tostring(set_id))
        return false
    end
    local Flags = deps.flags or require "mvtk.core.flags"
    local Stats = deps.stats or require "mvtk.player.permanent_stats"
    local Healing = set.upgrade == "heal_charges" and (deps.healing or require "mvtk.player.healing")
    local count_key, piece_flag = "fragment_count_" .. set_id, "fragment_piece_" .. piece_key
    local old_count, old_piece = Flags.get(count_key), Flags.get(piece_flag)
    local count, needed = Flags.get(count_key, 0), set.pieces
    if Flags.has(piece_flag) then
        return {count = count, needed = needed, upgraded = false, duplicate = true, undo = function() end}
    end
    local recorded, undone = {}, false
    local function undo()
        if undone then return end
        undone = true
        for i = #recorded, 1, -1 do
            if Healing then Healing.remove_bonus_charges(recorded[i]) else Stats.forget(recorded[i]) end
        end
        if old_count == nil then Flags.clear(count_key) else Flags.set(count_key, old_count) end
        if old_piece == nil then Flags.clear(piece_flag) else Flags.set(piece_flag, old_piece) end
    end
    count = count + 1
    local ok, err = pcall(function()
        Flags.set(count_key, count)
        Flags.set(piece_flag, true)
        for k = 1, math.floor(count / needed) do
            local key = "fragment:" .. set_id .. ":" .. k
            local added
            if Healing then added = Healing.add_bonus_charges(set.amount, key)
            else added = Stats.record(key, {kind = "pickup", id = set_id .. "_fragment",
                deltas = {[set.upgrade] = set.amount}}) end
            if added then recorded[#recorded + 1] = key end
        end
    end)
    if not ok then undo(); error(err, 0) end
    return {count = count, needed = needed, upgraded = #recorded > 0, undo = undo}
end

return M
