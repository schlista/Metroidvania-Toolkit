-- Boss-owned attack time and cleanup. Engine operations are injected by callers.
local Runtime = {}
local Instance = {}
Instance.__index = Instance
local Clock = require "mvtk.bosses.boss_clock"
local settle
local EPSILON = 1e-12

local function clock_for(boss)
    if not boss._attack_clock then
        boss._attack_clock = {time = 0, draw = 0, sequence = 0}
    end
    return boss._attack_clock
end

function Runtime.start(boss, pattern, opts)
    opts = opts or {}
    local background = opts.background == true
    local clock = clock_for(boss)
    local origin = opts.origin or boss._attack_due or clock.time
    local instance = setmetatable({
        pattern = pattern, elapsed = 0, background = background,
        persist = pattern.persist == true or (background and pattern.persist ~= false),
        parent = opts.parent, done = false, boss = boss,
        _timers = {}, _frames = {}, _owned = {}, _children = {},
        _delete = opts.delete, _exists = opts.exists, _cancel = opts.cancel,
        _origin = origin, _elapsed_draw = clock.draw,
        _first_frame = clock.dispatch_at and clock.draw + 1 or clock.draw,
        _first_timer = clock.dispatch_at and not (opts.parent or background) and clock.draw + 1 or clock.draw,
        _defer = opts.defer_timers == true, _hold = 0,
    }, Instance)
    boss._attacks = boss._attacks or {}
    table.insert(boss._attacks, instance)
    if clock.advancing then table.insert(clock.advancing, instance) end
    if instance.parent then table.insert(instance.parent._children, instance) end
    return instance
end

local function scheduled_time(instance, clock)
    return math.max(instance._origin, clock.dispatch_at or instance.boss._attack_due or clock.time)
end

-- Legacy frame work still reads display-frame age.
local function sample_elapsed(instance, clock)
    if instance._elapsed_draw == clock.draw then return end
    instance._elapsed_draw = clock.draw
    if not instance._defer then instance.elapsed = instance.elapsed + clock.draw_delta end
end

-- A cast already on the gameplay clock can spend a zero delay on its due
-- draw. A nested zero waits for another draw, so a recursive authored combo
-- cannot keep the dispatcher at the same time forever.
function Instance:after(seconds, fn)
    if self._cancelled then return end
    local clock = clock_for(self.boss)
    local delay = math.max(0, seconds)
    clock.sequence = clock.sequence + 1
    local origin = scheduled_time(self, clock)
    local first_draw = delay == 0 and (not clock.draw_end or clock.dispatch_at) and clock.draw + 1 or clock.draw
    table.insert(self._timers, {at = origin + delay, fn = fn, sequence = clock.sequence, first_draw = first_draw})
    self.done = false
end

function Instance:each_frame(fn, until_seconds, decision_seconds, timed)
    if self._cancelled then return end
    local clock = clock_for(self.boss)
    local at = scheduled_time(self, clock)
    table.insert(self._frames, {fn = fn,
        remaining = until_seconds and math.max(0, until_seconds),
        deadline = decision_seconds and at + decision_seconds,
        at = at, timed = timed})
    self.done = false
end

function Instance:each_motion(fn)
    self:each_frame(fn, nil, nil, "motion")
end

function Instance:time()
    return scheduled_time(self, clock_for(self.boss))
end

-- A factory object first updates on the next draw. Its first travel
-- segment also includes any game time after the scheduled launch this draw.
function Instance:launch_age()
    local clock = clock_for(self.boss)
    return math.max(0, (clock.draw_end or clock.time) - scheduled_time(self, clock))
end

function Instance:at_time(at, fn, ...)
    local clock = clock_for(self.boss)
    local record = self.boss.boss_data
    local previous, dispatch = record and record._boss_clock_at, clock.dispatch_at
    if record then record._boss_clock_at = at end
    clock.dispatch_at = at
    fn(...)
    clock.dispatch_at = dispatch
    if record then record._boss_clock_at = previous end
