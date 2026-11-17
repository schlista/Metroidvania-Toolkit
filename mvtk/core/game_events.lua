-- Synchronous gameplay facts, safe to load in any Lua host (no dependencies).
-- Listeners may change module state and post messages (including Audio.sfx).
-- Never call gui/go/factory/physics/sound/sprite, even indirectly: Inventory
-- can emit from a GUI script. Post world effects to their owning script.
-- Never save/autosave in a listener; use Grants or Checkpoint.batch instead.
-- Modules subscribe once at load; scripts subscribe in init and off in final.
-- RoomManager.register_event and TriggerBus retain their separate routes.
local M = {}
M.EVENTS = {
    player_damaged = {fields={"amount","damage_type","over_time","lethal"}, emitter="mvtk/player/player.script", when="After accepted positive damage changes health, before statuses and death"},
    trial_started = {fields={"trial_id","room_id","goal"}, emitter="mvtk/game/fight_session.lua", when="When a trial is armed and sealed"},
    trial_completed = {fields={"trial_id","room_id","goal","rank","metric","first_clear","new_best"}, emitter="mvtk/game/fight_session.lua", when="After the result and first-clear reward inside the optional save batch"},
    trial_failed = {fields={"trial_id","room_id","reason"}, emitter="mvtk/game/fight_session.lua", when="On safe failure, or an abort while playing; reason is time, hit, defeated, incomplete or left"},
    countdown_started = {fields={"countdown_id","source"}, emitter="mvtk/game/countdown.lua", when="After countdown_<id>_active is set and saves are suspended; source is zone, condition, restart or script"},
    countdown_finished = {fields={"countdown_id","tenths","new_best","first_clear"}, emitter="mvtk/game/countdown.lua", when="After the once-key reward, finish flag and best time inside the optional save batch; tenths is the time taken"},
    countdown_failed = {fields={"countdown_id","reason"}, emitter="mvtk/game/countdown.lua", when="When a run ends without finishing; reason is time, death, cancelled or left"},
    completion_changed = {fields={"percent","previous"}, emitter="mvtk/game/completion_tracker.lua", when="When the rounded weighted completion percentage changes during play"},
    quest_started = {fields={"quest_id"}, emitter="mvtk/game/quests/quests.lua", when="After entering the first step and writing the started mirror"},
    quest_step = {fields={"quest_id", "step_id", "step"}, emitter="mvtk/game/quests/quests.lua", when="After finishing a step; step is the next one-based index"},
    quest_completed = {fields={"quest_id"}, emitter="mvtk/game/quests/quests.lua", when="After objectives finish, before explicit turn-in and rewards"},
    quest_turned_in = {fields={"quest_id"}, emitter="mvtk/game/quests/quests.lua", when="After the once-key grant and turned-in mirror inside the save batch"},
    quest_failed = {fields={"quest_id"}, emitter="mvtk/game/quests/quests.lua", when="After an active or completed quest fails and its mirror is written"},
    goal_changed = {fields={"goal_id", "previous_id"}, emitter="mvtk/game/goals.lua", when="After a new goal's goal_announced_ flag, or once when the last goal finishes; ids are empty text when there is none"},
    region_entered = {fields={"region_id", "room_id", "first_visit"}, emitter="mvtk/ui/region_titles.lua", when="When the player enters a room in another region, or the first room of a session, after the region_seen_ flag; first_visit is true on the first entry in this save"},
    npc_met = {fields={"npc_id", "npc_type", "room_id"}, emitter="mvtk/npcs/npc_memory.lua", when="After the first finished conversation with a placed NPC in this save is stored; npc_type is empty text for an NPC with no type"},
    achievement_unlocked = { fields = {"achievement_id", "category"}, emitter = "mvtk/game/progression/achievements.lua", when = "After the profile unlock is forced to disk, before feedback, reward and platform dispatch" },
    xp_gained = { fields = {"amount", "source", "total"}, emitter = "mvtk/game/progression/progression_manager.lua", when = "After a positive XP gain; never saves" },
    level_up = { fields = {"level", "previous"}, emitter = "mvtk/game/progression/progression_manager.lua", when = "Once for each level crossed by a gain" },
    item_sold = { fields = {"item_id", "count", "price", "station_kind"}, emitter = "mvtk/economy/transaction.lua", when = "After a successful sale exchange and its optional save attempt" },
    purchase_completed = { fields = {"station_kind", "catalog", "entry", "price"}, emitter = "mvtk/economy/transaction.lua", when = "After a committed purchase, inside its optional save batch" },
    encounter_cleared = { fields = {"encounter_id", "room_id", "repeatable", "clear_count"}, emitter = "mvtk/enemies/encounter_controller.lua", when = "After saved clear flags and channel, inside the optional clear save batch" },
    enemy_damaged = { fields = {"amount", "by_player", "boss", "defeated", "over_time"}, emitter = "mvtk/enemies/enemy.script; mvtk/bosses/boss_manager.lua", when = "After accepted positive damage changes health, before statuses and defeat" },
    player_parried = { fields = {"perfect"}, emitter = "mvtk/player/parry_system.lua", when = "After successful parry bookkeeping, before returning the result" },
    status_applied = { fields = {"status", "target", "source"}, emitter = "mvtk/combat/status_effects.lua", when = "On a new status start, never a refresh or added stack" },
    hazard_return = { fields = {"room_id", "lethal"}, emitter = "mvtk/player/hazard_return.lua", when = "a pending hazard return is delivered" },
    reward_granted = { fields = {"source", "reason", "entry_count", "once_key"}, emitter = "mvtk/game/grants.lua", when = "After a complete grant, before releasing held events inside the save batch" },
    enemy_defeated = { fields = {"enemy_type", "archetype", "skin", "species", "elite", "room_id", "spawn_id", "defeat_key", "spawned", "spawn_owner", "group_id", "respawn", "x", "y", "cause", "source_attack", "damage_type", "xp_value", "in_bestiary"}, emitter = "mvtk/enemies/enemy_defeats.lua", when = "After drops, unregister, group leave and spawned outcome, before death presentation" },
    boss_defeated = { fields = {"boss_id", "preset", "room_id", "x", "y", "xp"}, emitter = "mvtk/bosses/boss_manager.lua", when = "After the defeat flag inside its save batch" },
    collectible_collected = { fields = {"collectible_id", "collectible_type", "category", "room_id", "respawns"}, emitter = "mvtk/collectibles/collectible_manager.lua", when = "After a successful reward is marked collected" },
    item_added = { fields = {"item_id", "count", "total"}, emitter = "mvtk/core/inventory.lua", when = "After the stored item count changes" },
    item_removed = { fields = {"item_id", "count", "total"}, emitter = "mvtk/core/inventory.lua", when = "After removal; count is the amount actually removed" },
    currency_changed = { fields = {"delta", "total"}, emitter = "mvtk/core/inventory.lua", when = "After the clamped total changes" },
    ability_unlocked = { fields = {"ability_id", "source"}, emitter = "mvtk/game/progression/progression_manager.lua", when = "After a newly listed ability unlocks" },
    secret_found = { fields = {"secret_id", "room_id"}, emitter = "mvtk/prefabs/secret.script", when = "After a previously unset secret flag is set" },
    gate_opened = { fields = {"gate_id", "source", "temporary"}, emitter = "mvtk/world/gates/gate_manager.lua", when = "After a real unlock" },
    chest_opened = { fields = {"chest_id", "room_id"}, emitter = "mvtk/world/chest.script", when = "After opening; chest_id is the authored text" },
    player_died = { fields = {"reason"}, emitter = "mvtk/player/player_death.lua", when = "After the dead flag is set" },
    room_visited = { fields = {"room_id"}, emitter = "mvtk/map/discovery.lua", when = "On the first visit only" },
    flag_set = { fields = {"flag", "value"}, emitter = "mvtk/core/flags.lua", when = "After a string-key value changes; value only if scalar" },
    ending_reached = { fields = {"ending_id"}, emitter = "mvtk/game/completion.lua", when = "After the ending save succeeds" },
}

