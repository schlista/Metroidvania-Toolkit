--- Boss projectile attack executor.
-- Fires `count` projectiles in a spread aimed at the player. Uses the boss's
-- `#boss_projectile_factory` when present; otherwise schedules a delayed hit
-- test at the player's predicted position so the attack still registers.
-- @module boss_attacks.projectile

local C = require "mvtk.bosses.boss_attacks.common"

local M = {}

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    local projectiles_config = pattern.projectiles or {}
    local count = projectiles_config.count or 1
    local spread_deg = projectiles_config.spread or 0
    local speed = projectiles_config.speed or C.Defaults.default_projectile_speed
    local lifetime = projectiles_config.lifetime or C.Defaults.default_projectile_life

    C.print(string.format("[BOSS_ATTACKS] Firing %d projectiles", count))

    local pos = go.get_position()
    local damage = (pattern.damage or projectiles_config.damage or C.Defaults.default_projectile_damage) * C.damage_mult(boss)

    local player_pos = C.Detection.get_player_position()
    if not player_pos then return end

    local to_player = player_pos - pos
    -- A coincident root has no direction. Keep the +X shot even when
    -- fractional movement leaves the roots a fraction of a pixel apart.
    local coincident = math.abs(to_player.x) <= 0.001 and math.abs(to_player.y) <= 0.001
    local base_angle = coincident and 0 or math.atan2(to_player.y, to_player.x)
    local angles = C.Geometry.compute_spread_angles(count, spread_deg, base_angle)

    local have_factory = C.factory_exists("#boss_projectile_factory")
    local shots
    local function overlaps(body)
        return C.Geometry.distance_sq_to_rect(player_pos, body) < 50 * 50
    end

    for _, angle in ipairs(angles) do
        local dir = vmath.vector3(math.cos(angle), math.sin(angle), 0)
        local spawn_pos = pos + dir * 30

        if have_factory then
            local id = C.ProjectileSpawner.fire("#boss_projectile_factory", spawn_pos, angle, {
                speed = speed,
                lifetime = lifetime,
                launch_age = instance:launch_age(),
                damage = damage,
                facing = boss.facing,
                extra_props = {
                    boss_id = boss.boss_id or "",
                    damage_type = pattern.damage_type or "physical",
                    source_actor = boss.self_url,
                    parryable = pattern.parryable ~= false,
                    deflect = require("mvtk.combat.projectile_counterplay").mode(pattern.projectile_deflect),
                    reflect_damage_mult = require("mvtk.combat.projectile_counterplay").damage_mult(pattern.reflect_damage_mult),
                    -- Shots spawn 30 px out from the boss. The first frame sweeps
                    -- from the boss itself, so a wall right beside it stops them
                    -- (a ray that starts inside a wall never reports it).
                    origin_x = pos.x,
                    origin_y = pos.y,
                    probe_origin = true,
                },
            })
            -- Shots already in flight stay through knockdown and phase
            -- changes and are removed when the boss is defeated.
            shots = shots or instance:lasting()
            shots:own(id)
        else
            local hit_delay = vmath.length(player_pos - spawn_pos) / math.max(1, speed)
            instance:after(hit_delay, function()
                C.active_frames(instance, 0, function()
                    if not C.hit_body(instance, overlaps, "circle", player_pos, 50) then return end
                    local payload = C.build_payload(boss, pattern, damage, 0, 0)
                    C.post_damage(payload)
                end)
            end)
        end
    end
end

return M