end

function Instance:motion_arrival(seconds, follow_up)
    local clock = clock_for(self.boss)
    local frame = clock.motion_frame
    local at = frame and math.min(clock.time, frame.at + seconds) or clock.time
    if follow_up then
        if frame and not frame.timed and clock.last_dispatch and at < clock.last_dispatch then at = clock.time end
        self:at_time(at, follow_up)
    end
    return false, at
end

function Instance:own(id)
    if id then table.insert(self._owned, id) end
    return id
end

-- Transfer an existing visual to a different attack without deleting it.
function Instance:disown(id)
    for i, owned in ipairs(self._owned) do
        if owned == id then
            table.remove(self._owned, i)
            return
        end
    end
end

function Instance:on_cancel(fn)
    self._cancel = fn
end

function Instance:child(pattern)
    local clock = clock_for(self.boss)
    return Runtime.start(self.boss, pattern, {parent = self, delete = self._delete, exists = self._exists,
        origin = clock.dispatch_at})
end

-- A separate instance for what outlives the attack that made it: a planted
-- mine, a raised shield, a buff, shots already in flight. It never keeps the
-- boss in its attack state, stays through knockdown and phase changes unless
-- the pattern sets persist = false, and ends with the boss.
function Instance:lasting(pattern)
    local clock = clock_for(self.boss)
    local lasting = Runtime.start(self.boss, pattern or self.pattern,
        {delete = self._delete, exists = self._exists, background = true, origin = clock.dispatch_at})
    lasting._defer = self._defer
    return lasting
end

function Instance:hold(seconds)
    local clock = clock_for(self.boss)
    local elapsed = scheduled_time(self, clock) - self._origin
    self._hold = math.max(self._hold, elapsed + math.max(0, seconds))
    self.done = false
end

function Instance:finish()
    settle(self)
end

local function cancel_instance(instance, reason)
    if instance._cancelled then return end
    instance._cancelled, instance.done = true, true
    instance._timers, instance._frames = {}, {}
    for _, child in ipairs(instance._children) do cancel_instance(child, reason) end
    for _, id in ipairs(instance._owned) do
        if instance._delete then instance._delete(id) end
    end
    instance._owned = {}
    if instance._cancel then instance._cancel(instance, reason) end
end

settle = function(instance)
    if instance._cancelled then return end
    local children_done = true
    for _, child in ipairs(instance._children) do
        if not child.done then children_done = false end
    end
    instance.done = #instance._timers == 0 and #instance._frames == 0
        and clock_for(instance.boss).time + EPSILON >= instance._origin + instance._hold and children_done
end

local function record_completion(instance, clock, frame, completion)
    if not instance.persist and not instance.background then
        clock.turn_end = math.max(clock.turn_end or 0, frame.deadline or completion or clock.time)
    end
end

-- Advance a move up to the work that is about to observe its transform.
-- A cursor on the frame pays each part of a display interval only once.
local function run_motion(boss, clock, at)
    local draw_time, advanced = clock.time, false
    clock.time = at
    for _, instance in ipairs(boss._attacks) do
        if not instance.done and not instance._cancelled and not instance._defer then
            local frames, index = instance._frames, 1
            while frames[index] and not instance._cancelled do
                local frame = frames[index]
                if frame.timed == "motion" and Clock.reached(at, frame.at)
                    and (not frame.progressed_at or at > frame.progressed_at + EPSILON) then
                    local dt = math.max(0, at - math.max(frame.at, frame.progressed_at or frame.at))
                    frame.progressed_at, clock.motion_frame = at, frame
                    local sequence = clock.sequence
                    local keep, completion = frame.fn(instance, dt, at, clock.draw_delta, frame.at)
                    clock.motion_frame, advanced = nil, true
                    if keep == false then
                        table.remove(frames, index)
                        record_completion(instance, clock, frame, completion)
                        index = index - 1
                    end
                    if clock.sequence ~= sequence then
                        -- Before visiting newly armed motion, give its
                        -- timers a chance to observe the earlier position.
                        clock.time = draw_time
                        return true
                    end
                end
                index = index + 1
            end
        end
    end
    clock.time = draw_time
    return advanced
