--- Attack Pattern Schema
-- Validates and normalises boss attack patterns from
-- mvtk/bosses/patterns/attack_patterns.lua (or any user-supplied source).
--
-- A valid pattern is a table with at minimum `type`. All other fields have
-- documented defaults in developer/config/boss_defaults.lua.
--
-- Supported fields (all optional unless noted):
--   type            — REQUIRED. "melee" | "projectile" | "aoe" | "beam"
--                     | "summon" | "special" | "charge" | "hazard" | "combo"
--                     | "grab" | "heal" | "buff" | "shield"
--                     | "parry_window" | "environmental" | "mine" | "wave"
--                     | "zone" | "ground_wave" | "sweep" | "rain" | "ring"
--                     | "leap" | "dive" | "reposition" | "hazard_pulse"
--   telegraph_time  — seconds of wind-up before hit frames
--   duration        — seconds the boss stays in its attack state after the warning
--   rehit_interval  — seconds between hits from one sustained attack, 0 for one hit
--   cooldown        — seconds before this pattern can fire again
--   damage          — base damage (multiplied by boss.damage_multiplier)
--   damage_type     — damage_types.lua id as text; omitted means physical
--   range           — reach / spawn distance. For melee, sets the midpoint
--                     before applying width and clipping the rear edge.
--   width, height   — hitbox half-extents for melee/AOE. A melee box starts
--                     from range/2 in front, with its rear edge clipped at
--                     the boss. Its warning uses those same bounds.
--   active_time     — melee hit window in seconds from the swing, separate
--                     from duration (attack recovery). 0 checks only at launch.
--   knockback       — horizontal knockback impulse
--   knockback_y     — vertical knockback impulse
--   iframes_on_hit  — override boss_defaults.iframes_on_hit for this attack
--   hitbox_group    — collision group for the spawned physics hitbox
--   telegraph_shape — "line" | "circle" | "cone" (melee uses its box)
--   telegraph_color — vmath.vector4 tint for the telegraph
--   telegraph_size  — { x = w, y = h } override (melee uses its box)
--   projectiles     — { count, spread, speed, lifetime, factory, damage }
--                     Damage uses pattern.damage, then projectiles.damage, then the boss default.
--   projectile_deflect — none | destroy (default) | reflect; features ship off
--   reflect_damage_mult — nonnegative returned-shot factor; -1 inherits combat config
--   aoe             — { radius, delay, active_time, knockback, factory }
--                     active_time is seconds after delay, 0 for a single check.
--   zone            — { shape, radius, width, height, target, delay, duration,
--                       tick, damage, status, status_duration, knockback }
--                     Shape is circle or box. Target is boss, player or anchor.
--                     For target = "anchor", set zone.anchor to an anchor name.
--                     Status is an id from developer/config/status_effects.lua.
--   ground_wave     — { speed, distance, height, width, both_sides, knockback, status }
--                     Height is jump clearance at the player root.
--   sweep           — { from_angle, to_angle, duration, windup, length, width }
--                     angular_speed can set duration from the arc (degrees/s).
--                     Angles are degrees relative to facing.
--   rain            — { count, gap_width, gap_at, stagger, speed, lifetime, shake }
--                     Gap placement is player, away, or random.
--   ring            — { count, volleys, volley_delay, rotate_per_volley, speed, lifetime }
--                     Volley rotation is in degrees.
--   leap            — { target, height, time, max_distance, land }
--                     Target is player (sampled at launch) or an anchor name.
--   dive            — { rise, rise_time, track_time, track_speed, speed, recover_time, land }
--                     Track speed caps rise and horizontal tracking, in pixels per second.
--                     Only for phases with movement profile hover or flying_patrol.
--   land            — In leap or dive: { radius, damage, knockback,
--                       ground_only, vertical_clearance }. Land damage wins
--                     over pattern.damage. Clearance reads the player root.
--   reposition      — { anchor, style, ["then"], timeout, warn_follow_up, then_overrides }
--                     Walk uses ground anchors and horizontal chase speed;
--                     blink accepts every anchor. Then names a follow-up.
--   combo           — Steps can set ["repeat"] (positive integer, delay
--                     seconds apart) and aim (facing, or player to turn first).
--   summon          — { count, enemy_type, skin, spawn_radius, max_active, drops }
--                     skin selects art; enemy_type supplies its archetype.
--                     max_active and drops inherit boss_defaults when absent.
--                     Summons use the shared enemy collection factory.
--   animation       — sprite animation id to play on the boss
--   avoid           — player hint for the generated catalogue, ignored by combat
--   followup_strikes — melee hits after the opening swing. Each delay is in
--                     seconds after the opening hit, with its own warning,
--                     active time, damage and optional range or animation.
--   environmental   — { effect_ids, duration, shake, flash }
--                     Duration holds the darkness, slow motion and gravity
--                     effects. Screen shake and flash accept optional settings.
--                     shake = {duration, intensity}, flash = {duration, color}.
--                     Flash color is a vmath.vector4 tint.
--                     Spawn adds uses the arena's room-owned enemy spawns.
--   hazard_pulse    — { hazard_ids, warn_time, duration }
--                     Omit the list or leave it empty to pulse all linked hazards.
--                     Duration is the dangerous time after the harmless blink.
--
-- @module attack_pattern_schema

