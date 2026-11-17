--- Boss wave attack executor.
-- Expanding-ring AOE: fires `rings` successive AOE pulses at the boss
-- position with growing radius. The player takes damage once per ring they
-- are inside.
-- @module boss_attacks.wave

local C = require "mvtk.bosses.boss_attacks.common"

local M = {}

-- The shared effect sprite is a soft disc, so a ring band is drawn as discs
-- `thickness` wide spaced around the band's middle radius. A band as wide as
-- its radius is a full disc.
local MAX_BAND_DISCS = 48

function M.band_discs(inner, outer)
    local band = outer - inner
    if band <= 0 then return {} end
    if inner <= 0 then return {{x = 0, y = 0, radius = outer}} end
    local mid = (inner + outer) * 0.5
    local count = math.max(8, math.min(MAX_BAND_DISCS,
        math.ceil((2 * math.pi * mid) / (band * 0.75))))
    local discs = {}
    for i = 1, count do
        local angle = (2 * math.pi) * (i - 1) / count
        discs[i] = {x = math.cos(angle) * mid, y = math.sin(angle) * mid, radius = band * 0.5}
    end
    return discs
end

function M.spawn_band(origin, inner, outer)
    local effect_ok, effect_url = C.factory_exists("#aoe_effect_factory")
    if not effect_ok then return end
    for _, disc in ipairs(M.band_discs(inner, outer)) do
        pcall(factory.create, effect_url,
            vmath.vector3(origin.x + disc.x, origin.y + disc.y, origin.z), nil,
            { radius = disc.radius })
    end
end

function M.execute(boss, pattern)
    local wave = pattern.wave or {}
    local rings = wave.rings or C.Defaults.default_wave_rings
    local ring_delay = wave.ring_delay or C.Defaults.default_wave_ring_delay
    local step = wave.radius_step or C.Defaults.default_wave_radius_step
    local thickness = wave.thickness or 40
    local damage = (wave.damage or pattern.damage or C.Defaults.default_wave_damage) * C.damage_mult(boss)
    local knockback = wave.knockback or C.Defaults.default_aoe_knockback

    local origin = go.get_position()

    C.print(string.format("[BOSS_ATTACKS] Wave: %d rings, step %.0f", rings, step))

    for i = 1, rings do
        C.delay(ring_delay * (i - 1), function()
            local outer = step * i
            local inner = math.max(0, outer - thickness)
            M.spawn_band(origin, inner, outer)
            local player_pos = C.Detection.get_player_position()
            if not player_pos then return end
            local dist = vmath.length(player_pos - origin)
            if dist >= inner and dist <= outer then
                local kb_dir = vmath.normalize(player_pos - origin)
                local kb = kb_dir * knockback
                local payload = C.build_payload(boss, pattern, damage, kb.x, kb.y)
                C.post_damage(payload)
                C.print(string.format("[BOSS_ATTACKS] Wave ring %d hit player for %d", i, damage))
            end
        end)
    end
end

return M
