--- Boss wave attack executor.
-- Expanding-ring AOE: fires successive bands at the boss with growing radius.
-- Each ring can hit the player once.
-- @module boss_attacks.wave

local C = require "mvtk.bosses.boss_attacks.common"
local Indicator = require "mvtk.bosses.indicator_geometry"
local Telegraph = require "mvtk.bosses.boss_telegraph"

local M = {}

function M.spawn_band(origin, inner, outer, instance, spent, single_hit, minimum_duration)
    if outer <= inner then return end
    local effect_ok, effect_url = C.factory_exists("#aoe_effect_factory")
    if not effect_ok then return end
    local ok, id = pcall(factory.create, effect_url, origin, nil, {
        radius = outer, ring = inner > 0, single_hit = single_hit or false,
        minimum_duration = minimum_duration,
    })
    if not ok then return end
    if instance then instance:own(id) end
    if spent then C.effect_look(id, "spent") end
    return id
end

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    local wave = pattern.wave or {}
    local rings = wave.rings or C.Defaults.default_wave_rings
    if rings < 1 then return end
    local ring_delay = wave.ring_delay or C.Defaults.default_wave_ring_delay
    local step = wave.radius_step or C.Defaults.default_wave_radius_step
    local thickness = wave.thickness or 40
    local damage = (wave.damage or pattern.damage or C.Defaults.default_wave_damage) * C.damage_mult(boss)
    local knockback = wave.knockback or C.Defaults.default_aoe_knockback

    local origin = go.get_position()
    local warning = Telegraph.lock_indicator(boss, pattern, instance)
    local previous_effect
    for i = 1, rings do
        instance:after(ring_delay * (i - 1), function()
            if i == 1 then Telegraph.cancel(warning) end
            local inner, outer = Indicator.wave_band(step, thickness, i)
            local single = ring_delay <= 0 and i == rings
            C.effect_look(previous_effect, "spent")
            local effect = M.spawn_band(origin, inner, outer, instance,
                ring_delay <= 0 and not single, single, ring_delay)
            previous_effect = effect
            if ring_delay <= 0 and not single then return end

            local ring = instance:child({rehit_interval = pattern.rehit_interval})
            local function overlaps(body)
                return C.Geometry.rect_in_ring(origin, inner, outer, body)
            end
            local function check(active, time)
                if time and time >= ring_delay
                    and (tonumber(pattern.rehit_interval) or C.Defaults.default_rehit_interval or 0) <= 0 then return end
                local body, count = C.hit_body(active, overlaps, "ring", origin, inner, outer)
                if not body then return end
                local kx, ky = C.radial_knockback(origin, body, knockback)
                local payload = C.build_payload(boss, pattern, damage, kx, ky)
                for _ = 1, count do C.post_damage(payload) end
                C.print(string.format("[BOSS_ATTACKS] Wave ring %d hit player for %d damage", i, damage))
            end
            C.launch_sample(ring, check)
            if ring_delay > 0 then
                C.active_frames(ring, ring_delay, check, false, function()
                    if previous_effect == effect then C.effect_look(effect, "spent") end
                end, true)
            end
        end)
    end
end

return M
