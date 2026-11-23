-- Geometry shared by warnings and the executors that own the hit tests.
local Confinement = require "mvtk.bosses.boss_confinement"
local Schema = require "mvtk.bosses.attack_pattern_schema"
local Defaults = require("mvtk.core.util").require_config("developer.config.boss_defaults", {})
local M = {}

function M.clearance(aoe)
    return Schema.slam_dodge_height(aoe, Defaults)
end

function M.floor_band(floor_y, height)
    return floor_y + height * 0.5, height
end

-- A body overlaps this interval exactly when its root is in the authored
-- root interval, for the hurtbox sampled when this visual is placed.
function M.root_band(min_root_y, max_root_y, body)
    local offset = body and body.y - (body.root_y or body.y) or 0
    local half_height = body and body.half_h or 0
    local bottom = min_root_y + offset + half_height
    local top = max_root_y + offset - half_height
    if top <= bottom then
        return (min_root_y + max_root_y) * 0.5 + offset, math.max(1, max_root_y - min_root_y)
    end
    return (bottom + top) * 0.5, top - bottom
end

function M.charge_band(ground_y, clearance, body)
    if body and body.animated then return ground_y, clearance * 2 end
    return M.root_band(ground_y - clearance, ground_y + clearance, body)
end

function M.area_origin(origin, options, detection)
    if options.target == "player" and detection.get_player_position then
        return detection.get_player_position() or origin
    end
    return origin
end

function M.beam(boss, pattern, defaults, origin, detection, geometry)
    local beam = pattern.beam or {}
    local direction = vmath.vector3(boss.facing, 0, 0)
    if beam.target == "player" and detection.get_player_position then
        local player = detection.get_player_position()
        if player then direction = geometry.aim_vector(origin, player) end
    end
    return direction,
        beam.length or defaults.default_beam_length,
        beam.width or defaults.default_beam_width
end

function M.wave_band(step, thickness, index)
    local outer = step * index
    return math.max(0, outer - thickness), outer
end

function M.hazard_attack(pattern, defaults)
    local hazard = pattern.hazard or {}
    return {
        type = "aoe",
        damage = hazard.damage_per_second or hazard.damage or pattern.damage or defaults.default_aoe_damage,
        damage_type = pattern.damage_type or "physical",
        aoe = {
            -- The unnamed legacy hazard remains a one-shot hit at the player.
            target = "player",
            radius = hazard.radius or (hazard.width and hazard.width * 0.25)
                or (hazard.count and math.max(48, hazard.count * 18)) or defaults.default_aoe_radius,
            delay = hazard.telegraph_duration or hazard.delay or 0,
            knockback = hazard.knockback or pattern.knockback or defaults.default_aoe_knockback,
        },
    }
end

function M.charge_target(start_x, target_x, pattern, arena, epsilon, boss)
    local bounds = arena and arena.bounds
    if bounds and tonumber(bounds.x) and tonumber(bounds.width) then
        local padding = math.max(0, tonumber(pattern.edge_padding) or 72)
        local left, right = bounds.x + padding, bounds.x + bounds.width - padding
        if right > left and start_x >= left - epsilon and start_x <= right + epsilon then
            target_x = math.max(left, math.min(right, target_x))
        end
    end
    if boss and boss._locomotion and boss._locomotion.active and boss._confine_rect then
        local inset = Confinement.half_extents(boss.config, boss)
        target_x = Confinement.clamp(target_x, 0, boss._confine_rect, inset, 0)
    elseif boss and boss._confine_kind == "arena" then
        target_x = Confinement.clamp_boss(boss, target_x, 0)
    end
    return target_x
end

function M.charge_extents(pattern, defaults)
    return math.max(0, tonumber(pattern.hitbox_half_width) or 72),
        math.max(0, tonumber(pattern.hitbox_half_height or pattern.width)
            or defaults.default_melee_height or 80)
end

function M.grab_box(pattern, defaults)
    local grab = pattern.grab or {}
    return grab.reach or pattern.range or defaults.default_melee_width,
        grab.width or defaults.default_melee_width, grab.height or defaults.default_melee_height
end

return M