local listeners, holds, mutes, queue, warned = {}, {}, {}, {}, {}
local strict_mode, trace, depth = false, nil, 0
local function warn_once(key, message)
    if warned[key] then return end
    warned[key] = true
    print("[GAME_EVENTS] " .. message)
end
local function declared(name)
    if M.EVENTS[name] then return true end
    warn_once("name:" .. tostring(name), "Undeclared event: " .. tostring(name))
    return false
end
local function scalar(value)
    local kind = type(value)
    return kind == "string" or kind == "number" or kind == "boolean"
end
local function copy_payload(name, payload)
    if type(payload) ~= "table" then
        if strict_mode then error("Event payload must be a table: " .. name, 3) end
        return {}
    end
    local allowed, copy = {}, {}
    for _, field in ipairs(M.EVENTS[name].fields) do allowed[field] = true end
    for field, value in pairs(payload) do
        if allowed[field] and scalar(value) then copy[field] = value
        elseif strict_mode then error("Invalid event field: " .. name .. "." .. tostring(field), 3) end
    end
    return copy
end
function M.on(name, fn)
    if not declared(name) then return nil end
    assert(type(fn) == "function", "Event listener must be a function")
    local token = { fn = fn, name = name, active = true }
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], token)
    return token
end
function M.off(token)
    if not token then return end
    token.active = false
    local list = listeners[token.name] or {}
    for i, item in ipairs(list) do
        if item == token then table.remove(list, i); break end
    end
