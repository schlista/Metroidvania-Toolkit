--- Boss AOE attack executor.
-- Telegraphs an area of effect at the boss or at the player's position, then
-- damages the player after `aoe.delay` if they remain inside the radius.
-- @module boss_attacks.aoe

local C = require "mvtk.bosses.boss_attacks.common"
local Indicator = require "mvtk.bosses.indicator_geometry"
local Telegraph = require "mvtk.bosses.boss_telegraph"
local Floor = require "mvtk.bosses.boss_floor_attacks"

local M = {}

local function hits_aoe(center, radius, aoe, body)
    if aoe.ground_only then
        return math.abs(body.x - center.x) <= radius + body.half_w
            and Floor.reaches(body, center.y, Indicator.clearance(aoe))
    end
    return C.Geometry.rect_in_circle(center, radius, body)
end

local function knockback_for(center, aoe, magnitude, player_pos)
    if aoe.ground_only then
        local direction = player_pos.x >= center.x and 1 or -1
        return direction * magnitude, tonumber(aoe.knockback_y) or magnitude * 0.5
    end

    local dx = player_pos.x - center.x
    local dy = player_pos.y - center.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.0001 then
        return magnitude, 0
    end
    return (dx / length) * magnitude, (dy / length) * magnitude
end

local function apply_hit(boss, pattern, instance, center, radius, aoe, damage, knockback)
    local body, count = C.hit_body(instance, function(player)
        return hits_aoe(center, radius, aoe, player)
    end, aoe.ground_only and "ground_area" or "circle", center, radius, aoe)
    if not body then return end
    local kx, ky = knockback_for(center, aoe, knockback, body)
    local payload = C.build_payload(boss, pattern, damage, kx, ky)
    for _ = 1, count do C.post_damage(payload) end
    C.print(string.format("[BOSS_ATTACKS] AOE hit player for %d damage", damage))
end

local function show_effect(instance, center, radius, options, active_time)
    local effect_ok, effect_url = C.factory_exists("#aoe_effect_factory")
    if effect_ok then
        local y = center.y
        local props = {radius = radius, duration = tonumber(options.effect_duration) or 0.45,
            minimum_duration = active_time, single_hit = active_time <= 0}
        if options.ground_only then
            y, props.box_height = Indicator.floor_band(y, Indicator.clearance(options))
            props.width = radius * 2
        end
        local position = vmath.vector3(center.x, y, (center.z or 0) + 0.1)
        local ok, id = pcall(factory.create, effect_url, position, nil, props)
        if ok then return instance:own(id) end
    end
end

-- Moving strikes sample once on touchdown. Their executor supplies the
-- impact point, on the landing floor for a ground-only strike.
function M.land(boss, pattern, instance, center, land)
    apply_hit(boss, pattern, instance, center, land.radius, land,
        land.damage * C.damage_mult(boss), land.knockback)
    show_effect(instance, center, land.radius, {
        ground_only = land.ground_only, vertical_clearance = land.vertical_clearance,
        jump_clearance = land.jump_clearance,
    }, 0)
end

function M.execute(boss, pattern, instance, warning_pattern)
    instance = C.instance(boss, pattern, instance)
    C.print("[BOSS_ATTACKS] AOE attack")

    local pos = go.get_position()
    local aoe = pattern.aoe or {}
    local radius = aoe.radius or C.Defaults.default_aoe_radius
    local damage = (pattern.damage or C.Defaults.default_aoe_damage) * C.damage_mult(boss)
    local knockback_mag = aoe.knockback or C.Defaults.default_aoe_knockback
    local delay = aoe.delay or C.Defaults.default_aoe_delay
    local active_time = tonumber(aoe.active_time) or C.Defaults.default_aoe_active_time
    local center_pos = Indicator.area_origin(pos, aoe, C.Detection)

    local function start(center)
        local warning = Telegraph.lock_area(boss, warning_pattern or pattern, instance, center, radius, aoe)
        instance:after(delay, function()
            Telegraph.cancel(warning)
            local effect
            C.active_frames(instance, active_time, function()
                apply_hit(boss, pattern, instance, center, radius, aoe, damage, knockback_mag)
            end, false, function() C.effect_look(effect, "spent") end)
            effect = show_effect(instance, center, radius, aoe, active_time or 0)
        end)
    end
    if not aoe.ground_only then return start(center_pos) end
    local function launch()
        local y, probed = Floor.slam_floor(boss, pos, center_pos)
        if y then start(vmath.vector3(center_pos.x, y, center_pos.z)) end
        return probed
    end
    if not launch() then
        instance:each_frame(function() if launch() then return false end end)
    end
end

M._hits_aoe = hits_aoe

return M
