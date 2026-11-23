-- mvtk/player/timers.lua
-- Tiny helper for the per-frame countdown timers scattered across
-- `player_state.lua` (slide/dash/coyote/jump-buffer/etc.).
--
-- Ordinary countdowns in player_state follow the same pattern:
--   if (self._field or 0) > 0 then
--     self._field = math.max(0, self._field - dt)
--   end
--
-- This module exposes that pattern as `tick(self, field, dt)` plus a
-- `tick_all(self, fields, dt)` convenience for the common case where a
-- block of timers all decrement together. The behaviour is identical to
-- the inline expressions: a `nil` field stays nil, a value <= 0 stays
-- pinned at 0 / its current value, and a positive value decrements with a
-- 0 floor.

local Pause = require "mvtk.core.pause"
local M = { REFERENCE_STEP = 1 / 60 }
-- Defold passes the binary32 representation of 1/60 to a 60 Hz update.
-- Use it only to count the saved updates, then place them on the reference grid.
local ENGINE_REFERENCE_STEP = 0.016666667535901070
local EDGE_EPSILON = 1e-12

function M.engine_reference_step()
    return ENGINE_REFERENCE_STEP
end

local function reference_count(seconds)
    return math.ceil(seconds / ENGINE_REFERENCE_STEP - 1e-9)
end

function M.reference_duration(seconds, scale)
    if scale and scale > 0 and scale ~= 1 then
        local count = math.ceil(seconds / M.binary32(ENGINE_REFERENCE_STEP * scale) - 1e-9)
        return math.max(0, count) * M.REFERENCE_STEP * scale
    end
    return math.max(0, reference_count(seconds)) * M.REFERENCE_STEP
end

-- Timing readers replay the saved arithmetic at a steady reference rate.
-- Other rates use elapsed time and deadlines counted from the engine delta.
function M.combat_scale(dt)
    local scale = (Pause.proxy_frame_scale and Pause.proxy_frame_scale(dt))
        or (Pause.dt_scale and Pause.dt_scale()) or 1
    return scale > 0 and M.binary32(scale) or 1
end

function M.combat_engine_step(scale)
    return scale == 1 and ENGINE_REFERENCE_STEP or M.binary32(ENGINE_REFERENCE_STEP * scale)
end

function M.combat_reference_frame(dt, scale)
    scale = scale or M.combat_scale(dt)
    return dt == M.REFERENCE_STEP * scale or dt == M.combat_engine_step(scale)
end

function M.combat_delta(dt, scale)
    scale = scale or M.combat_scale(dt)
    return dt == M.combat_engine_step(scale) and M.REFERENCE_STEP * scale or dt
end

-- Repeating effects can spend the exact old per-step debit. Advancing one
-- step at a time preserves the remainder between successive pulses.
function M.combat_steps(owner, field, dt)
    if dt <= 0 then return 0, 0 end
    local scale = M.combat_scale(dt)
    local at_reference = M.combat_reference_frame(dt, scale)
    local raw = at_reference and M.REFERENCE_STEP or dt / scale
    local age = (owner[field] or 0) + raw
    local steps = math.floor((age + EDGE_EPSILON) / M.REFERENCE_STEP)
    owner[field] = age - steps * M.REFERENCE_STEP
    return steps, at_reference and dt or M.combat_engine_step(scale)
end

function M.start_combat_window(owner, field, seconds, elapsed, epsilon)
    M.start_window(owner, field, seconds, false, elapsed)
    local window = owner._movement_windows and owner._movement_windows[field]
    if window then
        window.combat_trace = not elapsed or elapsed == 0
        window.combat_epsilon = epsilon or 0
        window.combat_seconds = seconds
        window.combat_scale = 1
    end
end

local function inclusive_duration(seconds, scale)
    if seconds < 0 then return 0 end
    return (math.floor(seconds / M.combat_engine_step(scale)) + 1) * M.REFERENCE_STEP * scale
end

-- A comparison of elapsed <= seconds closes at the next reference sample.
-- Keep the authored boundary for later changes in proxy speed.
function M.start_inclusive_combat_window(owner, field, seconds)
    M.start_combat_window(owner, field, math.max(seconds, M.REFERENCE_STEP))
    local window = owner._movement_windows[field]
    window.combat_trace = false
    window.combat_seconds = seconds
    window.combat_inclusive = true
    window.length = inclusive_duration(seconds, 1)
end

function M.reference_frame(dt)
    return math.abs(dt - M.REFERENCE_STEP) <= 1e-9
end