end
function M.emit(name, payload)
    if next(mutes) then return end
    if not declared(name) then return end
    payload = copy_payload(name, payload == nil and {} or payload)
    if next(holds) then queue[#queue + 1] = {name, payload}; return end
    if depth >= 8 then warn_once("depth", "Nested event depth exceeds 8"); return end
    depth = depth + 1
    if trace then
        local ok, err = pcall(trace, name, payload)
        if not ok then warn_once("trace", "Trace failed: " .. tostring(err)) end
    end
    -- Snapshot registration order: new subscriptions begin on the next emit;
    -- off() still takes effect immediately, including during this dispatch.
    local pending = {}
    for _, token in ipairs(listeners[name] or {}) do pending[#pending + 1] = token end
    for _, token in ipairs(pending) do
        if token.active then
            local ok, err = pcall(token.fn, payload)
            if not ok then warn_once(token, "Listener failed for " .. name .. ": " .. tostring(err)) end
        end
    end
    depth = math.max(0, depth - 1)
end
function M.hold()
    local mark = {}
    holds[mark] = #queue
    return mark
end
local function end_hold(mark, discard)
    local start = holds[mark]
    if start == nil then return end
    holds[mark] = nil
    if discard then
        for i = #queue, start + 1, -1 do queue[i] = nil end
        for token, offset in pairs(holds) do holds[token] = math.min(offset, #queue) end
    end
    if next(holds) then return end
    local pending = queue
    queue = {}
    for _, event in ipairs(pending) do M.emit(event[1], event[2]) end
end
function M.release(mark) end_hold(mark, false) end
function M.discard(mark) end_hold(mark, true) end
function M.mute()
    local token = {}
    mutes[token] = true
    return token
end
function M.unmute(token) mutes[token] = nil end
function M.strict(enabled) strict_mode = enabled == true end
function M.set_trace(fn) trace = fn end
function M.clear()
    for _, list in pairs(listeners) do for _, token in ipairs(list) do token.active = false end end
    listeners, holds, mutes, queue, warned = {}, {}, {}, {}, {}
    strict_mode, trace, depth = false, nil, 0
end
return M
