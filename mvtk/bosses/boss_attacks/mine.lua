--- Boss mine attack executor.
-- Drops a stationary trigger at the boss (or player) position that damages
-- the player on contact and disappears on trigger or after lifetime. Uses
-- the aoe_effect_factory as the visual.
-- @module boss_attacks.mine

local C = require "mvtk.bosses.boss_attacks.common"
local Telegraph = require "mvtk.bosses.boss_telegraph"

local M = {}

function M.execute(boss, pattern, instance)
    -- The mine outlives the planting attack.
    instance = C.instance(boss, pattern, instance):lasting()
    local mine = pattern.mine or {}
    local radius = mine.radius or C.Defaults.default_mine_radius
    local damage = (mine.damage or pattern.damage or C.Defaults.default_mine_damage) * C.damage_mult(boss)
    local lifetime = mine.lifetime or C.Defaults.default_mine_lifetime
    local arm_delay = mine.arm_delay or 0.4

    local pos = go.get_position()
    local plant_pos
    if mine.position == "player" then
        plant_pos = C.Detection.get_player_position() or pos
    else
        plant_pos = vmath.vector3(pos.x, pos.y, pos.z)
    end

    C.print(string.format("[BOSS_ATTACKS] Mine planted (radius %.0f, lifetime %.1fs)",
        radius, lifetime))

    local warning = Telegraph.lock_indicator(boss, pattern)
    local color = (warning and warning.color) or pattern.telegraph_color
    Telegraph.cancel(warning)
    local visual
    local effect_ok, effect_url = C.factory_exists("#aoe_effect_factory")
    if effect_ok then
        local created, id = pcall(factory.create, effect_url, plant_pos, nil, {
            radius = radius,
            lifetime = lifetime,
            indicator_look = "warning",
            warning_color = color,
        })
        if created then visual = instance:own(id) end
    end

    -- The visual times itself out too; this removes it when the mine ends first.
    local function remove_visual()
        if visual then
            local id = visual
            visual = nil
            pcall(function() if go.exists(id) then go.delete(id) end end)
        end
    end

    instance:after(lifetime, remove_visual)

    local function overlaps(body)
        return C.Geometry.rect_in_circle(plant_pos, radius, body)
    end

    local function check()
        local body = C.hit_body(instance, overlaps, "circle", plant_pos, radius)
        if not body then return end
        remove_visual()
        local kx, ky = C.radial_knockback(plant_pos, body,
            mine.knockback or C.Defaults.default_aoe_knockback)
        local payload = C.build_payload(boss, pattern, damage, kx, ky)
        C.post_damage(payload)
        C.print(string.format("[BOSS_ATTACKS] Mine triggered for %d damage", damage))
        return false
    end
    if arm_delay < lifetime then
        instance:after(arm_delay, function()
            C.effect_look(visual, "active")
            C.active_frames(instance, lifetime - arm_delay, check)
        end)
    end
end

return M