-- A native timer rounds both its argument and each subtraction to binary32.
-- Lua numbers can represent those rounded values exactly.
function M.binary32(value)
    if value == 0 or value == math.huge or value == -math.huge then return value end
    local _, exponent = math.frexp(value)
    local unit = math.ldexp(1, math.max(exponent - 24, -149))
    local units = value / unit
    local lower = math.floor(units)
    local fraction = units - lower
    if fraction > 0.5 or (fraction == 0.5 and lower % 2 ~= 0) then lower = lower + 1 end
    return lower * unit
end

function M.native_steps(seconds, engine_step, limit)
    local remaining = M.binary32(seconds)
    local dt = engine_step or ENGINE_REFERENCE_STEP
    limit = limit or math.huge
    local count = 0
    while remaining > 0 and count < limit do
        local next_value = M.binary32(remaining - dt)
        local debit = remaining - next_value
        if debit <= 0 then return limit, remaining end
        count = count + 1
        -- Within one binary32 exponent range the subtraction has a constant
        -- debit once the rounded value is even. Skip those identical steps.
        if next_value > 0 and M.binary32(next_value - dt) == next_value - debit then
            local _, exponent = math.frexp(next_value)
            local boundary = math.ldexp(1, exponent - 1)
            local same_spacing = math.min(limit - count, math.max(0, math.ceil((next_value - boundary) / debit) - 1))
            next_value = next_value - same_spacing * debit
            count = count + same_spacing
        end
        remaining = next_value
    end
    return count, remaining
end

-- Keep a display update of exactly the captured engine delta on the grid.
function M.world_delta(dt, scale)
    scale = scale or 1
    local engine_step = scale == 1 and ENGINE_REFERENCE_STEP or M.binary32(ENGINE_REFERENCE_STEP * scale)
    if math.abs(dt - engine_step) < EDGE_EPSILON then return M.REFERENCE_STEP * scale end
    return math.max(0, dt)
end

function M.world_scale(dt, pause)
    local scale = pause.proxy_frame_scale and pause.proxy_frame_scale(dt)
    return scale and scale > 0 and M.binary32(scale) or 1
end