local StatusConfig = require "developer.config.status_effects"
local Stationary = require "mvtk.bosses.stationary_attack_defaults"
local Moving = require "mvtk.bosses.moving_attack_defaults"
local Legacy = require "mvtk.bosses.legacy_attack_patterns"
local M = {}

M.ENVIRONMENTAL_TIMED = {
    darkness = true, slow_motion = true, low_gravity = true, high_gravity = true,
}
M.ENVIRONMENTAL_IMMEDIATE = {
    screen_shake = true, flash = true, spawn_adds = true,
}

local VALID_TYPES = {
    melee = true, projectile = true, aoe = true, beam = true,
    summon = true, special = true,
    charge = true, hazard = true, combo = true,
    grab = true, heal = true, buff = true, shield = true,
    parry_window = true, environmental = true, mine = true, wave = true,
    zone = true, ground_wave = true, sweep = true, rain = true, ring = true,
    leap = true, dive = true, reposition = true, hazard_pulse = true,
}

local function finite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

local function nonnegative(value)
    return finite(value) and value >= 0
end

local function positive(value)
    return finite(value) and value > 0
end

local function count(value)
    return positive(value) and value % 1 == 0
end

local function flag(value)
    return type(value) == "boolean"
end

local function choices(...)
    local allowed = {}
    for _, value in ipairs({...}) do allowed[value] = true end
    return function(value) return allowed[value] == true end
end

local REQUIRED_FORMAT = {
    [finite] = "must be a finite number",
    [nonnegative] = "must be a nonnegative number",
    [positive] = "must be a positive number",
    [count] = "must be a positive integer",
    [flag] = "must be true or false",
}

local function status_id(id, effects)
    return type(id) == "string" and (effects or StatusConfig.effects)[id] ~= nil
end

local STATIONARY_FIELDS = {
    zone = {
        shape = choices("circle", "box"), radius = positive, width = positive, height = positive,
        target = choices("boss", "player", "anchor"), anchor = Moving.is_anchor,
        delay = nonnegative, duration = positive, tick = positive,
        damage = nonnegative, status_duration = nonnegative, knockback = nonnegative,
        status = status_id,
    },
    ground_wave = {
        speed = positive, distance = positive, height = positive, width = positive,
        both_sides = flag, knockback = nonnegative, status = status_id, status_duration = nonnegative,
    },
    sweep = {
        from_angle = finite, to_angle = finite, duration = positive, windup = nonnegative,
        length = positive, width = positive, angular_speed = positive,
    },
    rain = {
        count = count, gap_width = positive, gap_at = choices("player", "away", "random"),
        stagger = nonnegative, speed = positive, lifetime = positive, shake = choices("light", "medium", "heavy"),
    },
    ring = {
        count = count, volleys = count, volley_delay = nonnegative,
        rotate_per_volley = finite, speed = positive, lifetime = positive, knockback = nonnegative,
    },
}

