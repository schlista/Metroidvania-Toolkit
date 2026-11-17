-- Shared transient registry, keyed by gameobject id hashes in the main world.
-- No engine calls or subscriptions at require time. Recipients own DamageCalc;
-- the ticker sends raw damage once and deliberately supplies no source_actor.
local Config = require "developer.config.status_effects"
local Pause = require "mvtk.core.pause"
local PlayerStats = require "mvtk.player.player_stats"
local Events = require "mvtk.core.game_events"
local M = {}
local active = {}
local refresh = 0
local hud_present = false

local cached_config, cached_revision

local function config()
    return require("developer.config.runtime_settings").section("status_effects", Config)
end

-- RuntimeSettings.section copies every creator override, and update runs each
-- frame: there, resolve once per settings revision (the mvtk/combat/config.lua
-- rule). Event-time callers keep reading config() fresh.
local function frame_config()
    local RuntimeSettings = require "developer.config.runtime_settings"
    local revision = RuntimeSettings.revision and RuntimeSettings.revision()
    if revision == nil or cached_config == nil or cached_revision ~= revision then
        cached_config, cached_revision = config(), revision
    end
    return cached_config
end

local function sync_hud()
    local effects = {}
    for _, bucket in pairs(active) do
        if bucket.kind == "player" then
            for id, inst in pairs(bucket.effects) do
                effects[#effects+1] = {id=id,label=inst.def.label,color=inst.def.color,remaining=inst.remaining}
            end
        end
    end
    table.sort(effects,function(a,b) return a.id < b.id end)
    if #effects > 0 or hud_present then
        require("mvtk.ui.hud_bus").post("status_chips", {effects=effects})
    end
    hud_present = #effects > 0
end

local function target_id(target)
    if target == nil then return nil end
    if type(target) == "string" then return msg.url(target).path end
    local ok, path = pcall(function() return target.path end)
    return ok and path or target
end

local function contains(set, id)
    if not set then return false end
    if set[id] == true then return true end
    for _, value in ipairs(set) do if value == id then return true end end
    return false
end

-- Enemies ask every frame: an unaffected target allocates nothing and reads no settings.
function M.move_multiplier(target)
    local bucket = active[target_id(target)]
    if not bucket then return 1 end
    local product = 1
    for _, inst in pairs(bucket.effects) do product = product * (inst.def.move or 1) end
    if bucket.kind == "boss" then
        product = math.max(frame_config().bosses.min_move_multiplier, product)
    end
    return product
end

local function sync_player()
    for id, bucket in pairs(active) do
        if bucket.kind == "player" then
            PlayerStats.set_source("status", {speed_mult=math.max(0.25, M.move_multiplier(id))}, {layer="temporary"})
            return
        end
    end
    PlayerStats.clear_source("status")
end

function M.apply(target, effect_id, opts)
    local Config = config()
    opts = opts or {}
    local def = Config.effects[effect_id]
    local id = target_id(target)
    if not Config.enabled or not id or not def then return false end
    local kind = opts.kind or "enemy"
    local kind_config = kind == "boss" and Config.bosses or Config[kind]
    if contains(opts.immune, effect_id) or contains((kind_config or {}).immune, effect_id) then return false end
    local chance = opts.chance == nil and 1 or opts.chance
    if chance <= 0 or (chance < 1 and (opts.rng or math.random)() >= chance) then return false end
    local duration = tonumber(opts.duration)
    if not duration or duration <= 0 then duration = def.duration end
    if not go.exists(id) then return false end
    local bucket = active[id] or {kind=kind, effects={}}
    local previous = bucket.effects[effect_id]
    bucket.effects[effect_id] = {
        def=def, remaining=duration, tick=def.tick_interval or Config.defaults.tick_interval,
        stacks=math.min((previous and previous.stacks or 0)+1, def.max_stacks or 1),
    }
    active[id] = bucket
    if kind == "player" then sync_player(); sync_hud() end
    -- Refreshes and additional stacks are not new starts.
    if not previous then
        Events.emit("status_applied", {status=effect_id, target=tostring(id), source=opts.source})
    end
    return true
end

function M.on_hit(target, payload, kind, immune)
    payload = payload or {}
    if payload.damage_over_time then return false end
    local id, chance = payload.status_id, payload.status_chance
    if (not id or id == "" or id == "none") and kind ~= "player" then
        local entry = require("developer.config.damage_types").types[payload.damage_type or payload.dtype]
        local status = entry and entry.status
        if status then id, chance = status.id, status.chance end
    end
    if not id or id == "" or id == "none" then return false end
    return M.apply(target, id, {kind=kind, immune=immune, chance=chance,
        duration=payload.status_duration, source=payload.source_attack})
end

function M.stops(target)
    local bucket = active[target_id(target)]
    if not bucket or bucket.kind ~= "enemy" then return false end
    for _, inst in pairs(bucket.effects) do if inst.def.stops_enemies then return true end end
    return false
end

function M.clear(target)
    local id = target_id(target)
    if id == nil then return end
    local bucket = active[id]
    active[id] = nil
    if bucket and bucket.kind == "player" then sync_player(); sync_hud() end
end

function M.reset()
    active, refresh = {}, 0
    PlayerStats.clear_source("status")
    sync_hud()
end

function M.on_session_start() M.reset() end

function M.update(dt)
    if Pause.get() then return end
    local Config = frame_config()
    if not Config.enabled then M.reset(); return end
    local changed = false
    dt = math.max(0, dt) * Pause.dt_scale()
    for id, bucket in pairs(active) do
        if not go.exists(id) then M.clear(id)
        else
            for effect_id, inst in pairs(bucket.effects) do
                local elapsed = math.min(dt, inst.remaining)
                inst.remaining = inst.remaining - elapsed
                inst.tick = inst.tick - elapsed
                local def = inst.def
                while inst.tick <= 0 do
                    inst.tick = inst.tick + (def.tick_interval or Config.defaults.tick_interval)
                    if (def.damage_per_tick or 0) > 0 then
                        msg.post(id, "mvtk_apply_damage", {
                            amount=def.damage_per_tick * inst.stacks, damage_type=def.damage_type,
                            damage_over_time=true, ignore_iframes=true, stun_t=0, parryable=false,
                            source_attack="status_"..effect_id,
                        })
                        if Config.feedback.tint then
                            local color = def.color
                            pcall(msg.post, msg.url(nil, id, "anim"), "anim.flash", {
                                color=vmath.vector4(color[1],color[2],color[3],1),
                                duration=Config.feedback.flash_duration,
                            })
                        end
                    end
                end
                if inst.remaining <= 0 then
                    bucket.effects[effect_id] = nil
                    changed = changed or bucket.kind == "player"
                end
            end
            if not next(bucket.effects) then M.clear(id) end
        end
    end
    if changed then sync_hud() end
    refresh = refresh - dt
    if refresh <= 0 then refresh = Config.defaults.refresh_interval; sync_player() end
end

return M
