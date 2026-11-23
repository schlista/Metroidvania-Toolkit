local Path = require "mvtk.world.kinematic_path"
local Timers = require "mvtk.player.timers"

local M = {}
local STEP = Timers.REFERENCE_STEP
local EPSILON = 1e-12

function M.reset(owner)
    owner._leg_left = nil
    owner._leg_scale = nil
    owner.waiting = false
end

function M.clear_wait(owner)
    owner.waiting = false
end

local function native_engine_step(scale)
    return Timers.binary32(Timers.engine_reference_step() * scale)
end

local function retime_wait(clock, scale)
    if clock.scale == scale then return end
    local elapsed = clock.elapsed / clock.scale
    local ticks = math.floor((elapsed + EPSILON) / STEP)
    local _, remaining = Timers.native_steps(clock.seconds, native_engine_step(clock.scale), ticks)
    local part = math.max(0, elapsed - ticks * STEP) * scale
    clock.seconds, clock.elapsed, clock.scale = remaining, part, scale
    clock.left = Timers.native_steps(remaining, native_engine_step(scale)) * STEP * scale - part
end

function M.age_wait(owner, dt, scale)
    local waits = owner._waits
    if not waits or dt <= 0 then return end
    for i = #waits, 1, -1 do
        local clock = waits[i]
        if scale then retime_wait(clock, scale) end
        clock.elapsed = clock.elapsed + dt
        clock.left = clock.left - dt
        if clock.left <= EPSILON then
            -- A switch or reset could clear the flag while this old timer
            -- remained armed. Any outstanding expiry still clears it.
            table.remove(waits, i)
            M.clear_wait(owner)
        end
    end
    if #waits == 0 then owner._waits = nil end
end

-- A native timer expires before the script update. The last interval of
-- the wait therefore already belongs to the next leg's movement.
function M.wait(owner, seconds, scale)
    if not seconds or seconds <= 0 then return end
    scale = scale or 1
    local waits = owner._waits or {}
    waits[#waits+1] = { seconds=seconds, scale=scale, elapsed=0,
        left=Timers.native_steps(seconds, native_engine_step(scale)) * STEP * scale }
    owner._waits = waits
    owner.waiting = true
end

local function motion_hold(owner, step)
    if not owner.waiting then return 0 end
    local earliest = math.huge
    for _, clock in ipairs(owner._waits or {}) do earliest = math.min(earliest, clock.left) end
    return math.max(0, earliest - step)
end

function M.step(owner, dt, duration, mode, wait, scale)
    if mode == "wrap_mod" or mode == "wrap_sub" or mode == "once_hold" then
        owner.t, owner.dir = Path.advance(owner.t, owner.dir, dt, duration, mode)
        -- Repeated binary64 addition can land a few ulps below an authored
        -- seam whose draw is on the exact reference grid. Keep raw engine
        -- 60 Hz arithmetic and reserve this repair for the rounding residue.
        if mode ~= "once_hold" and owner.platform_type ~= "circular" and not owner.path_loop
            and dt > 0 and math.abs(dt-Timers.engine_reference_step()) > EPSILON
            and duration - owner.t <= EPSILON * duration then
            owner.t = 0
        end
        return true, 0, false
    end

    scale = scale or 1
    dt = Timers.world_delta(dt, scale)
    local step = STEP * scale
    if dt > 0 and owner._waits then
        for _, clock in ipairs(owner._waits) do retime_wait(clock, scale) end
    end
    local moved, turns = false, 0
    while dt > EPSILON do
        local hold = motion_hold(owner, step)
        if hold > EPSILON then
            local spent = math.min(dt, hold)
            M.age_wait(owner, spent)
            dt = dt - spent
        else
            local to_end = owner.dir > 0 and duration - owner.t or owner.t
            local left = owner._leg_scale == scale and owner._leg_left
                or math.max(step, Timers.reference_duration(to_end, scale))
            local spent = math.min(dt, left)
            local arrive = left <= dt + EPSILON
            M.age_wait(owner, spent)
            moved = true
            if not arrive then
                owner.t = math.max(0, math.min(duration, owner.t + owner.dir * spent))
                owner._leg_left = left - spent
                owner._leg_scale = scale
                break
            end

            owner._leg_left = nil
            local outward = owner.dir > 0
            owner.t = outward and duration or 0
            if mode == "once_stop" then return true, turns, true end
            owner.dir = -owner.dir
            if not outward and mode == "there_and_back" then return true, turns, true end
            turns = turns + 1
            M.wait(owner, wait, scale)
            dt = dt - spent
        end
    end
    return moved, turns, false
end

return M