local function validate_settings(settings, prefix, fields, effective, effects)
    for key, value in pairs(settings) do
        local validator = fields[key] or (effective and (key == "damage" or key == "knockback") and nonnegative)
        if not validator then return false, prefix .. tostring(key) .. " is not a supported field" end
        if not validator(value, effects) then
            local problem = REQUIRED_FORMAT[validator] or "has invalid value '" .. tostring(value) .. "'"
            if key == "status" then problem = "has unknown status id '" .. tostring(value) .. "'" end
            return false, prefix .. key .. " " .. problem
        end
    end
    return true
end

local LAND_FIELDS = {
    radius = positive, damage = nonnegative, knockback = nonnegative,
    ground_only = flag, vertical_clearance = nonnegative,
}

local function nonempty(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

local function hazard_id_list(ids)
    if type(ids) ~= "table" then return false end
    local size = 0
    for index, id in pairs(ids) do
        if not count(index) or not nonempty(id) then return false end
        size = size + 1
    end
    for index = 1, size do
        if ids[index] == nil then return false end
    end
    return true
end

REQUIRED_FORMAT[hazard_id_list] = "must be a list of hazard IDs"
local HAZARD_PULSE_FIELDS = {hazard_ids = hazard_id_list, warn_time = nonnegative, duration = positive}
local HAZARD_PULSE_TIMES = {warn_time = nonnegative, duration = positive}
local HAZARD_PULSE_DEFAULTS = {warn_time = 0.6, duration = 2}

local MOVING_FIELDS = {
    leap = {
        target = function(value) return value == "player" or Moving.is_anchor(value) end,
        height = nonnegative, time = positive, max_distance = positive,
        land = function(value) return type(value) == "table" end,
    },
    dive = {
        rise = nonnegative, rise_time = nonnegative, track_time = nonnegative,
        track_speed = positive, speed = positive, recover_time = nonnegative,
        land = function(value) return type(value) == "table" end,
    },
    reposition = {
        anchor = Moving.is_anchor, style = choices("walk", "blink"),
        ["then"] = nonempty, timeout = nonnegative, warn_follow_up = flag,
        then_overrides = function(value) return type(value) == "table" end,
    },
}

local function validate_block(settings, prefix, kind, fields, effective, effects)
    local ok, err = validate_settings(settings, prefix, fields, effective, effects)
    if not ok then return false, err end
    if settings.land then
        ok, err = validate_settings(settings.land, prefix .. "land.", LAND_FIELDS)
        if not ok then return false, err end
    end
    if settings.then_overrides then
        ok, err = validate_settings(settings.then_overrides, prefix .. "then_overrides.", {
            damage = nonnegative, range = nonnegative, width = nonnegative, height = nonnegative,
            knockback = nonnegative, telegraph_time = nonnegative, damage_type = nonempty, parryable = flag,
        })
        if not ok then return false, err end
    end
    if kind == "reposition" and Moving.top[settings.anchor]
        and (settings.style == "walk" or (effective and not settings.style)) then
        return false, prefix .. 'anchor requires style = "blink" for top anchors'
    end
    if effective and kind == "zone" and settings.target == "anchor" and not settings.anchor then
        return false, prefix .. "anchor is required when target is 'anchor'"
    end
    return true
end

local function validate_kind(pattern, name, fields, effects)
    local prefix = string.format("pattern '%s' ", name)
    for _, key in ipairs({"telegraph_time", "duration", "cooldown", "damage", "knockback", "rehit_interval"}) do
        if pattern[key] ~= nil and not nonnegative(pattern[key]) then
            return false, prefix .. key .. " must be a nonnegative number"
        end
    end
    local kind = pattern.type
    local settings = pattern[kind]
    if settings == nil then return true end
    if type(settings) ~= "table" then return false, prefix .. kind .. " must be a table" end
    return validate_block(settings, prefix .. kind .. ".", kind, fields, false, effects)
end

function M.is_stationary(kind)
    return STATIONARY_FIELDS[kind] ~= nil
end

function M.is_moving(kind)
    return MOVING_FIELDS[kind] ~= nil
end

-- Validate authored settings and the effective options before use. The
-- effective check also covers values supplied by a creator's defaults file.
function M.stationary_options(pattern, defaults, effects)
    local kind = pattern.type
    local fields = STATIONARY_FIELDS[kind]
    if not fields then return nil end
    local name = pattern._attack_name or kind
    local ok, err = validate_kind(pattern, name, fields, effects)
    if not ok then return nil, err end
    local key = "default_" .. kind
    if defaults and defaults[key] ~= nil and type(defaults[key]) ~= "table" then
        return nil, string.format("pattern '%s' %s must be a table in boss_defaults.lua", name, key)
    end
    local settings = Stationary.options(pattern, defaults)
    ok, err = validate_block(settings, string.format("pattern '%s' effective %s.", name, kind), kind, fields, true, effects)
    if not ok then return nil, err end
    if kind == "sweep" and settings.angular_speed then
        settings.duration = math.abs(settings.to_angle - settings.from_angle) / settings.angular_speed
        if not positive(settings.duration) then return nil, "pattern '" .. name .. "' needs a finite, nonzero sweep arc" end
    end
    return settings
end

function M.moving_options(pattern, defaults)
    local kind = pattern.type
    local fields = MOVING_FIELDS[kind]
    if not fields then return nil end
    local name = pattern._attack_name or kind
    local ok, err = validate_kind(pattern, name, fields)
    if not ok then return nil, err end
    defaults = defaults or {}
    local key = "default_" .. kind
    local configured = defaults[key]
    if configured ~= nil then
        local prefix = string.format("pattern '%s' %s", name, key)
        if type(configured) ~= "table" then return nil, prefix .. " must be a table" end
        ok, err = validate_block(configured, prefix .. ".", kind, fields)
        if not ok then return nil, err end
    end
    local settings = Moving.options(pattern, defaults)
    ok, err = validate_block(settings, string.format("pattern '%s' effective %s.", name, kind), kind, fields, true)
    if not ok then return nil, err end
    return settings
end

-- Width and height are the space available to this cast. A missing width
-- means there is no confinement rectangle, unless the caller only knows
-- part of the geometry (as in authoring checks).
function M.arena_fit_failure(pattern, defaults, width, height, half_width, half_height)
    if pattern.type == "rain" then
        local settings = M.stationary_options(pattern, defaults)
        if not settings then return end
        if not width then return "arena_missing", "no confinement rectangle (arena or room bounds)" end
        if settings.gap_width >= width then
            return "arena_gap", string.format("gap width %g must be smaller than confinement width %g",
                settings.gap_width, width)
        end
        return
    end
    local anchored
    if pattern.type == "zone" then
        local settings = M.stationary_options(pattern, defaults)
        anchored = settings and settings.target == "anchor"
    elseif pattern.type == "leap" or pattern.type == "reposition" then
        local settings = M.moving_options(pattern, defaults)
        anchored = settings and (pattern.type == "reposition" or settings.target ~= "player")
    end
    if not anchored then return end
    if not width then return "arena_missing", "no confinement rectangle for the destination anchor" end
    if half_width and 2 * half_width > width or height and half_height and 2 * half_height > height then
        return "arena_anchor", "the boss cannot fit at the destination anchor"
    end
end

function M.slam_dodge_height(options, defaults)
    return math.max(0, tonumber(options.vertical_clearance or options.jump_clearance)
        or tonumber(defaults.default_slam_dodge_height) or 0)
end

-- A nil limit identifies attacks without a floor-relative damage band.
function M.floor_height_limit(pattern, defaults, effects)
    local kind = pattern.type
    if kind == "ground_wave" then
        local settings = M.stationary_options(pattern, defaults, effects)
        return settings and settings.height
    elseif kind == "aoe" and pattern.aoe and pattern.aoe.ground_only then
        return M.slam_dodge_height(pattern.aoe, defaults)
    elseif kind == "leap" or kind == "dive" then
        local settings = M.moving_options(pattern, defaults)
        if settings and settings.land.ground_only then return M.slam_dodge_height(settings.land, defaults), settings end
    end
end

function M.hazard_pulse_options(pattern, defaults)
    local name = pattern._attack_name or "hazard_pulse"
    local ok, err = validate_kind(pattern, name, HAZARD_PULSE_FIELDS)
    if not ok then return nil, err end

    local configured = defaults and defaults.default_hazard_pulse
    local prefix = string.format("pattern '%s' default_hazard_pulse", name)
    if configured ~= nil then
        if type(configured) ~= "table" then return nil, prefix .. " must be a table in boss_defaults.lua" end
        ok, err = validate_settings(configured, prefix .. ".", HAZARD_PULSE_TIMES)
        if not ok then return nil, err end
    end
    local settings = {}
    for key, value in pairs(HAZARD_PULSE_DEFAULTS) do settings[key] = value end
    for key, value in pairs(configured or {}) do settings[key] = value end
    for key, value in pairs(pattern.hazard_pulse or {}) do settings[key] = value end
    if not finite(settings.warn_time + settings.duration) then
        return nil, string.format("pattern '%s' hazard_pulse total time must be finite", name)
    end
    return settings
end

function M.tracking_beam_windup(pattern, defaults)
    local beam = pattern.beam
    local lock_time = beam.lock_time
    if lock_time == nil then lock_time = defaults and defaults.default_tracking_beam_lock_time end
    local name = pattern._attack_name or "beam"
    if not positive(lock_time) then
        return nil, "pattern '" .. name .. "' needs a positive tracking beam lock time"
    end
    if not positive(beam.track_time) or not finite(beam.track_time + lock_time) then
        return nil, "pattern '" .. name .. "' needs a finite tracking beam warning"
    end
    return beam.track_time + lock_time
end

-- A prepared pattern is usable only if its inherited options are valid too.
function M.effective_options(pattern, defaults, effects)
    if pattern.type == "hazard_pulse" then return M.hazard_pulse_options(pattern, defaults) end
    if pattern.type == "beam" and pattern.beam and pattern.beam.track_time then
        return M.tracking_beam_windup(pattern, defaults)
    end
    if M.is_moving(pattern.type) then return M.moving_options(pattern, defaults) end
    if M.is_stationary(pattern.type) then return M.stationary_options(pattern, defaults, effects) end
    return true
end

local function validate_combo(steps, name)
    local prefix = string.format("pattern '%s' combo", name)
    if type(steps) ~= "table" then return false, prefix .. " must be a table" end
    for i, step in ipairs(steps) do
        if type(step) ~= "table" then return false, prefix .. "[" .. i .. "] must be a table" end
        if step["repeat"] ~= nil and not count(step["repeat"]) then
            return false, prefix .. "[" .. i .. "].repeat must be a positive integer"
        end
        if step.aim ~= nil and step.aim ~= "player" and step.aim ~= "facing" then
            return false, prefix .. "[" .. i .. "].aim must be 'facing' or 'player'"
        end
    end
    return true
end

local STRIKE_FIELDS = {
    delay = positive, telegraph_time = positive, active_time = positive, damage = nonnegative,
    range = positive, animation = nonempty, parryable = flag,
}

local BEAM_FIELDS = {
    target = choices("facing", "player"), length = positive, width = positive,
    windup = nonnegative, duration = nonnegative, track_time = positive,
    tracking_speed = positive, lock_time = positive,
}

local function validate_beam(beam, name)
    local prefix = "pattern '" .. name .. "' beam."
    if type(beam) ~= "table" then return false, prefix .. "must be a table" end
    local ok, err = validate_settings(beam, prefix, BEAM_FIELDS)
    if not ok then return false, err end
    if beam.track_time then
        if not beam.tracking_speed then return false, prefix .. "track_time requires tracking_speed" end
        if beam.windup ~= nil then return false, prefix .. "use lock_time for the wind-up of a tracking beam" end
        if beam.target ~= nil then return false, prefix .. "tracking already aims the beam at the player" end
    elseif beam.lock_time or beam.tracking_speed then
        return false, prefix .. "lock_time and tracking_speed require track_time"
    end
    return true
end

local function validate_strikes(strikes, name)
    local prefix = "pattern '" .. name .. "' followup_strikes."
    if type(strikes) ~= "table" then return false, prefix .. "must be a list" end
    local previous, checked = 0, 0
    for index, strike in ipairs(strikes) do
        if type(strike) ~= "table" then return false, prefix .. index .. " must be a table" end
        local ok, err = validate_settings(strike, prefix .. index .. ".", STRIKE_FIELDS)
        if not ok then return false, err end
        if not strike.delay or not strike.telegraph_time or not strike.active_time or strike.damage == nil
            or strike.delay <= previous or strike.telegraph_time >= strike.delay then
            return false, prefix .. index .. " needs increasing hit times, an earlier warning, an active time and damage"
        end
        previous, checked = strike.delay, index
    end
    for key in pairs(strikes) do
        if not count(key) or key > checked then return false, prefix .. "must be a list" end
    end
    return true
end

local function validate_environmental(env, name)
    local prefix = string.format("pattern '%s' environmental.", name)
    if type(env) ~= "table" then return false, "pattern '" .. name .. "' environmental must be a table" end
    local ids = env.effect_ids
    if ids ~= nil then
        if type(ids) ~= "table" then return false, prefix .. "effect_ids must be a list" end
        local count = 0
        for index, id in pairs(ids) do
            if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then
                return false, prefix .. "effect_ids must be a list"
            end
            if type(id) ~= "string" or not (M.ENVIRONMENTAL_TIMED[id] or M.ENVIRONMENTAL_IMMEDIATE[id]) then
                return false, prefix .. "effect_ids contains unknown effect '" .. tostring(id) .. "'"
            end
            count = count + 1
        end
        for index = 1, count do
            if ids[index] == nil then return false, prefix .. "effect_ids must be a list" end
        end
    end
    if env.duration ~= nil and (type(env.duration) ~= "number" or not (env.duration >= 0)) then
        return false, prefix .. "duration must be a nonnegative number"
    end
    for _, field in ipairs({"shake", "flash"}) do
        if env[field] ~= nil and type(env[field]) ~= "table" then
            return false, prefix .. field .. " must be a table"
        end
    end
    return true
end

-- Validate a pattern. Returns (true) or (false, error_msg).
function M.validate(pattern, name, effects)
    name = name or "?"
    if type(pattern) ~= "table" then
        return false, string.format("pattern '%s' is not a table", name)
    end
    if not pattern.type or not VALID_TYPES[pattern.type] then
        return false, string.format("pattern '%s' has invalid type '%s'",
            name, tostring(pattern.type))
    end
    if pattern.avoid ~= nil and not nonempty(pattern.avoid) then
        return false, string.format("pattern '%s' avoid must be nonempty text", name)
    end
    local fields = STATIONARY_FIELDS[pattern.type] or MOVING_FIELDS[pattern.type]
        or (pattern.type == "hazard_pulse" and HAZARD_PULSE_FIELDS)
    if fields then
        return validate_kind(pattern, name, fields, effects)
    end
    if pattern.telegraph_time ~= nil and not nonnegative(pattern.telegraph_time) then
        return false, string.format("pattern '%s' telegraph_time must be >= 0", name)
    end
    if pattern.type == "combo" and pattern.combo then
        return validate_combo(pattern.combo, name)
    end
    if pattern.type == "melee" and pattern.followup_strikes then
        return validate_strikes(pattern.followup_strikes, name)
    end
    if pattern.type == "beam" and pattern.beam then
        return validate_beam(pattern.beam, name)
    end
    if pattern.type == "special" or pattern.type == "hazard" then
        return Legacy.validate(pattern, name)
    end
    if pattern.type == "environmental" and pattern.environmental ~= nil then
        return validate_environmental(pattern.environmental, name)
    end
    return true
end

-- Called on an independent cast snapshot after the caller applies its tuning.
function M.resolve(pattern, defaults, warn, effects)
    local name = pattern._attack_name or pattern.type or "?"
    local ok, err = M.validate(pattern, name, effects)
    if not ok then return nil, err end
    local kind = pattern.type
    Legacy.translate(pattern, defaults, warn)
    if kind ~= pattern.type then
        ok, err = M.validate(pattern, name, effects)
        if not ok then return nil, err end
    end
    return pattern
end

-- Validate every entry in a patterns module. Returns count + error list.
function M.validate_all(patterns)
    local errors = {}
    local count = 0
    for name, pat in pairs(patterns or {}) do
        if type(pat) == "table" then
            count = count + 1
            local ok, err = M.validate(pat, name)
            if not ok then
                errors[#errors + 1] = err
            end
        end
    end
    return count, errors
end

return M
