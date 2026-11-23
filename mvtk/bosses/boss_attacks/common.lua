--- Shared helpers for the boss attack executors.
--
-- The boss_attacks/<type>.lua modules all import this file and use it for
-- module references, payload construction, and the few shared utility
-- functions that used to live as locals in the monolithic boss_attacks.lua.
-- Keeping them in one place avoids duplication and lets each per-type file
-- stay focused on the attack's behavior.
--
-- @module boss_attacks.common

local Util = require "mvtk.core.util"
local Stationary = require "mvtk.bosses.stationary_attack_defaults"
local Schema = require "mvtk.bosses.attack_pattern_schema"
local Clock = require "mvtk.bosses.boss_clock"

local C = {}

-- Debug-gated print. Mirrors the previous file-local print() so per-attack
-- modules can call C.print(...) and only see output when
-- developer/config/debug_config.lua has bosses.attacks = true.
local _orig_print = print
local _Dbg = Util.require_config("developer.config.debug_config")
function C.print(...)
    if _Dbg.bosses and _Dbg.bosses.attacks then
        _orig_print(...)
    end
end

-- Placed bosses always have an arena field. A blank placement must not
-- borrow another boss's arena, but a config with no fields keeps that fallback.
function C.resolve_arena(config, active)
    config = config or {}
    local id = Util.normalize_hash_string(config.arena_id) or Util.normalize_hash_string(config.arena)
    if not active or (not id and (config.arena_id ~= nil or config.arena ~= nil)) then
        return nil, "missing"
    end
    if not id or id == active.id then return active end
end

C.Detection         = require "mvtk.enemies.detection"
C.Geometry          = require "mvtk.combat.attack_geometry"
C.BossAnimations    = Util.require_module("mvtk.bosses.boss_animations")
C.ProjectileSpawner = require "mvtk.combat.projectile_spawner"
C.DamagePayload     = Util.require_module("mvtk.combat.damage_payload")
C.Util              = Util
C.DEFAULT_MELEE_ACTIVE_TIME = 0.14
C.Defaults = Util.require_config("developer.config.boss_defaults", {
    attack_duration            = 1.0,
    default_melee_damage       = 2,
    default_melee_width        = 60,
    default_melee_height       = 80,
    default_melee_active_time  = C.DEFAULT_MELEE_ACTIVE_TIME,
    default_melee_knockback_x  = 200,
    default_melee_knockback_y  = 100,
    default_projectile_damage  = 1,
    default_projectile_speed   = 300,
    default_projectile_life    = 3.0,
    default_aoe_damage         = 3,
    default_aoe_radius         = 150,
    default_aoe_delay          = 0.5,
    default_aoe_active_time    = 0,
    default_aoe_knockback      = 150,
    default_rehit_interval     = 0,
    default_beam_damage        = 2,
    default_beam_length        = 400,
    default_beam_width         = 40,
    default_beam_duration      = 1.5,
    default_beam_windup        = 0.5,
    default_grab_damage        = 3,
    default_grab_duration      = 1.2,
    default_grab_throw_kb      = 350,
    default_heal_amount        = 10,
    default_buff_duration      = 4.0,
    default_shield_hp          = 25,
    default_shield_duration    = 6.0,
    default_parry_window       = 0.5,
    default_mine_damage        = 3,
    default_mine_radius        = 48,
    default_mine_lifetime      = 8.0,
    default_wave_damage        = 2,
    default_wave_rings         = 3,
    default_wave_ring_delay    = 0.35,
    default_wave_radius_step   = 80,
    default_zone               = Stationary.zone,
    default_ground_wave        = Stationary.ground_wave,
    default_sweep              = Stationary.sweep,
    default_rain               = Stationary.rain,
    default_ring               = Stationary.ring,
})

function C.stationary_options(pattern)
    local settings, err = Schema.stationary_options(pattern, C.Defaults)
    if err then _orig_print("[BOSS_ATTACKS] " .. err) end
    return settings
end

function C.moving_options(pattern)
    local settings, err = Schema.moving_options(pattern, C.Defaults)
    if err then _orig_print("[BOSS_ATTACKS] " .. err) end
    return settings
end

-- Charge and the other moving kinds share one owner. A combo can start a
-- second move while the first is still running, so clean up the old move
-- before sampling the new position or scale.
function C.supersede_motion(boss)
    local previous = boss._active_charge
    if not previous then return end
    if previous.release then previous.release(true) end
    previous.finished = true
    boss._active_charge = nil
end

C.DAMAGE_MSG = hash("mvtk_apply_damage")

function C.damage_mult(boss)
    return (boss.boss_data and boss.boss_data.damage_multiplier) or 1.0
end

function C.launch_sample(instance, check)
    local at = instance:time()
    instance._hit_schedule = {first = at, through = at}
    check(instance)
    instance._hit_schedule = nil
end

