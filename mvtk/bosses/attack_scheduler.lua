-- Pure choice and validation. A boss supplies the clock, readiness and RNG.
local Defaults = require "mvtk.bosses.attack_schedule_defaults"
local AttackScale = require "mvtk.bosses.attack_scale"
local Schema = require "mvtk.bosses.attack_pattern_schema"
local Geometry = require "mvtk.combat.attack_geometry"
local M = {}

local CANONICAL_ATTACK_TYPES = {
    aoe = "aoe",
    beam = "beam",
    blade_storm = "aoe",
    charge = "charge",
    clone = "summon",
    combo = "melee",
    crystal_shard_enemy = "summon",
    dive = "charge",
    explosion = "aoe",
    fire_wave = "beam",
    grab = "grab",
    ground_wave = "aoe",
    hazard = "aoe",
    hazard_pulse = "special",
    leap = "charge",
    melee = "melee",
    poison_cloud = "aoe",
    projectile = "projectile",
    rain = "projectile",
    reposition = "special",
    ring = "projectile",
    shadow_spawn = "summon",
    slime = "summon",
    sweep = "beam",
    zone = "aoe",
    special = "special",
    spike_trap = "aoe",
    summon = "summon",
    teleport_attack = "charge",
    thorn_minion = "summon",
}

local CONDITIONS = {
    player_above = function(ctx)
        return ctx.dy > (ctx.player_height_dead_band or Defaults.player_height_dead_band)
    end,
    player_below = function(ctx)
        return ctx.dy < -(ctx.player_height_dead_band or Defaults.player_height_dead_band)
    end,
    player_in_front = function(ctx) return ctx.dx * ctx.facing > 0 end,
    player_behind = function(ctx) return ctx.dx * ctx.facing < 0 end,
    player_grounded = function(ctx) return ctx.player_grounded ~= false end,
    player_airborne = function(ctx) return ctx.player_grounded == false end,
    near_wall = function(ctx) return ctx.near_wall end,
    partner_alive = function(ctx) return ctx.partners_alive > 0 end,
    partner_defeated = function(ctx) return ctx.partners_total > ctx.partners_alive end,
    last_survivor = function(ctx) return ctx.partners_total > 0 and ctx.partners_alive == 0 end,
}

local PARAMETER_CONDITIONS = {
    boss_health_below = function(ctx, fraction) return ctx.boss_health < fraction end,
    boss_health_above = function(ctx, fraction) return ctx.boss_health > fraction end,
    adds_below = function(ctx, count) return ctx.adds_alive < count end,
    phase_time_above = function(ctx, seconds) return ctx.phase_time > seconds end,
    after = function(ctx, attack) return ctx.last_attack == attack end,
}

local MODES = {weighted = true, sequence = true, shuffle = true, opener = true}
local compiled_conditions = setmetatable({}, {__mode = "k"})

local function nonnegative(value)
    return type(value) == "number" and value >= 0 and value < math.huge
end

local function condition(name, known_patterns)
    if type(name) ~= "string" then return nil end
    if CONDITIONS[name] then return {name = name, test = CONDITIONS[name]} end
    local kind, argument = name:match("^([^:]+):(.+)$")
    local test = PARAMETER_CONDITIONS[kind]
    if not test then return nil end
    if kind == "after" then
        if not known_patterns[argument] then return nil end
    else
        argument = tonumber(argument)
        if not nonnegative(argument) then return nil end
        if kind == "adds_below" and argument % 1 ~= 0 then return nil end
        if (kind == "boss_health_above" or kind == "boss_health_below") and argument > 1 then
            return nil
        end
    end
    return {name = name, test = test, argument = argument}
end

local function is_list(list)
    if type(list) ~= "table" then return false end
    local length = #list
    local count = 0
    for index in pairs(list) do
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > length then
            return false
        end
        count = count + 1
    end
    return count == length
end