end

local function dispatch_timer(owner, timer, index, clock)
    table.remove(owner._timers, index)
    sample_elapsed(owner, clock)
    owner:at_time(timer.at, timer.fn, owner)
    clock.last_dispatch = math.max(clock.last_dispatch or timer.at, timer.at)
    if not owner.persist and not owner.background then
        clock.turn_end = math.max(clock.turn_end or 0, timer.at)
    end
end

local function run_timers(boss, clock)
    while true do
        local owner, next_timer, index
        for _, instance in ipairs(boss._attacks) do
            if not instance.done and not instance._cancelled and not instance._defer
                and instance._first_timer <= clock.draw then
                for i, timer in ipairs(instance._timers) do
                    if timer.first_draw <= clock.draw and timer.at <= clock.time
                        and (not next_timer or timer.at < next_timer.at
                            or timer.at == next_timer.at and timer.sequence < next_timer.sequence) then
                        owner, next_timer, index = instance, timer, i
                    end
                end
            end
        end
        if not next_timer then return end
        -- An arrival can enqueue work before this timer. Select again
        -- after moving so the queue observes logical order.
        if not run_motion(boss, clock, next_timer.at) then
            dispatch_timer(owner, next_timer, index, clock)
        end
    end
end

function Runtime.begin_update(boss, previous, dt)
    local clock = clock_for(boss)
    clock.time, clock.draw = previous or clock.time, clock.draw + 1
    clock.draw_start = clock.time
    clock.draw_end = dt and previous + dt
    clock.draw_delta = dt or 0
end

function Runtime.begin_turn(boss)
    clock_for(boss).turn_end = nil
end

function Runtime.turn_end(boss)
    return clock_for(boss).turn_end or 0
end

function Runtime.advance(boss, now)
    local clock = clock_for(boss)
    clock.time = now
    if not boss._attacks then return end
    run_timers(boss, clock)
    for i = #boss._attacks, 1, -1 do
        local instance = boss._attacks[i]
        settle(instance)
    end
end

function Runtime.finish_update(boss, dt)
    if not boss._attacks then return end
    local clock = clock_for(boss)
    for _, instance in ipairs(boss._attacks) do
        if instance._defer and instance._first_frame <= clock.draw then
            local shift = clock.time - instance._origin
            instance._origin, instance.elapsed, instance._defer = clock.time, 0, false
            for _, timer in ipairs(instance._timers) do timer.at = timer.at + shift end
            -- A standalone tick observes a cast with no logical warning
            -- deadline at this draw's endpoint.
            if not clock.draw_end then
                for _, frame in ipairs(instance._frames) do
                    if frame.timed then
                        frame.at = frame.at + shift
                        if frame.deadline then frame.deadline = frame.deadline + shift end
                    end
                end
            end
            instance._elapsed_draw = clock.draw
        end
    end
    while run_motion(boss, clock, clock.time) do run_timers(boss, clock) end
    local advancing = {}
    for i, instance in ipairs(boss._attacks) do
        advancing[i] = instance
    end
    clock.advancing = advancing
    for _, instance in ipairs(advancing) do
        if not instance.done and not instance._cancelled then
            if instance._first_frame <= clock.draw then sample_elapsed(instance, clock) end
            local frames = instance._frames
            instance._frames = {}
            for _, frame in ipairs(frames) do
                if not instance._cancelled and frame.timed ~= "motion"
                    and (frame.timed and Clock.reached(clock.time, frame.at)
                    or not frame.timed and instance._first_frame <= clock.draw) then
                    local frame_dt = frame.remaining and math.min(dt, frame.remaining) or dt
                    if frame.timed then
                        frame_dt = math.max(0, clock.time - math.max(clock.draw_start, frame.at))
                    end
                    clock.motion_frame = frame
                    local result, completion = frame.fn(instance, frame_dt, clock.time, dt, frame.at)
                    clock.motion_frame = nil
                    local keep = result ~= false
                    if frame.remaining then frame.remaining = math.max(0, frame.remaining - frame_dt) end
                    if keep and (not frame.remaining or frame.remaining > 0) then
                        table.insert(instance._frames, frame)
                    else
                        record_completion(instance, clock, frame, completion)
                    end
                elseif not instance._cancelled then
                    table.insert(instance._frames, frame)
                end
            end
        end
    end
    clock.advancing = nil
    -- Children can finish later in the same update than their parent.
    for i = #boss._attacks, 1, -1 do settle(boss._attacks[i]) end
    clock.draw_end = nil
    Runtime.prune(boss)