-- The window owns its timestamps and retires with its frame callback. A
-- crossing draw can show the spent effect before the final scheduled tick.
function C.active_frames(instance, duration, check, sample_end, on_end, sampled_at_launch)
    duration = math.max(0, duration or 0)
    local sampled, closed, previous = sampled_at_launch, false, nil
    local rehit = (tonumber(instance.pattern.rehit_interval) or C.Defaults.default_rehit_interval or 0) > 0
    local schedule = {}
    instance:each_frame(function(active, _, now, dt, starts_at)
        local ends_at = starts_at + duration
        local ended = Clock.reached(now, ends_at)
        local keep = true
        if not sampled or sample_end or Clock.reached(ends_at, now) or rehit then
            local time = ended and ends_at or now
            schedule.first = sampled and time or starts_at
            schedule.through = time
            schedule.limit = duration > 0 and ends_at or nil
            schedule.previous = previous
            active._hit_schedule = schedule
            keep = check(active, ended and duration or math.max(0, time - starts_at)) ~= false
            active._hit_schedule = nil
            sampled, previous = true, time
        end
        if not closed and (not keep or Clock.reached(now + Clock.window_lead(dt), ends_at)) then
            closed = true
            if on_end then on_end() end
        end
        return keep and not ended
    end, nil, duration, true)
end

-- Optional shape arguments describe the same sample for the debug overlay.
-- Pass bounds as values so disabled drawing adds no allocation.
function C.hit_body(instance, overlaps, shape, ...)
    local schedule = instance._hit_schedule
    local now = schedule and schedule.through or instance.elapsed
    local due = instance.next_player_hit_at
    local interval = tonumber(instance.pattern.rehit_interval) or C.Defaults.default_rehit_interval or 0
    local ready = not due or Clock.reached(now, due)
    if not ready and (not schedule or interval <= 0) then return nil end
    if schedule and due and schedule.limit and due + 1e-12 >= schedule.limit then return nil end
    local body = C.Detection.get_player_body()
    if ready and body and shape and C.shape_probe then C.shape_probe(body, shape, ...) end
    local hit, entered, left
    if body then hit, entered, left = overlaps(body, ...) end
    if not schedule or interval <= 0 then
        if not hit then return nil end
        instance.next_player_hit_at = interval > 0 and now + interval or math.huge
        return body, 1
    end
    local was_occupied = schedule.occupied
    schedule.occupied = hit == true
    if not ready or not hit then return nil end
    due = due or entered or schedule.first
    if left then now = math.min(now, left) end
    if was_occupied == false and now > due then
        -- An empty shape can become occupied between ticks. Deliver the
        -- current slot on contact without replaying past empty slots.
        due = due + math.floor((now - due) / interval + 1e-9) * interval
    end
    if entered and entered > due then
        due = due + math.ceil((entered - due) / interval - 1e-9) * interval
    end
    if not Clock.reached(now, due) then return nil end
    if schedule.limit and due + 1e-12 >= schedule.limit then return nil end
    local count = 1 + math.max(0, math.floor((now - due) / interval + 1e-9))
    if schedule.limit then
        count = math.min(count, math.ceil((schedule.limit - due) / interval - 1e-9))
    end
    instance.next_player_hit_at = due + count * interval
    return body, count
end

function C.radial_knockback(origin, body, magnitude)
    local dx, dy = body.x - origin.x, body.y - origin.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance == 0 then return 0, 0 end
    return dx / distance * magnitude, dy / distance * magnitude
end

-- Build a damage payload with the attack's knockback and hit recovery.
-- Falls back to a plain table when DamagePayload is unavailable.
function C.build_payload(boss, pattern, amount, kx, ky)
    local base = {
        amount = amount,
        damage_type = pattern.damage_type or "physical",
        -- Keep the logical manager id separately while using a real GO URL as
        -- the combat source so parries/counters can message the attacker.
        source = boss.self_url or boss.boss_id,
        source_actor = boss.self_url,
        boss_id = boss.boss_id,
        dir = boss.facing,
        kx = kx,
        ky = ky,
        -- Preserve authored recovery; normalization otherwise turns a missing
        -- stun into zero and the player's movement overwrites the impulse.
        stun_t = pattern.stun_t or C.Defaults.default_hit_stun,
        reaction_type = pattern.reaction_type,
        iframes_on_hit = pattern.iframes_on_hit,
        parryable = pattern.parryable ~= false,
    }
    if C.DamagePayload and C.DamagePayload.build then
        return C.DamagePayload.build(base)
    end
    return base
end

function C.post_damage(payload)
    local player_url = C.Detection.get_player_url()
    if not player_url then return false end

    -- Detection stores a game-object URL because it is also used for position
    -- queries. Damage must target the actual player controller component.
    -- Rebuild the URL explicitly so the legacy fallback ending in `#player`
    -- cannot silently swallow combat messages (the component is `#script`).
    local target = player_url
    local ok_url, parsed = pcall(msg.url, player_url)
    if ok_url and parsed and parsed.socket and parsed.path then
        local ok_target, script_url = pcall(msg.url, parsed.socket, parsed.path, hash("script"))
        if ok_target and script_url then
            target = script_url
        end
    end

    local ok, err = pcall(msg.post, target, C.DAMAGE_MSG, payload)
    if not ok then
        C.print("[BOSS_ATTACKS] Failed to damage player:", err)
    end
    return ok