local function validate_entry(entry, known_patterns, report)
    if type(entry) ~= "table" then
        report("must be a table")
        return
    end
    compiled_conditions[entry] = nil
    if type(entry.attack) ~= "string" or not known_patterns[entry.attack] then
        report("unknown attack pattern " .. tostring(entry.attack), "unknown_pattern")
    end
    if entry.weight ~= nil and (not nonnegative(entry.weight) or entry.weight == 0) then
        report("weight must be a positive number")
    end
    for _, field in ipairs({"min_range", "max_range", "cooldown"}) do
        if entry[field] ~= nil and not nonnegative(entry[field]) then
            report(field .. " must be a nonnegative number")
        end
    end
    if nonnegative(entry.min_range) and nonnegative(entry.max_range) and entry.min_range > entry.max_range then
        report("min_range exceeds max_range")
    end
    if entry.max_repeat ~= nil and (not nonnegative(entry.max_repeat)
        or entry.max_repeat < 1 or entry.max_repeat % 1 ~= 0) then
        report("max_repeat must be a positive whole number")
    end
    for _, field in ipairs({"once_per_phase", "gap_closer"}) do
        if entry[field] ~= nil and type(entry[field]) ~= "boolean" then
            report(field .. " must be true or false")
        end
    end
    if entry.overrides ~= nil and type(entry.overrides) ~= "table" then
        report("overrides must be a table")
    end
    if entry.when ~= nil then
        if not is_list(entry.when) then
            report("when must be a list of conditions")
            return
        end
        local parsed = {}
        for _, name in ipairs(entry.when) do
            local check = condition(name, known_patterns)
            if not check then
                report("unknown or invalid condition " .. tostring(name))
            else
                parsed[#parsed + 1] = check
            end
        end
        if #parsed == #entry.when then compiled_conditions[entry] = parsed end
    end
end

local function range_limits(entry)
    return entry.min_range or 0, entry.max_range or math.huge
end

function M.coverage_scope(profile, leash)
    if profile == "stationary" then return 0, "this phase stands still" end
    if profile == "teleport" then return 0, "this phase teleports" end
    leash = tonumber(leash) or 0
    if leash > 0 then return leash, "this phase has a Leash radius of " .. leash .. " pixels" end
end

-- Coverage is positional. Cooldowns and conditions vary during the fight and
-- sequence can advance once its wait expires. A ready gap closer can answer
-- beyond its upper range, but cannot fill a gap below its minimum.
function M.coverage_warning(name, moveset, profile, width, leash, usable)
    local first, why = M.coverage_scope(profile, leash)
    if first == nil then return nil end
    local last = width or Defaults.coverage_distance
    if first > last then return nil end
    local ranges = {}
    for _, entry in ipairs(moveset.entries) do
        if not entry._missing_pattern and (not usable or usable(entry)) then
            local minimum, maximum = range_limits(entry)
            ranges[#ranges + 1] = {min = minimum, max = entry.gap_closer and math.huge or maximum}
        end
    end
    table.sort(ranges, function(a, b) return a.min < b.min end)
    local covered, has_coverage = first, false
    local function warning(from, to)
        return tostring(name) .. " (" .. tostring(profile) .. ") has no attack coverage in the "
            .. from .. " to " .. to .. " pixel band because " .. why .. "."
    end
    for _, range in ipairs(ranges) do
        if range.min > covered then return warning(covered, math.min(range.min, last)) end
        if range.max >= covered then
            has_coverage = true
            covered = range.max
            if covered >= last then return nil end
        end
    end
    if not has_coverage or covered < last then return warning(covered, last) end
end

-- Return errors and, for a phase's validation view with an effective profile,
-- a separate list of range coverage warnings. Cache parsed entry conditions.
function M.validate(name, moveset, known_patterns, on_error)
    local errors, warnings = {}, {}
    local function report(message, code)
        errors[#errors + 1] = tostring(name) .. ": " .. message
        if on_error then on_error(errors[#errors], code) end
    end
    if type(moveset) ~= "table" then
        report("moveset must be a table")
        return errors, warnings
    end
    if moveset.mode ~= nil and not MODES[moveset.mode] then report("unknown mode " .. tostring(moveset.mode)) end
    if moveset.sequence_wait ~= nil and not nonnegative(moveset.sequence_wait) then
        report("sequence_wait must be a nonnegative number")
    end
    if not is_list(moveset.entries) then
        report("entries must be a list of attacks")
        return errors, warnings
    end
    local names = {}
    for index, entry in ipairs(moveset.entries) do
        validate_entry(entry, known_patterns, function(message, code)
            report("entry " .. index .. " " .. message, code)
        end)
        if type(entry) == "table" and type(entry.attack) == "string" then names[entry.attack] = true end
    end
    if moveset.opener ~= nil then
        if not is_list(moveset.opener) then
            report("opener must be a list of attack names from entries")
        else
            for index, attack in ipairs(moveset.opener) do
                if type(attack) ~= "string" or not names[attack] or not known_patterns[attack] then
                    report("opener entry " .. index .. " names a missing attack " .. tostring(attack))
                end
            end
        end
    end
    if #errors == 0 then
        local warning = M.coverage_warning(name, moveset, moveset.movement_profile)
        if warning then warnings[1] = warning end
    end
    return errors, warnings
end

local STATIONARY_REACH = {
    zone = function(settings)
        if settings.target ~= "boss" then return nil end
        return settings.shape == "box" and settings.width * 0.5 or settings.radius
    end,
    ground_wave = function(settings) return settings.distance end,
    sweep = function(settings) return settings.length end,
    rain = function() return nil end,
    ring = function(settings) return settings.speed * settings.lifetime end,
}

-- How far a legacy attack reaches from the boss, in world pixels, or nil when
-- distance does not limit it (it lands on the player, or does not aim at all).
-- A boss must not slam the floor, fire a beam or loose a shot that cannot reach.
local function legacy_reach(pattern, kind, chase_range, defaults, effects)
    local function default(key)
        return tonumber(defaults and defaults[key]) or Defaults.reach[key]
    end
    local kind_of = pattern.type
    local stationary = STATIONARY_REACH[kind_of]
    if stationary then
        local settings = Schema.stationary_options(pattern, defaults, effects)
        local reach = settings and stationary(settings)
        return reach and math.max(chase_range, reach)
    elseif kind_of == "leap" then
        local settings = Schema.moving_options(pattern, defaults)
        return settings and settings.target == "player" and settings.max_distance or nil
    elseif kind_of == "dive" or kind_of == "reposition" then
        return nil
    elseif kind_of == "melee" then
        local offset, half_w, half_h = AttackScale.melee_box(pattern, defaults)
        return offset + half_w, {center = {x = offset, y = 0}, half_w = half_w, half_h = half_h}
    elseif kind == "melee" or kind == "grab" then
        local reach = kind == "grab" and type(pattern.grab) == "table" and pattern.grab.reach
        return math.max(chase_range, tonumber(reach or pattern.range) or 0)
    elseif kind == "charge" then
        return chase_range + AttackScale.charge_distance(pattern)
    elseif kind_of == "aoe" then
        local aoe = type(pattern.aoe) == "table" and pattern.aoe or {}
        if aoe.target == "player" then return nil end
        return math.max(chase_range, tonumber(aoe.radius) or default("default_aoe_radius"))
    elseif kind_of == "wave" then
        local wave = type(pattern.wave) == "table" and pattern.wave or {}
        return math.max(chase_range, (tonumber(wave.rings) or default("default_wave_rings"))
            * (tonumber(wave.radius_step) or default("default_wave_radius_step")))
    elseif kind_of == "beam" then
        local beam = type(pattern.beam) == "table" and pattern.beam or {}
        return math.max(chase_range, tonumber(beam.length) or default("default_beam_length"))
    elseif kind_of == "projectile" then
        local shots = type(pattern.projectiles) == "table" and pattern.projectiles or {}
        return math.max(chase_range, (tonumber(shots.speed) or default("default_projectile_speed"))
            * (tonumber(shots.lifetime) or default("default_projectile_life")))
    elseif kind_of == "hazard" then
        -- Preserve reach for the generic hazard. Named hazards have resolved
        -- to their actual kind before they reach this function.
        local hazard = type(pattern.hazard) == "table" and pattern.hazard or {}
        if hazard.position == "boss" then
            local radius = tonumber(hazard.radius) or (tonumber(hazard.width) and hazard.width * 0.25)
                or (tonumber(hazard.count) and math.max(48, hazard.count * 18)) or default("default_aoe_radius")
            return math.max(chase_range, radius)
        end
    end
    return nil
end

-- Reach shared by implicit scheduling and the framework catalogue.
function M.pattern_reach(pattern, chase_range, defaults, effects)
    return legacy_reach(pattern, CANONICAL_ATTACK_TYPES[pattern.type] or "special", chase_range, defaults, effects)
end

-- A string selects a built-in profile. The runtime can pass loaded weights.
-- Movement range and distances from the pattern resolver are in world pixels.
-- phase.defaults may carry the project's boss_defaults table for missing reach fields.
function M.implicit(attack_names, behavior, resolve_pattern, phase)
    local weights = behavior
    if type(weights) ~= "table" then
        local key = type(behavior) == "string" and behavior:lower() or "random"
        weights = Defaults.behaviors[key] or Defaults.behaviors.random
    end
    local moveset = {mode = "weighted", entries = {}, movement_profile = phase and phase.movement_profile}
    local chase_range = tonumber(phase and phase.attack_range) or Defaults.attack_range
    for _, name in ipairs(attack_names) do
        local pattern = resolve_pattern(name)
        local kind = pattern and (CANONICAL_ATTACK_TYPES[pattern.type] or "special") or "special"
        local entry = {attack = name, weight = weights[kind], max_repeat = weights.max_repeat}
        if pattern then
            entry.max_range, entry._melee_box = M.pattern_reach(pattern, chase_range, phase and phase.defaults, phase and phase.effects)
        else
            entry._missing_pattern = true
        end
        moveset.entries[#moveset.entries + 1] = entry
    end
    return moveset
end

local function failed_condition(entry, ctx)
    if not entry.when then return nil end
    local checks = assert(compiled_conditions[entry], "validate moveset conditions before choosing attacks")
    for _, check in ipairs(checks) do
        if not check.test(ctx, check.argument) then return check.name end
    end
end

local function range_boundary(entry, ctx, distance)
    local box, body = entry._melee_box, ctx.melee_body
    if box and body then
        if not Geometry.rect_in_box(box.center, box.half_w, box.half_h, body) then
            local distance, boundary = math.abs(body.x), entry.max_range + body.half_w
            return boundary, distance, distance > boundary
        end
        return
    end
    local minimum, maximum = range_limits(entry)
    if entry.min_range and distance < minimum then return minimum end
    if entry.max_range and distance > maximum then return maximum, nil, true end
end

-- Pick a chase stop from the phase's ranges, independent of combat state.
function M.approach_distance(moveset, attack_range, margin)
    local nearer_max
    for _, entry in ipairs(moveset.entries) do
        local min_range, max_range = entry.min_range, entry.max_range
        if not entry._missing_pattern then
            if (not min_range or min_range <= attack_range)
                and (not max_range or attack_range <= max_range) then
                return attack_range
            end
            if max_range and max_range < attack_range then
                nearer_max = math.max(nearer_max or 0, max_range)
            end
        end
    end
    if nearer_max == nil then return attack_range end
    return math.max(0, nearer_max - math.max(0, tonumber(margin) or 0))
end

local function candidates(entries, ctx, state, reasons, rejected)
    local ready, gap = {}, {}
    local nearest_delta, cooling, conditions, height, floor = math.huge, false, false, false, false
    for index, entry in ipairs(entries) do
        local failed = failed_condition(entry, ctx)
        if rejected[index] then
            reasons[index] = rejected[index]
        elseif entry.once_per_phase and state.once and state.once[index] then
            reasons[index] = "once_per_phase"
        elseif failed then
            reasons[index], conditions = failed, true
        else
            local cooldown = entry.cooldown or (entry.overrides and entry.overrides.cooldown)
            local available, unavailable, floor_attack = ctx.is_ready(entry.attack, cooldown, entry)
            local distance = floor_attack and math.abs(ctx.dx) or ctx.distance
            local boundary, body_distance, too_far = range_boundary(entry, ctx, distance)
            if available and floor_attack and ctx.floor_reach and (not boundary or entry.gap_closer and too_far) then
                local reached, reason = ctx.floor_reach(floor_attack)
                if not reached then available, unavailable = false, reason end
            end
            if not available then
                reasons[index] = unavailable or "cooldown"
                height = height or unavailable == "height"
                floor = floor or unavailable == "floor"
                cooling = cooling or unavailable == nil
            elseif boundary then
                reasons[index] = "range"
                local delta = math.abs((body_distance or distance) - boundary)
                if not reasons.nearest_range or delta < nearest_delta then
                    nearest_delta, reasons.nearest_range = delta, boundary
                end
                if entry.gap_closer and too_far then gap[#gap + 1] = index end
            else
                ready[#ready + 1] = index
            end
        end
    end
    if reasons.nearest_range then
        reasons.status = "range"
    elseif height then
        reasons.status = "height"
    elseif floor then
        reasons.status = "floor"
    elseif cooling then
        reasons.status = "cooldown"
    elseif conditions then
        reasons.status = "conditions"
    else
        reasons.status = "no_usable_entries"
    end
    return ready, gap
end

local function prefer_variety(entries, choices, state, reasons)
    local preferred = {}
    for _, index in ipairs(choices) do
        local entry = entries[index]
        if entry.attack ~= state.last or state.repeats < (entry.max_repeat or 2) then
            preferred[#preferred + 1] = index
        end
    end
    if #preferred == 0 or #preferred == #choices then return choices end
    for _, index in ipairs(choices) do
        local entry = entries[index]
        if entry.attack == state.last and state.repeats >= (entry.max_repeat or 2) then
            reasons[index] = "max_repeat"
        end
    end
    return preferred
end

local function weighted(entries, choices, random)
    local total = 0
    for _, index in ipairs(choices) do total = total + (entries[index].weight or 1) end
    local roll = random() * total
    for _, index in ipairs(choices) do
        roll = roll - (entries[index].weight or 1)
        if roll < 0 then return index end
    end
    return choices[#choices]
end

local function opener(moveset, choices, state)
    local list = moveset.opener or {}
    while (state.opener_index or 0) < #list do
        local slot = (state.opener_index or 0) + 1
        state.opener_index = slot
        for _, index in ipairs(choices) do
            if moveset.entries[index].attack == list[slot] then return index end
        end
    end
end

local function sequence(moveset, reasons, ctx, state, retrying)
    local count = #moveset.entries
    local wait = moveset.sequence_wait or ctx.sequence_wait or Defaults.sequence_wait
    for _ = 1, count do
        local index = state.sequence_index or 1
        if reasons[index] and not retrying then
            state.sequence_wait_since = state.sequence_wait_since or ctx.phase_time
            local Clock = require "mvtk.bosses.boss_clock"
            if not Clock.reached(ctx.phase_time, state.sequence_wait_since + wait) then return nil end
        end
        state.sequence_wait_since = nil
        state.sequence_index = index % count + 1
        if not reasons[index] then return index end
    end
end

local function shuffle(choices, state, random)
    state.shuffle_used = state.shuffle_used or {}
    local bag = {}
    for _, index in ipairs(choices) do
        if not state.shuffle_used[index] then bag[#bag + 1] = index end
    end
    if #bag == 0 then
        state.shuffle_used = {}
        bag = choices
    end
    return bag[math.min(#bag, math.floor(random() * #bag) + 1)]
end

local function choose(moveset, ctx, state, random, reasons, rejected)
    local entries = moveset.entries
    local ready, gap = candidates(entries, ctx, state, reasons, rejected)
    local mode = moveset.mode or "weighted"
    local selected, selection_mode
    if mode == "sequence" then
        if #ready > 0 then selected = opener(moveset, ready, state) end
        selection_mode = selected and "opener" or "sequence"
        if not selected then selected = sequence(moveset, reasons, ctx, state, next(rejected) ~= nil) end
    elseif #ready > 0 then
        ready = prefer_variety(entries, ready, state, reasons)
        selected = opener(moveset, ready, state)
        if selected then
            selection_mode = "opener"
        elseif mode == "shuffle" then
            selected, selection_mode = shuffle(ready, state, random), "shuffle"
        else
            selected, selection_mode = weighted(entries, ready, random), "weighted"
        end
    end
    if not selected and #ready == 0 and #gap > 0 then
        if mode ~= "sequence" then gap = prefer_variety(entries, gap, state, reasons) end
        selected, selection_mode = weighted(entries, gap, random), "gap_closer"
    end
    if not selected and #ready > 0 then reasons.status = "sequence_wait" end
    for _, index in ipairs(ready) do
        if index ~= selected then reasons[index] = selection_mode end
    end
    return selected, selection_mode
end

-- A cast rejected after selection is excluded for this decision only.
-- Retries use the same chooser and random stream, without taking cooldown,
-- once-per-phase or repeat credit for a cast the boss cannot start.
function M.pick(moveset, ctx, state, random)
    if #moveset.entries == 0 then return nil, {status = "no_entries"} end
    if ctx.engaged == false then return nil, {status = "not_engaged"} end
    local rejected, first_rejection = {}, nil
    local reasons, selected, selection_mode, entry
    while true do
        reasons = {arena_rejection = first_rejection}
        selected, selection_mode = choose(moveset, ctx, state, random, reasons, rejected)
        if not selected then return nil, reasons end
        entry = moveset.entries[selected]
        local reason = ctx.cast_failure and ctx.cast_failure(entry)
        if not reason then break end
        rejected[selected] = reason
        first_rejection = first_rejection or reason
    end
    reasons[selected], reasons.status = nil, "picked"
    if selection_mode == "shuffle" or selection_mode == "opener" and moveset.mode == "shuffle" then
        state.shuffle_used = state.shuffle_used or {}
        state.shuffle_used[selected] = true
    end
    if entry.once_per_phase then
        state.once = state.once or {}
        state.once[selected] = true
    end
    state.repeats = entry.attack == state.last and state.repeats + 1 or 1
    state.last = entry.attack
    return entry, reasons
end

return M
