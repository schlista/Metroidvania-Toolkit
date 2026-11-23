-- Place a fixed damage area whose lifetime belongs to the fight, not the cast.
local C = require "mvtk.bosses.boss_attacks.common"
local Telegraph = require "mvtk.bosses.boss_telegraph"

local M = {}

local function start_zone(boss, pattern, instance, settings, center, color)
    local zone = instance:lasting(pattern)
    local circle = settings.shape == "circle"
    local visual = circle and {radius = settings.radius}
        or {width = settings.width, box_height = settings.height}
    local last_tick = math.floor(settings.duration / settings.tick + 1e-9)
    visual.indicator_look = last_tick > 0 and "warning" or "spent"
    visual.single_hit = last_tick == 1
    visual.warning_color = color
    local position = vmath.vector3(center.x, center.y, center.z + 0.1)
    local effect = C.stationary_effect(zone, "#aoe_effect_factory", position, visual)
    local damage = (pattern.zone and pattern.zone.damage or pattern.damage or settings.damage) * C.damage_mult(boss)
    local knockback = pattern.zone and pattern.zone.knockback or pattern.knockback or settings.knockback
    local function overlaps(body)
        if circle then return C.Geometry.rect_in_circle(center, settings.radius, body) end
        return C.Geometry.rect_in_box(center, settings.width * 0.5, settings.height * 0.5, body)
    end
    local shape = circle and "circle" or "box"
    local size = circle and settings.radius or settings.width * 0.5
    local half_height = not circle and settings.height * 0.5
    local tick = 1
    C.active_frames(zone, settings.duration, function(active, time)
        local hit_time = time / settings.tick + 1e-9
        if tick == 1 and tick <= hit_time then C.effect_look(effect, "active") end
        -- Allow an exact endpoint tick even when accumulated frame time has
        -- a little floating-point drift.
        while tick <= hit_time do
            tick = tick + 1
            active.next_player_hit_at = nil
            local body = C.hit_body(active, overlaps, shape, center, size, half_height)
            if body then
                local kx, ky = C.radial_knockback(center, body, knockback)
                local payload = C.build_payload(boss, pattern, damage, kx, ky)
                payload.status_id = settings.status
                payload.status_duration = settings.status_duration
                payload.source_attack = pattern._attack_name or "zone"
                C.post_damage(payload)
            end
            if tick == last_tick + 1 then C.effect_look(effect, "spent", settings.duration - time) end
        end
        if time >= settings.duration then
            if last_tick == 1 then
                C.effect_look(effect, "expire")
            else
                C.delete_owned(effect)
            end
        end
    end, true)
end

function M.execute(boss, pattern, instance)
    local settings = C.stationary_options(pattern)
    if not settings then return end
    instance = C.stationary_instance(boss, pattern, instance)
    local cue = Telegraph.take_stationary(boss, pattern, settings)
    if not cue.center then return end
    local function place(active)
        Telegraph.cancel(cue)
        start_zone(boss, pattern, active, settings, cue.center, cue.color or pattern.telegraph_color)
    end
    if settings.delay > 0 then
        -- The cast's authored state duration and the placement delay are
        -- independent. An interrupted cast never places a pending zone.
        cue.execution_owned = true
        instance:lasting({persist = false}):after(settings.delay, place)
    else
        place(instance)
    end
end

return M