end

function C.factory_exists(component_url_string)
    local ok, url = pcall(msg.url, component_url_string)
    if not ok then return false end
    local ok2, exists = pcall(go.exists, url)
    return ok2 and exists, url
end

function C.resolve_animation_key(boss, key)
    if type(key) ~= "string" or key == "" then
        return key
    end
    if C.BossAnimations and C.BossAnimations.resolve_or_key then
        return C.BossAnimations.resolve_or_key(boss, key)
    end
    return key
end

function C.play_resolved_animation(boss, key, loop, force)
    if not (boss and boss.play_animation and key and key ~= "") then
        return
    end
    boss:play_animation(C.resolve_animation_key(boss, key), loop, force)
end

function C.play_pattern_animation(boss, pattern)
    if not (boss and pattern and pattern.animation and boss.play_animation) then
        return
    end
    -- Route attack-pattern animations through the shared boss animation
    -- contract so attack patterns can use logical keys (e.g. "swing", "slam")
    -- and first-time users only need to author the standard generic slot names.
    C.play_resolved_animation(boss, pattern.animation, false)
end

function C.copy_table(src)
    if type(C.Util) == "table" and type(C.Util.deep_copy) == "function" then
        return C.Util.deep_copy(src)
    end
    local out = {}
    for k, v in pairs(src or {}) do
        out[k] = v
    end
    return out
end

function C.merge_step_pattern(base_pattern, step)
    local merged = C.copy_table(base_pattern or {})
    for k, v in pairs(step or {}) do
        if k ~= "pattern" and k ~= "delay" and k ~= "repeat" and k ~= "aim" then
            merged[k] = v
        end
    end
    return merged
end

-- The runtime stays pure; object deletion is supplied at this boundary.
C.Runtime = require "mvtk.bosses.attack_runtime"
function C.delete_owned(id)
    if id and go.exists(id) then go.delete(id) end
end
function C.instance(boss, pattern, instance)
    return instance or C.Runtime.start(boss, pattern, {delete = C.delete_owned, exists = go.exists})
end

-- A foreground sequence always stops with the attack. Lingering zones and
-- launched shots opt into separate background ownership.
function C.stationary_instance(boss, pattern, instance)
    local active = C.instance(boss, pattern, instance)
    active.persist = false
    active.interruptible = true
    return active
end

function C.stationary_shots(boss, pattern, instance, settings)
    local Counterplay = require "mvtk.combat.projectile_counterplay"
    local props = {
        speed = settings.speed,
        lifetime = settings.lifetime,
        damage = (pattern.damage or settings.damage) * C.damage_mult(boss),
        extra_props = {
            boss_id = boss.boss_id or "",
            damage_type = pattern.damage_type or "physical",
            source_actor = boss.self_url,
            source_attack = pattern._attack_name,
            parryable = pattern.parryable ~= false,
            deflect = Counterplay.mode(pattern.projectile_deflect),
            reflect_damage_mult = Counterplay.damage_mult(pattern.reflect_damage_mult),
        },
    }
    local shots
    return function(origin, angle)
        props.launch_age = instance:launch_age()
        if settings.knockback then
            props.extra_props.kx = math.cos(angle) * settings.knockback
            props.extra_props.ky = math.sin(angle) * settings.knockback
        end
        local id = C.ProjectileSpawner.fire("#boss_projectile_factory", origin, angle, props)
        if id then
            shots = shots or instance:lasting({persist = true})
            shots:own(id)
        end
    end
end

function C.stationary_effect(instance, component, origin, props)
    props.managed = true
    local ok, id = pcall(factory.create, component, origin, nil, props)
    if ok then return instance:own(id) end
end

function C.active_box(instance, origin, width, height)
    if width <= 0 or height <= 0 then return end
    return C.stationary_effect(instance, "#aoe_effect_factory", origin, {
        width = width, box_height = height,
    })
end

function C.retire_effect(instance, id)
    if not id then return end
    C.delete_owned(id)
    instance:disown(id)
end

-- Stage changes are issued by the same callback that arms or ends damage.
function C.effect_look(id, look, remaining)
    if id and go.exists(id) then
        msg.post(msg.url(nil, id, "script"), "boss_indicator_look", {look = look, remaining = remaining})
    end
end

-- Pattern dispatcher binding. boss_attacks.lua installs the active
-- execute_pattern() here after the dispatch table is built so combo
-- modules can re-enter dispatch without circular requires.
C._execute_pattern = nil
function C.set_execute_pattern(fn)
    C._execute_pattern = fn
end

function C.execute_pattern(boss, pattern, opts)
    if C._execute_pattern then
        return C._execute_pattern(boss, pattern, opts)
    end
end

return C