function M.schedule_native(owner, seconds, callback)
    local clock = owner._world_clock
    if not clock then
        clock = { time = 0, pending = {} }
        owner._world_clock = clock
    end
    local entry = {
        due = (clock.dispatch_at or clock.time) + M.REFERENCE_STEP,
        remaining = M.binary32(seconds),
        callback = callback,
        added_frame = clock.frame or 0,
    }
    clock.pending[#clock.pending + 1] = entry
    return entry
end

function M.cancel_native(owner, entry)
    if not entry then return end
    local pending = owner._world_clock.pending
    for i, candidate in ipairs(pending) do
        if candidate == entry then table.remove(pending, i); return end
    end
end

-- A motion owner may already draw travel in the update that will spend
-- this timer's final step. Dispatch itself still waits for the closing edge.
function M.native_preview(owner, scale)
    local clock = owner._world_clock
    if not clock then return 0 end
    local engine_step = M.binary32(ENGINE_REFERENCE_STEP * scale)
    local lead = 0
    for _, entry in ipairs(clock.pending) do
        if entry.remaining <= engine_step then
            lead = math.max(lead, M.REFERENCE_STEP - (entry.due - clock.time))
        end
    end
    return lead * scale
end

-- Call before the script's other guards, just as the native timer world does.
-- A callback scheduling another delay uses its own deadline as the origin.
function M.tick_native(owner, dt, scale)
    local clock = owner._world_clock
    if not clock then return end
    scale = scale or 1
    local elapsed = M.world_delta(dt, scale) / scale
    local engine_step = M.binary32(ENGINE_REFERENCE_STEP * scale)
    clock.time = clock.time + elapsed
    clock.frame = (clock.frame or 0) + 1
    while true do
        local index, earliest, at
        for i, entry in ipairs(clock.pending) do
            local stopped_zero = elapsed == 0 and entry.remaining == 0 and entry.added_frame < clock.frame
            local due = stopped_zero and clock.time or entry.due
            if due <= clock.time + EDGE_EPSILON and (not earliest or due < at) then
                index, earliest, at = i, entry, due
            end
        end
        if not earliest then break end
        earliest.remaining = M.binary32(earliest.remaining - engine_step)
        if earliest.remaining <= 0 then
            table.remove(clock.pending, index)
            clock.dispatch_at = at
            earliest.callback(math.max(0, (clock.time - at) * scale), scale)
            clock.dispatch_at = nil
        else
            earliest.due = earliest.due + M.REFERENCE_STEP
        end
    end
end

-- Fraction of an approach applied over dt, and the same fraction divided by
-- its per-step value. Near zero the latter needs a cancellation-free limit.
function M.approach_fraction(p, dt)
    local steps = dt / M.REFERENCE_STEP
    if p == 0 or dt <= 0 then return 0, steps end
    if p == 1 then return 1, 1 end
    if p < 1e-8 and p > 0 then
        local decay_per_p = steps * (1 + p / 2)
        local decay = p * decay_per_p
        if decay < 1e-8 then
            local ratio = decay_per_p * (1 - decay / 2)
            return p * ratio, ratio
        end
        local fraction = 1 - math.exp(-decay)
        return fraction, fraction / p
    end
    local fraction = 1 - (1 - p) ^ steps
    return fraction, fraction / p
end

function M.approach_travel(speed, target, p, dt, fraction_per_step)
    if p == 0 then return speed * dt end
    if not fraction_per_step then
        local _, ratio = M.approach_fraction(p, dt)
        fraction_per_step = ratio
    end
    return target * dt + M.REFERENCE_STEP * (speed - target) * (1 - p) * fraction_per_step
end

function M.center_fraction(rate, dt)
    if M.reference_frame(dt) then return math.min(1, rate * dt) end
    local fraction = M.approach_fraction(math.min(1, rate * M.REFERENCE_STEP), dt)
    return fraction
end

-- A caller replacing a timer can retire the old clock even if the new
-- public value happens to be the same.
function M.discard_window(owner, field)
    local windows = owner._movement_windows
    if windows then windows[field] = nil end
end

-- When the effect reads after decrement, the expiry update is outside it.
-- An opening press or an effect that reads before decrement spends that update.
function M.start_window(owner, field, seconds, opens_after_decrement, elapsed)
    local windows = owner._movement_windows
    owner[field] = seconds
    if seconds <= 0 then
        if windows then windows[field] = nil end
        return
    end
    if not windows then
        windows = {}
        owner._movement_windows = windows
    end
    local count = reference_count(seconds)
    local exact_multiple = math.abs(seconds - count * M.REFERENCE_STEP) <= EDGE_EPSILON
    windows[field] = {
        length = math.max(0, count - (opens_after_decrement and 1 or 0)) * M.REFERENCE_STEP,
        elapsed = elapsed or 0,
        paid = 0,
        visible = seconds,
        -- Presentation still matches the exact-double reference replay.
        reference = exact_multiple and seconds - 1e-9 or seconds,
    }
end

local function get_window(owner, field)
    local windows = owner._movement_windows
    local window = windows and windows[field]
    if window and window.visible ~= owner[field] then
        -- Resets, contacts and other motion owners can still clear the public
        -- timer directly. Their writes also retire the associated clock.
        windows[field] = nil
        return nil
    end
    return window
end

function M.clear_window(owner, field)
    M.discard_window(owner, field)
    owner[field] = 0
end

-- Keep a running deadline when a request would leave less time. A repeated
-- full-duration request can renew the clock once it has spent time.
function M.extend_window(owner, field, seconds, elapsed)
    local window = get_window(owner, field)
    if seconds <= (owner[field] or 0) then return end
    if window and reference_count(seconds) * M.REFERENCE_STEP - (elapsed or 0) + EDGE_EPSILON
        < window.length - window.elapsed then return end
    M.start_window(owner, field, seconds, false, elapsed)
end

local function advance(owner, field, window, dt)
    window.elapsed = window.elapsed + dt
    local remaining = window.visible - dt
    if remaining <= 0 then remaining = EDGE_EPSILON end
    window.visible, owner[field] = remaining, remaining
end

local function finish(owner, field)
    owner._movement_windows[field] = nil
    owner[field] = 0
end

local function combat_trace(owner, field, window, dt, scale)
    if not window or not window.combat_trace then return false end
    if not M.combat_reference_frame(dt, scale) then
        if dt > 0 then window.combat_trace = false end
        return false
    end
    window.elapsed = window.elapsed + M.combat_delta(dt, scale)
    window.visible = math.max(0, window.visible - dt)
    owner[field] = window.visible
    if window.visible <= window.combat_epsilon then finish(owner, field) end
    return true
end

local function combat_scale_window(window, scale, dt)
    if dt <= 0 or not window.combat_seconds or window.combat_scale == scale then return end
    local remaining = window.combat_seconds - window.elapsed
    local length = window.combat_inclusive and inclusive_duration(remaining, scale)
        or M.reference_duration(remaining, scale)
    window.length = window.elapsed + length
    window.combat_scale = scale
end

-- Readers before the next count sample a press deadline at the nearer draw.
function M.tick_combat_window(owner, field, dt, scale)
    local window = get_window(owner, field)
    if not window then M.tick(owner, field, dt); return (owner[field] or 0) <= 0 end
    scale = scale or M.combat_scale(dt)
    combat_scale_window(window, scale, dt)
    if combat_trace(owner, field, window, dt, scale) then return (owner[field] or 0) <= 0 end
    if dt > M.REFERENCE_STEP * scale then
        M.tick_deadline(owner, field, dt)
    else
        M.tick_window(owner, field, M.combat_delta(dt, scale))
    end
    return (owner[field] or 0) <= 0
end

function M.tick_combat_deadline(owner, field, dt, scale)
    if dt <= 0 then return (owner[field] or 0) <= 0, 0 end
    local window = get_window(owner, field)
    if not window then return M.tick_deadline(owner, field, dt) end
    scale = scale or M.combat_scale(dt)
    combat_scale_window(window, scale, dt)
    if combat_trace(owner, field, window, dt, scale) then
        return (owner[field] or 0) <= 0, dt
    end
    return M.tick_deadline(owner, field, M.combat_delta(dt, scale))
end

function M.window_remaining(owner, field)
    local window = get_window(owner, field)
    return window and math.max(0, window.length - window.elapsed) or math.max(0, owner[field] or 0)
end

function M.has_window(owner, field)
    return get_window(owner, field) ~= nil
end

-- Dispatch on the first update containing the reference deadline. Return the
-- portion before it so a caller can split movement without rounding travel.
function M.tick_deadline(owner, field, dt)
    local window = get_window(owner, field)
    if not window then
        local before = math.max(0, owner[field] or 0)
        M.tick(owner, field, dt)
        return (owner[field] or 0) <= 0, math.min(before, dt)
    end
    local remaining = window.length - window.elapsed
    if remaining <= dt + EDGE_EPSILON then
        finish(owner, field)
        return true, math.min(dt, math.max(0, remaining))
    end
    advance(owner, field, window, dt)
    return false, dt
end

-- A speed hold spends only the travel in the current draw. Preserve the
-- saved order of its continuous reference replay, including the exit draw.
function M.step_held_speed(owner, field, dt)
    local window = get_window(owner, field)
    if not window then
        M.tick(owner, field, dt)
        local active = (owner[field] or 0) > 0
        return active, active and dt or 0
    end
    if dt <= 0 then return true, 0 end
    if window.held_reference ~= false and M.reference_frame(dt) then
        if window.visible > dt then
            advance(owner, field, window, dt)
            return true, dt
        end
        finish(owner, field)
        return false, 0
    end
    window.held_reference = false
    local expired, spent = M.tick_deadline(owner, field, dt)
    return not expired, spent
end

-- A recurring deadline preserves the phase across a late draw. The caller
-- can dispatch each crossed deadline or read the latest state once.
function M.periodic_deadlines(owner, field, interval, dt)
    if dt <= 0 then return 0 end
    if interval ~= interval or interval <= 0 then return 1 end
    if interval == math.huge then return 0 end
    local remaining = (owner[field] or interval) - dt
    local epsilon = math.min(EDGE_EPSILON, interval * EDGE_EPSILON)
    local count = remaining <= epsilon and 1 + math.floor((epsilon - remaining) / interval) or 0
    owner[field] = remaining + count * interval
    return count
end

-- World scripts in the boot proxy receive already scaled time from Defold.
function M.gameplay_delta(dt, pause)
    local proxy = pause.proxy_frame_scale and pause.proxy_frame_scale(dt)
    local scale = proxy or (pause.dt_scale and pause.dt_scale()) or 1
    if proxy and scale <= 0 then scale = 1 end
    local scaled_dt = proxy and dt or dt * scale
    return M.world_delta(scaled_dt, scale), scale, scaled_dt
end

-- A countdown an opening press reads after this update. Choose the
-- endpoint nearest the expiry so the next opening sees the new state.
function M.tick_window(owner, field, dt)
    local window = get_window(owner, field)
    if not window then return M.tick(owner, field, dt) end
    if dt <= 0 then return end
    if window.length - window.elapsed <= dt * 1.5 + EDGE_EPSILON then
        finish(owner, field)
    else
        advance(owner, field, window, dt)
    end
end

function M.tick_windows(owner, fields, dt)
    for _, field in ipairs(fields) do M.tick_window(owner, field, dt) end
end

-- A steering window changes the target at its exact deadline. The frame's
-- reported state uses the nearer opening, even when part of the frame
-- still uses the forced target.
function M.slice_window(owner, field, dt)
    local window = get_window(owner, field)
    if not window then
        local active = (owner[field] or 0) > 1e-9
        if active then M.tick(owner, field, dt) end
        return active, active and dt or 0
    end
    if dt <= 0 then return true, 0 end
    local remaining = window.length - window.elapsed
    local active = remaining > dt / 2 + EDGE_EPSILON
    local travel = remaining >= dt - EDGE_EPSILON and dt or math.max(0, remaining)
    if remaining <= dt + EDGE_EPSILON then
        finish(owner, field)
    else
        advance(owner, field, window, dt)
    end
    return active, travel
end

-- Returns whether this frame belongs to the window, the time that still
-- needs to be traveled at the held speed, and the elapsed time from expiry
-- at the opening of the first outside frame. False has no offset for timers
-- set directly by an older caller.
function M.step_window(owner, field, dt)
    local window = get_window(owner, field)
    if not window then
        M.tick(owner, field, dt)
        return (owner[field] or 0) > 0, dt
    end
    if dt <= 0 then return true, 0 end
    local remaining = window.length - window.elapsed
    local unpaid = window.length - window.paid
    if unpaid < EDGE_EPSILON then unpaid = 0 end
    if remaining <= dt / 2 + EDGE_EPSILON then
        finish(owner, field)
        if math.abs(remaining) < EDGE_EPSILON then remaining = 0 end
        return false, unpaid, -remaining
    end
    -- If this looks like the last frame, pay all remaining travel. A
    -- shorter next frame may still belong to the window, but only the unpaid
    -- portion can travel. A longer next frame can close an unpaid window.
    local travel = math.min(unpaid, dt)
    if remaining <= dt * 1.5 + EDGE_EPSILON then travel = unpaid end
    if math.abs(travel - dt) < EDGE_EPSILON then travel = dt end
    window.paid = window.paid + travel
    advance(owner, field, window, dt)
    return true, travel
end

function M.tick_drop_through(owner, dt)
    M.tick_window(owner, "_platform_drop_t", dt)
    if (owner._one_way_ground_bypass_t or 0) > 0 then
        if dt > ENGINE_REFERENCE_STEP then
            M.tick_deadline(owner, "_one_way_ground_bypass_t", dt)
        else
            M.step_window(owner, "_one_way_ground_bypass_t", dt)
        end
    end
end

function M.reference_remaining(owner, field)
    local window = get_window(owner, field)
    return window and math.max(0, window.reference - M.REFERENCE_STEP) or owner[field]
end

-- A steering pulse changes the target velocity at its exact endpoint. Its
-- public field expires on the nearest frame, and the remaining fraction can
-- still contribute to this or the next displacement interval.
function M.consume_pulse(owner, field, dt, frame_dt)
    local window = get_window(owner, field)
    if not window then
        if (owner[field] or 0) <= 0 then return 0 end
        M.tick(owner, field, frame_dt)
        return dt
    end
    local remaining = window.length - window.elapsed
    local time = remaining >= dt - EDGE_EPSILON and dt or math.max(0, remaining)
    if remaining <= dt + EDGE_EPSILON then
        finish(owner, field)
    else
        if window.visible > 0 then advance(owner, field, window, dt)
        else window.elapsed = window.elapsed + dt end
        if window.length - window.elapsed <= frame_dt / 2 + EDGE_EPSILON then
            window.visible, owner[field] = 0, 0
        end
    end
    return time
end

--- Decrement a single timer field on `self` by `dt`, clamping to 0.
-- @param self table The state table containing the timer field.
-- @param field string Field name on `self` (e.g. "_slide_cool").
-- @param dt number Frame delta in seconds.
function M.tick(self, field, dt)
    local v = self[field]
    if v and v > 0 then
        local nv = v - dt
        if nv < 0 then nv = 0 end
        self[field] = nv
    end
end

--- Decrement a block of timer fields on `self` by `dt`.
-- Equivalent to calling `M.tick(self, field, dt)` for each entry. Use this
-- when several timers all advance together at the start/end of a frame.
-- @param self table
-- @param fields string[] Array of field names.
-- @param dt number
function M.tick_all(self, fields, dt)
    if not fields then return end
    for i = 1, #fields do
        local field = fields[i]
        local v = self[field]
        if v and v > 0 then
            local nv = v - dt
            if nv < 0 then nv = 0 end
            self[field] = nv
        end
    end
end

--- Returns true when the named timer is currently active (> 0).
-- Treats nil / 0 / negative values as inactive.
function M.is_active(self, field)
    local v = self[field]
    return type(v) == "number" and v > 0
end

return M