end

function Runtime.prune(boss)
    local attacks = boss._attacks or {}
    -- Completed instances with cleanup remain owned until cancellation. This
    -- includes spawned actors that outlive their attack's pending callbacks.
    for i = #attacks, 1, -1 do
        local a = attacks[i]
        if a._exists then
            for j = #a._owned, 1, -1 do
                if not a._exists(a._owned[j]) then table.remove(a._owned, j) end
            end
        end
        if a.done and #a._owned == 0 and not a._cancel then table.remove(attacks, i) end
    end
end

function Runtime.update(boss, dt)
    if not boss._attacks then return end
    dt = math.max(0, dt)
    local previous = clock_for(boss).time
    Runtime.begin_update(boss, previous)
    clock_for(boss).draw_delta = dt
    Runtime.advance(boss, previous + dt)
    Runtime.finish_update(boss, dt)
end

function Runtime.cancel(boss, reason)
    local attacks = boss._attacks or {}
    for _, instance in ipairs(attacks) do
        -- A finished parent may already have left the list while a child's
        -- spawned actor is still alive. Keep cancellation rooted at that parent.
        local root = instance
        while root.parent do root = root.parent end
        if not (root.persist and (reason == "stagger" or reason == "phase")) then
            cancel_instance(root, reason)
        elseif instance.interruptible then
            cancel_instance(instance, reason)
        end
    end
    for i = #attacks, 1, -1 do
        if attacks[i]._cancelled then table.remove(attacks, i) end
    end
    if reason == "removed" or reason == "defeat" then boss._attack_clock = nil end
end

function Runtime.is_busy(boss)
    for _, instance in ipairs(boss._attacks or {}) do
        if not instance.done and not instance.persist and not instance.background then return true end
    end
    return false
end

-- Phase baselines and live buffs share one composition path. Defense bonuses
-- retain their authored flat meaning; damage/speed buffs multiply.
function Runtime.apply_multipliers(boss, phase)
    local data = boss.boss_data or boss
    local base = data._phase_multipliers
    if not base then
        base = {damage = data.damage_multiplier or boss.damage_multiplier or 1,
            speed = data.speed_multiplier or boss.speed_multiplier or 1, defense = data.defense or 0}
        data._phase_multipliers = base
    end
    if phase then
        base.damage = phase.damage_multiplier or base.damage
        base.speed = phase.speed_multiplier or base.speed
    end
    local damage, speed, defense = base.damage, base.speed, base.defense
    for _, buff in ipairs(data.buffs or {}) do
        damage, speed = damage * (buff.damage or 1), speed * (buff.speed or 1)
        defense = defense + (buff.defense or 0)
    end
    data.damage_multiplier, data.speed_multiplier, data.defense = damage, speed, defense
    boss.damage_multiplier, boss.speed_multiplier = damage, speed
end

return Runtime
