-- Framework boss patterns use 64-pixel tiles. Resolve pixel values into the
-- project's units without changing angles, timing, damage or the shared source.
local M = {}

M.PIXEL_KEYS = {
    speed = true,             -- px/s: projectile, hazard or special movement
    dash_speed = true,        -- px/s: charge movement
    slam_speed = true,        -- px/s: downward movement
    dash_distance = true,     -- px: charge travel
    range = true,             -- px: attack range
    attack_range = true,      -- px: special attack range
    reach = true,             -- px: melee reach
    width = true,             -- px: attack width
    height = true,            -- px: attack height
    hitbox_half_width = true, -- px: horizontal hitbox half-size
    hitbox_half_height = true, -- px: vertical hitbox half-size
    radius = true,            -- px: circular attack radius
    radius_step = true,       -- px: radius increment
    spawn_radius = true,      -- px: spawn distance from the boss
    beam_length = true,       -- px: beam length
    beam_width = true,        -- px: beam width
    thickness = true,         -- px: ring or wave thickness
    jump_height = true,       -- px: attack jump height
    vertical_clearance = true, -- px: vertical space required by the attack
    edge_padding = true,      -- px: arena-edge clearance
    knockback = true,         -- px or px/s: horizontal knockback
    knockback_y = true,       -- px or px/s: vertical knockback
    throw_knockback = true,   -- px or px/s: horizontal throw knockback
    throw_knockback_y = true, -- px or px/s: vertical throw knockback
}

-- Several new blocks use short field names that older kinds never scaled.
local SCOPED_PIXEL_KEYS = {
    telegraph_size = {x = true, y = true},
    ground_wave = {distance = true},
    sweep = {length = true},
    rain = {gap_width = true},
    leap = {max_distance = true},
    dive = {rise = true, track_speed = true},
}

-- Recursive independent copy, including nested attack tables and arrays.
-- k is a positive, unitless factor supplied by the boss pattern resolver.
function M.scale_pattern(pattern, k, scoped_keys)
    local out = {}
    for key, value in pairs(pattern) do
        if type(value) == "table" then
            out[key] = M.scale_pattern(value, k, SCOPED_PIXEL_KEYS[key])
        elseif type(value) == "number" and (M.PIXEL_KEYS[key] or (scoped_keys and scoped_keys[key])) then
            out[key] = value * k
        else
            out[key] = value
        end
    end
    return out
end

-- Preserve the older charge patterns that use range or omit both distances.
function M.charge_distance(pattern)
    return math.max(0, tonumber(pattern.dash_distance or pattern.range) or 180)
end

-- Resolve a melee box in facing-relative pixels. Keep the forward edge of
-- wide swings and clip their rear edge at the boss's origin.
function M.melee_box(pattern, defaults)
    defaults = defaults or {}
    local midpoint = math.max(0, tonumber(pattern.range) or tonumber(defaults.melee_range) or 80) * 0.5
    local width = math.max(0, tonumber(pattern.width)
        or math.max(midpoint, tonumber(defaults.default_melee_width) or 60))
    local height = math.max(0, tonumber(pattern.height) or tonumber(defaults.default_melee_height) or 80)
    local near, far = math.max(0, midpoint - width), midpoint + width
    return (near + far) * 0.5, (far - near) * 0.5, height
end

local CHARGE_PATTERN_OVERRIDES = {
    charge_speed = "dash_speed",
    charge_distance = "dash_distance",
    charge_telegraph_time = "telegraph_time",
    charge_duration = "duration",
    charge_cooldown = "cooldown",
    charge_recovery = "recovery",
    charge_edge_padding = "edge_padding",
}

local POSITIVE_CHARGE_OVERRIDES = {
    charge_speed = true,
    charge_distance = true,
}

local function apply_direct_charge_pattern_overrides(pattern, source)
    for source_key, pattern_key in pairs(CHARGE_PATTERN_OVERRIDES) do
        local value = tonumber(source[source_key])
        local accepts_value = value ~= nil and value >= 0
            and (not POSITIVE_CHARGE_OVERRIDES[source_key] or value > 0)
        if accepts_value then
            pattern[pattern_key] = value
        end
    end
end

local function apply_charge_pattern_overrides(pattern, source)
    if type(pattern) ~= "table" or type(source) ~= "table" then
        return
    end

    -- Also accept an explicit attack_tuning table for hand-authored presets.
    -- Tiled class properties are flattened, so their values are applied by
    -- the second pass and take precedence over this optional nested form.
    if type(source.attack_tuning) == "table" then
        apply_direct_charge_pattern_overrides(pattern, source.attack_tuning)
    end
    apply_direct_charge_pattern_overrides(pattern, source)
end

-- Convert framework patterns to project units before applying authored tuning.
function M.for_boss(base_pattern, config, phase, creator_pattern, tile_width)
    local factor = 1
    if not creator_pattern or base_pattern.scale_with_tiles == true then
        factor = tonumber(config and config.attack_pixel_scale) or (tile_width or 64) / 64
    end
    local pattern = M.scale_pattern(base_pattern, factor)
    if pattern.type == "charge" then
        apply_charge_pattern_overrides(pattern, config)
        apply_charge_pattern_overrides(pattern, phase)
    end
    return pattern
end

return M
