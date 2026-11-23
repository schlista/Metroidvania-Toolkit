-- A pulse is permission for already-baked hazards to pass their arena gate.
-- The caller owns the clock; the registry only tracks live permissions.
local M = {}
local arenas = {}
local generation = 0

local function as_set(values)
    if not values then return nil end
    local set = {}
    for _, value in ipairs(values) do set[value] = true end
    return set
end

function M.start(arena_id, hazard_ids, warn_time, filters)
    if not arena_id or arena_id == "" then return nil end
    filters = filters or {}
    generation = generation + 1
    local token = {arena_id = arena_id}
    arenas[arena_id] = arenas[arena_id] or {}
    arenas[arena_id][token] = {
        ids = hazard_ids and #hazard_ids > 0 and as_set(hazard_ids) or nil,
        types = as_set(filters.hazard_types),
        pulse_only = filters.pulse_only == true,
        warn_time = warn_time or 0,
        elapsed = filters.elapsed,
        order = generation,
    }
    return token
end

function M.is_running(token)
    local pulses = token and arenas[token.arena_id]
    return pulses ~= nil and pulses[token] ~= nil
end

function M.stop(token)
    if not M.is_running(token) then return end
    local pulses = arenas[token.arena_id]
    pulses[token] = nil
    if not next(pulses) then arenas[token.arena_id] = nil end
    generation = generation + 1
end

-- When a hazard first notices several pulses, use the first that matches it.
-- The hazard owns its running warning once it opens the gate.
function M.warn_time(arena_id, hazard_id, hazard_type, pulse_only)
    local pulses = arenas[arena_id]
    if not pulses then return nil end
    local first
    for _, pulse in pairs(pulses) do
        if (not pulse.ids or pulse.ids[hazard_id])
            and (not pulse.types or pulse.types[hazard_type])
            and (not pulse.pulse_only or pulse_only)
            and (not first or pulse.order < first.order) then
            first = pulse
        end
    end
    if first then return first.warn_time, first.elapsed and first.elapsed() end
end

function M.is_active(arena_id, hazard_id, hazard_type, pulse_only)
    return M.warn_time(arena_id, hazard_id, hazard_type, pulse_only) ~= nil
end

function M.generation()
    return generation
end

function M.clear(arena_id)
    if not arenas[arena_id] then return end
    arenas[arena_id] = nil
    generation = generation + 1
end

function M.clear_all()
    if not next(arenas) then return end
    arenas = {}
    generation = generation + 1
end

return M
