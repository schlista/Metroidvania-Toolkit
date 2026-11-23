-- Translate compatibility names before the scheduler or an attack sees them.
local M = {}
local Patterns = require "mvtk.bosses.patterns.attack_patterns"
local reported_positions = {}

local function damage(pattern, block, fallback)
    return block.damage or block.attack_damage or pattern.damage or block.damage_per_second or fallback
end

local function extend_warning(pattern, block)
    local delay = block.delay
    if type(delay) == "number" then
        pattern.telegraph_time = (pattern.telegraph_time or 0) + delay
    end
end

local function zone(pattern, block, defaults, status, warn)
    local target = block.position
    if target ~= nil and target ~= "boss" and target ~= "player" and warn
        and not reported_positions[pattern._attack_name] then
        reported_positions[pattern._attack_name] = true
        local value = tostring(target)
        if type(target) == "table" then
            value = ("{x=%s, y=%s}"):format(tostring(target.x), tostring(target.y))
        end
        warn(("pattern '%s' hazard.position %s is not supported; the zone goes at the player")
            :format(pattern._attack_name, value))
    end
    local spike = status == nil
    local example = spike and Patterns.root_spike or Patterns.poison_cloud
    local tick = block.tick or example.zone.tick
    local radius = block.radius or (block.count and math.max(48, block.count * 18))
        or defaults.default_aoe_radius or 150
    local amount = block.damage_per_second and block.damage_per_second * tick
    local width, height = block.width, block.height
    pattern.zone = {
        target = target == "boss" and "boss" or "player",
        shape = (width or height) and "box" or "circle", radius = radius,
        width = width or radius * 2, height = height or radius * 2,
        delay = block.delay or 0,
        duration = block.active_duration or block.lifetime or example.zone.duration,
        tick = tick, damage = block.damage or amount or pattern.damage or defaults.default_aoe_damage or 3,
        status = status, knockback = block.knockback or pattern.knockback or defaults.default_aoe_knockback,
    }
    if spike then
        if pattern.persist == nil then pattern.persist = false end
        if pattern.telegraph_time <= 0 then pattern.telegraph_time = example.telegraph_time end
    end
end

local SPECIAL = {
    teleport_attack = function(pattern, block, defaults)
        local reach = block.attack_range or block.radius
        local overrides
        if not block["then"] then
            overrides = {
                damage = damage(pattern, block, defaults.default_aoe_damage),
                range = reach, width = block.width or (reach and reach * 0.5), height = block.height,
                knockback = block.knockback or pattern.knockback,
                telegraph_time = block.delay,
                damage_type = pattern.damage_type, parryable = pattern.parryable,
            }
        end
        pattern.telegraph_shape = "circle"
        pattern.reposition = {anchor = "behind_player", style = "blink",
            ["then"] = block["then"] or "teleport_slash", warn_follow_up = true, then_overrides = overrides}
        if not overrides then extend_warning(pattern, block) end
        return "reposition"
    end,
    blade_storm = function(pattern, block, defaults)
        pattern.damage = damage(pattern, block, defaults.default_aoe_damage)
        local speed = block.speed or 300
        local reach = block.radius or block.width or block.height
        pattern.ring = {count = block.count or block.projectile_count, speed = speed,
            lifetime = block.lifetime or (reach and reach / speed), knockback = block.knockback}
        extend_warning(pattern, block)
        return "ring"
    end,
    explosion = function(pattern, block, defaults)
        pattern.damage = damage(pattern, block, defaults.default_aoe_damage)
        pattern.aoe = {radius = block.radius or block.width or block.height or 100,
            delay = block.delay or 0.8, knockback = block.knockback or pattern.knockback,
            target = "boss"}
        return "aoe"
    end,
    clone = function(pattern, block)
        local summon = pattern.summon or {}
        summon.count = summon.count or block.count
        summon.spawn_radius = summon.spawn_radius or block.radius or block.width or block.height
        pattern.summon = summon
        pattern.telegraph_shape = pattern.telegraph_shape or "circle"
        extend_warning(pattern, block)
        return "summon"
    end,
}

local HAZARD = {
    poison_cloud = function(pattern, block, defaults, warn)
        zone(pattern, block, defaults, "poison", warn)
        return "zone"
    end,
    spike_trap = function(pattern, block, defaults, warn)
        zone(pattern, block, defaults, nil, warn)
        return "zone"
    end,
    fire_wave = function(pattern, block, defaults)
        pattern.damage = damage(pattern, block, defaults.default_beam_damage)
        pattern.ground_wave = {distance = block.width or pattern.range or block.radius,
            height = block.height, speed = block.speed, knockback = block.knockback, status = "burn"}
        extend_warning(pattern, block)
        return "ground_wave"
    end,
}

function M.validate(pattern, name)
    local kind = pattern.type
    local block = pattern[kind]
    if kind ~= "special" and kind ~= "hazard" then return true end
    if block ~= nil and type(block) ~= "table" then
        return false, ("pattern '%s' %s must be a table"):format(name, kind)
    end
    block = block or {}
    if kind == "special" and type(block.callback) == "function" then return true end
    if kind == "hazard" and block.type == nil then return true end
    local handlers = kind == "special" and SPECIAL or HAZARD
    if handlers[block.type] then
        if block.type == "clone" and pattern.summon ~= nil and type(pattern.summon) ~= "table" then
            return false, ("pattern '%s' summon must be a table"):format(name)
        end
        for _, key in ipairs({"radius", "width", "height", "delay", "telegraph_duration", "damage",
            "attack_damage", "damage_per_second", "knockback", "attack_range", "count", "projectile_count",
            "speed", "tick", "lifetime", "active_duration"}) do
            local value = block[key]
            if value ~= nil and (type(value) ~= "number" or not (value >= 0 and value < math.huge)
                or (key == "speed" and value == 0)) then
                return false, ("pattern '%s' %s.%s must be a finite nonnegative number, with speed above zero")
                    :format(name, kind, key)
            end
        end
        return true
    end
    local names = {}
    for id in pairs(handlers) do names[#names + 1] = id end
    table.sort(names)
    return false, ("pattern '%s' has unknown %s.type '%s'; valid names: %s")
        :format(name, kind, tostring(block.type), table.concat(names, ", "))
end

-- Mutates only the resolver's independent copy. Aliases and callbacks keep
-- their original route, and a nameless hazard keeps its one-shot area hit.
function M.translate(pattern, defaults, warn)
    defaults = defaults or {}
    local kind = pattern.type
    local block = pattern[kind]
    if kind ~= "special" and kind ~= "hazard" or not block then return pattern end
    if kind == "special" and type(block.callback) == "function" then return pattern end
    local translate = (kind == "special" and SPECIAL or HAZARD)[block.type]
    if translate then
        pattern._attack_name = pattern._attack_name or kind
        pattern.telegraph_time = block.telegraph_duration or pattern.telegraph_time or defaults.telegraph_time or 0.5
        pattern.type = translate(pattern, block, defaults, warn)
        pattern[kind] = nil
        pattern._legacy_cast = true
    end
    return pattern
end

return M
