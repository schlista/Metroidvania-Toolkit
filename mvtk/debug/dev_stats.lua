-- Shared debug-session observations. Only the overlay loads this module;
-- gameplay owners see optional neutral callbacks, nil while their tool is off.
local Time = require "mvtk.core.time"
local Util = require "mvtk.core.util"
local DamageCalc = require "mvtk.combat.damage_calc"
local BossManager = require "mvtk.bosses.boss_manager"
local Prefab = require "mvtk.prefabs.prefab_utils"
local Config = require "developer.config.debug_config"
local M = {enabled = false, labels_enabled = false, dps_enabled = false}
local actors, window, hits = {}, {}, {}
local peak = 0
local WINDOW = 5
local ACTOR_INTERVAL = 0.1
local ACTOR_EXPIRY = 0.5
local schedule_results

local function prune(now)
    while window[1] and window[1].time <= now - WINDOW do table.remove(window, 1) end
    local total = 0
    for _, hit in ipairs(window) do total = total + hit.amount end
    return total
end

function M.record_damage(target, amount, now)
    if not M.dps_enabled then return false end
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount <= 0 or amount == math.huge then return false end
    now = now or Time.gettime()
    local hit = {target = tostring(target), amount = amount, time = now}
    window[#window + 1], hits[#hits + 1] = hit, hit
    if #hits > 10 then table.remove(hits, 1) end
    peak = math.max(peak, prune(now) / WINDOW)
    return true
end

-- Fixed five-second denominator, even during warm-up. Peak and last hits
-- belong to this meter session; they survive an empty rolling window.
function M.damage_snapshot(now)
    local total = prune(now or Time.gettime())
    return {total = total, dps = total / WINDOW, peak = peak, hits = hits}
end

local function due(id, now)
    return not actors[id] or now - actors[id].time + 0.000000001 >= ACTOR_INTERVAL
end

function M.record_actor(id, world_pos, label, hp, max_hp)
    if not M.labels_enabled then return false end
    local now = Time.gettime()
    if not due(id, now) then return false end
    actors[id] = {id = id, position = {x = world_pos.x, y = world_pos.y},
        label = label, hp = hp, max_hp = max_hp, time = now}
    return true
end

function M.actors()
    local out, now = {}, Time.gettime()
    for id, actor in pairs(actors) do
        if now - actor.time > ACTOR_EXPIRY then actors[id] = nil
        else out[#out + 1] = actor end
    end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

local function pattern_state(actor, name)
    if not name then return "off" end
    if (actor.stunned_t or 0) > 0 then return "stunned" end
    for _, pattern in ipairs(actor.patterns or {}) do
        if pattern.name == name then
            return pattern.get_state and pattern.get_state() or "running"
        end
    end
    return "running"
end

local function enemy_probe(actor, id, pos)
    if not actor or actor._dying then actors[id] = nil; return end
    if not due(id, Time.gettime()) then return end
    local resolved = actor._resolved_behavior or {}
    local slots = resolved.slots or {}
    local movement = resolved.movement or actor.pattern1 or "none"
    local first, second = slots.attack_pattern, slots.attack_pattern2
    local label = string.format("pattern %s:%s\nslot1 %s:%s / slot2 %s:%s\n%s",
        movement, actor._simple_movement_state or pattern_state(actor, movement),
        first or "none", pattern_state(actor, first), second or "none", pattern_state(actor, second),
        actor._player_detected and "detected" or "undetected")
    local defense = actor._defense or (actor.enemy_type_config or {}).defense or {}
    label = label .. "\nguard " .. tostring(defense.guard or (actor.shielded and "all" or "none"))
        .. ((actor._guard_open_t or 0) > 0 and ":open" or (actor.shielded and ":raised" or ""))
        .. " / armor " .. tostring(actor._armor_remaining or defense.armor_hits or 0)
    M.record_actor(id, pos, label, actor.health, actor.max_health)
end

local RESULT_LABELS = {
    range = "out of range", height = "height", cooldown = "cooldown", conditions = "condition",
    floor = "no floor",
    not_engaged = "not engaged", sequence_wait = "sequence wait",
    no_entries = "no attacks", no_usable_entries = "no usable attack",
    arena_missing = "no arena bounds", arena_gap = "safe gap too wide", arena_anchor = "anchor too small",
}

local function observe_pick(actor, schedule, entry, status, reasons)
    local height
    for index, reason in pairs(reasons or {}) do
        if type(index) == "number" and reason == "height" then height = true; break end
    end
    schedule_results[actor] = {schedule = schedule, attack = entry and entry.attack, status = status,
        height = height, arena_rejection = reasons and reasons.arena_rejection}
end

local function boss_probe(id, pos, state, phase, hp, max_hp, actor)
    if not pos or hp <= 0 then actors[id] = nil; return end
    if not due(id, Time.gettime()) then return end
    local label = "boss " .. tostring(state) .. " / phase " .. tostring(phase)
    if actor then
        local schedule = actor._attack_schedule
        local active = actor.state_machine and actor.state_machine.state_data
        local attack = active and active.attack
        local kind = active and active.pattern and active.pattern.type
        local result = schedule_results[actor]
        local choice = "waiting"
        if result and result.schedule == schedule then
            choice = result.attack and ("picked " .. result.attack) or (RESULT_LABELS[result.status] or "no usable attack")
            if result.height and result.status ~= "height" then choice = choice .. " / height" end
            if result.arena_rejection then choice = choice .. " / " .. RESULT_LABELS[result.arena_rejection] end
        end
        label = label .. "\nattack " .. (attack or "none") .. (kind and (" (" .. kind .. ")") or "")
            .. "\nmoveset " .. (schedule and (schedule.moveset_name or "attacks list") or "waiting")
            .. "\n" .. choice
    end
    M.record_actor(id, pos, label, hp, max_hp)
end

function M.set_labels(enabled)
    M.labels_enabled = enabled == true
    actors = {}
    schedule_results = M.labels_enabled and setmetatable({}, {__mode = "k"}) or nil
    Util.actor_probe = M.labels_enabled and enemy_probe or nil
    BossManager.actor_probe = M.labels_enabled and boss_probe or nil
    BossManager.schedule_probe = M.labels_enabled and observe_pick or nil
    M.enabled = M.labels_enabled or M.dps_enabled
end

function M.set_dps(enabled)
    M.dps_enabled = enabled == true
    window, hits, peak = {}, {}, 0
    DamageCalc.damage_probe = M.dps_enabled and M.record_damage or nil
    M.enabled = M.labels_enabled or M.dps_enabled
end

function M.reset()
    M.set_labels(false)
    M.set_dps(false)
end

function M.register_menu(menu, changed)
    if not (Prefab.is_dev_build() and Config.dev_tools and Config.dev_tools.enabled == true) then return end
    menu.register("stats", "Stats", {
        rows = function()
            return {
                {id = "labels", label = "AI labels: " .. (M.labels_enabled and "On" or "Off"), hold = 0},
                {id = "dps", label = "DPS meter: " .. (M.dps_enabled and "On" or "Off"), hold = 0},
            }
        end,
        on_confirm = function(_, row)
            if row.id == "labels" then M.set_labels(not M.labels_enabled)
            elseif row.id == "dps" then M.set_dps(not M.dps_enabled) end
            if changed then changed() end
            return {refresh = true, status = ""}
        end,
    })
end

return M
