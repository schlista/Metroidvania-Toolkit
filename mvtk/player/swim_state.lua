-- mvtk/player/swim_state.lua
-- Swimming state and physics for underwater gameplay
-- Handles different movement mechanics when in water

local M = {}

-- Attempt to load swim settings from developer config
local Util = require "mvtk.core.util"
local Timers = require "mvtk.player.timers"
local AirDash = require "mvtk.player.air_dash"
local SwimConfig = Util.require_config("developer.config.swim_settings")
local Debug = Util.require_config("developer.config.debug_config")
local swim_log = Util.make_debug_log("[SWIM]", function()
    return Debug.global.enable or (Debug.gameplay and Debug.gameplay.swim)
end)

-- Swimming physics constants (configurable via developer/config/swim_settings.lua)
local DEFAULTS = {
    swim_speed = SwimConfig.swim_speed or 200,
    swim_acceleration = SwimConfig.swim_acceleration or 800,
    swim_friction = SwimConfig.swim_friction or 0.85,
    swim_dash_speed = SwimConfig.swim_dash_speed or 400,
    swim_dash_duration = SwimConfig.swim_dash_duration or 0.3,
    bubble_interval = SwimConfig.bubble_interval or 0.5,
    oxygen_max = SwimConfig.oxygen_max or 10.0,
    oxygen_drain_rate = SwimConfig.oxygen_drain_rate or 1.0,
    oxygen_refill_rate = SwimConfig.oxygen_refill_rate or 2.0,
    surface_splash_threshold = SwimConfig.surface_splash_threshold or 50,
    swim_speed_mult = 1.0,
    buoyancy_speed = 0,
    no_swim_sink_speed = nil,
}

local SWIM_SPEED = DEFAULTS.swim_speed
local SWIM_ACCELERATION = DEFAULTS.swim_acceleration
local SWIM_FRICTION = DEFAULTS.swim_friction
local SWIM_DASH_SPEED = DEFAULTS.swim_dash_speed
local SWIM_DASH_DURATION = DEFAULTS.swim_dash_duration
local BUBBLE_INTERVAL = DEFAULTS.bubble_interval
local OXYGEN_MAX = DEFAULTS.oxygen_max
local OXYGEN_DRAIN_RATE = DEFAULTS.oxygen_drain_rate
local OXYGEN_REFILL_RATE = DEFAULTS.oxygen_refill_rate
local SURFACE_SPLASH_THRESHOLD = DEFAULTS.surface_splash_threshold
local SWIM_SPEED_MULT = DEFAULTS.swim_speed_mult
local BUOYANCY_SPEED = DEFAULTS.buoyancy_speed
local NO_SWIM_SINK_SPEED = DEFAULTS.no_swim_sink_speed

-- State
local is_swimming = false
local is_underwater = false
local oxygen = OXYGEN_MAX
local bubble_timer = 0
local clocks = {}
local is_dashing = false
local water_surface_y = 0
local current_velocity = vmath.vector3(0, 0, 0)
local swim_direction = vmath.vector3(0, 0, 0)
local water_source = nil
local oxygen_hud_url, oxygen_overlay_url
local oxygen_hud_message, oxygen_overlay_message
local last_oxygen_percent
local air_pockets = {}
local vertical_sample
local dash_request
local eight_directions = { directions = "eight" }
-- Treat binary32 display deltas that add up to a reference edge as that
-- edge. Otherwise a press nanoseconds past it waits a whole extra step.
local GRID_EPSILON = 1e-7

-- A settings file saved before the dash had a button lacks its three keys;
-- it then gets the values the shipped file has.
local function dash_setting(key, shipped)
    local value = SwimConfig[key]
    if value == nil then return shipped end
    return value
end

local function start_dash_cooldown()
    local seconds = math.max(0, tonumber(dash_setting("swim_dash_cooldown", 0.5)) or 0)
    local steps = math.floor(seconds / Timers.REFERENCE_STEP + 0.5)
    Timers.start_window(clocks, "dash_cooldown", steps * Timers.REFERENCE_STEP)
end

--- A nil rate leaves this pocket; negative rates inherit the swim setting.
-- Overlaps use the fastest refill, rather than adding rates together.
function M.set_air_pocket(key, rate)
    if key == nil then return end
    air_pockets[key] = rate
end

function M.clear_air_pockets()
    air_pockets = {}
end

--- Initialize swimming state
function M.init()
    M.clear_air_pockets()
    last_oxygen_percent = nil
    M.reset_params()
    is_swimming = false
    is_underwater = false
    oxygen = OXYGEN_MAX
    bubble_timer = 0
    clocks = {}
    is_dashing = false
    dash_request = nil
    current_velocity = vmath.vector3(0, 0, 0)
    vertical_sample = nil
end

--- Check if player is currently swimming
-- @return True if swimming
function M.is_swimming()
    return is_swimming
end

--- Check if player is underwater (fully submerged)
-- @return True if underwater
function M.is_underwater()
    return is_underwater
end

--- Get current oxygen level (0-1)
-- @return Oxygen percentage
function M.get_oxygen()
    return oxygen / OXYGEN_MAX
end

--- Publish the oxygen ratio only when its displayed whole percentage changes.
-- Cache absolute HUD URLs and message hashes on first use in the runtime host.
function M.publish_oxygen_hud(percent)
    local rounded = math.floor((percent or 0) * 100 + 0.5)
    if rounded == last_oxygen_percent then return end
    if not oxygen_hud_url then
        oxygen_hud_url = msg.url("main:/mode_hud#mode_hud")
        oxygen_overlay_url = msg.url("main:/underwater_overlay#underwater_overlay")
        oxygen_hud_message = hash("hud_oxygen")
        oxygen_overlay_message = hash("oxygen")
    end
    pcall(msg.post, oxygen_hud_url, oxygen_hud_message, { oxygen = percent })
    pcall(msg.post, oxygen_overlay_url, oxygen_overlay_message, { value = rounded })
    last_oxygen_percent = rounded
end

--- Correct the water surface after entry.
-- The bare-trigger entry path has no surface information and falls back to the
-- player's entry Y. A cooperating water volume that reports the real surface a
-- frame later must be able to fix it, since the surface drives is_underwater,
-- oxygen drain and buoyancy.
-- @param surface_y World Y of the water surface
function M.set_surface_y(surface_y)
    local y = tonumber(surface_y)
    if not y then return end
    water_surface_y = y
    vertical_sample = nil
end

--- Enter water
-- @param surface_y Y position of water surface
-- @param player_y Current player Y position
function M.enter_water(surface_y, player_y, opts)
    opts = opts or {}
    if not is_swimming then
        is_swimming = true
        vertical_sample = nil
        water_surface_y = surface_y
        water_source = opts.source
        swim_log(string.format("Entered water source=%s surface_y=%.1f", tostring(water_source), surface_y))

        -- Check if fully submerged
        if player_y < surface_y - 20 then  -- Below surface threshold
            is_underwater = true
            swim_log("Player is underwater")
        end

        if opts.oxygen_enabled == false then M.publish_oxygen_hud(M.get_oxygen()) end
        return "enter_water"  -- Event for splash effect
    end
    return nil
end

--- Exit water
-- @param exit_velocity Velocity when exiting (for splash)
-- @return Event name if should trigger splash
function M.exit_water(exit_velocity)
    last_oxygen_percent = nil
    if is_swimming then
        is_swimming = false
        vertical_sample = nil
        is_underwater = false
        oxygen = OXYGEN_MAX  -- Refill oxygen instantly on exit
        Timers.clear_window(clocks, "drown")
        M.stop_dash()
        clocks.dash_phase = nil

        swim_log(string.format("Exited water source=%s", tostring(water_source)))
        water_source = nil

        -- Check if exit was fast enough for splash
        if exit_velocity and vmath.length(exit_velocity) > SURFACE_SPLASH_THRESHOLD then
            return "exit_water_splash"
        else
            return "exit_water"
        end
    end
    return nil
end

local function axis_step(speed, target, acceleration, damp, buoyancy, resistance, dt)
    local h = Timers.REFERENCE_STEP
    local steering = 1 - math.exp(-acceleration * h)
    local preserve = damp * resistance
    local fraction = 1 - (1 - steering) * preserve
    local push = steering * target * preserve + buoyancy * h * resistance
    if fraction == 0 then
        local drift = push / h
        return speed + drift * dt, speed * dt + drift * dt * (dt + h) / 2
    end
    local steady = push / fraction
    local blend, ratio = Timers.approach_fraction(fraction, dt)
    return speed + (steady - speed) * blend,
        Timers.approach_travel(speed, steady, fraction, dt, ratio)
end

local function move_swimmer(dt, player_y, input)
    if dt <= 0 then return 0, 0 end
    swim_direction.x, swim_direction.y, swim_direction.z = input.x, input.y, 0
    local mag = vmath.length(swim_direction)
    if mag > 1 then swim_direction = swim_direction / mag end
    local target_x = swim_direction.x * SWIM_SPEED * SWIM_SPEED_MULT
    local target_y = swim_direction.y * SWIM_SPEED * SWIM_SPEED_MULT
    local acceleration = SWIM_ACCELERATION / math.max(1, SWIM_SPEED)
    local drift_x, drift_y = math.abs(swim_direction.x) < 0.01, math.abs(swim_direction.y) < 0.01
    local h = Timers.REFERENCE_STEP
    if Timers.reference_frame(dt) and not vertical_sample then
        -- Preserve the ordering of intermediate vector writes at native rate.
        local rate = 1 - math.exp(-acceleration * dt)
        current_velocity.x = current_velocity.x + (target_x - current_velocity.x) * rate
        current_velocity.y = current_velocity.y + (target_y - current_velocity.y) * rate
        local damp = math.pow(SWIM_FRICTION, dt * 60)
        if drift_x then current_velocity.x = current_velocity.x * damp end
        if drift_y then current_velocity.y = current_velocity.y * damp end
        if drift_y and BUOYANCY_SPEED > 0 and player_y < water_surface_y - 4 then
            current_velocity.y = current_velocity.y + BUOYANCY_SPEED * dt
            current_velocity.y = math.min(current_velocity.y, BUOYANCY_SPEED)
        end
        if player_y >= water_surface_y - 10 and current_velocity.y < -50 then
            current_velocity.y = current_velocity.y * 0.5
        end
        return current_velocity.x * dt, current_velocity.y * dt
    end
    local damp_x, damp_y = drift_x and SWIM_FRICTION or 1, drift_y and SWIM_FRICTION or 1
    local vx, dx = axis_step(current_velocity.x, target_x, acceleration, damp_x, 0, 1, dt)
    current_velocity.x = vx
    local dy, remaining = 0, dt
    while remaining > 1e-12 do
        local sample = vertical_sample
        if not sample or sample.steering ~= swim_direction.y then
            local buoyancy = drift_y and player_y + dy < water_surface_y - 4 and BUOYANCY_SPEED or 0
            local next_vy = axis_step(current_velocity.y, target_y, acceleration, damp_y, buoyancy, 1, h)
            local cap = buoyancy > 0 and next_vy > buoyancy and buoyancy or nil
            local resist = player_y + dy >= water_surface_y - 10 and next_vy < -50
            local left = sample and sample.left or h
            sample = {left = left, buoyancy = buoyancy, resist = resist, cap = cap, steering = swim_direction.y}
        end
        local piece = math.min(sample.left, remaining)
        local vy, travel
        if sample.cap then
            vy, travel = sample.cap, sample.cap * piece
        else
            vy, travel = axis_step(current_velocity.y, target_y, acceleration, damp_y,
                sample.buoyancy, sample.resist and 0.5 or 1, piece)
        end
        current_velocity.y = vy
        dy, remaining = dy + travel, remaining - piece
        sample.left = sample.left - piece
        vertical_sample = sample.left > 1e-12 and sample or nil
    end
    return dx, dy
end

local function dash_grid(dt)
    local h = Timers.REFERENCE_STEP
    local phase = clocks.dash_phase or 0
    local elapsed = phase + Timers.combat_delta(dt)
    local next_phase = elapsed % h
    if elapsed >= h and next_phase < GRID_EPSILON then
        elapsed, next_phase = elapsed - next_phase, 0
    elseif h - next_phase < GRID_EPSILON then
        elapsed, next_phase = elapsed + h - next_phase, 0
    end
    return phase, elapsed - phase, next_phase
end

local function dash_opening(phase, elapsed)
    local wait = phase > 0 and Timers.REFERENCE_STEP - phase or 0
    if dash_request and wait <= elapsed + 1e-12 then return math.min(wait, elapsed) end
end

function M.dash_press_offset(dt)
    if dash_request and dt > 0 then return dash_opening(dash_grid(dt)) end
end

local function tick_dash_cooldown(dt)
    if dt > 0 and Timers.is_active(clocks, "dash_cooldown") then
        Timers.tick_deadline(clocks, "dash_cooldown", dt)
    end
end

-- Consume an accepted press at the next 60 Hz opening. Draw the swim travel
-- before that edge and split the burst's last draw at its own deadline.
local function move_with_dash(dt, move_dt, player_y, input)
    local phase, elapsed, next_phase = dash_grid(dt)
    clocks.dash_phase = next_phase

    local dx, dy, sound = 0, 0
    local wait = dash_opening(phase, elapsed)
    local holding = Timers.has_window(clocks, "dash")
    local draw_scale = elapsed > 0 and dt / elapsed or 0
    if wait then
        if M.can_dash() then
            dx, dy = move_swimmer(wait * draw_scale, player_y, input)
            holding = M.dash(dash_request)
            local sound_id = dash_setting("swim_dash_sound", "air_dash")
            if sound_id ~= "" then sound = sound_id end
        end
        dash_request = nil
    end

    local swim_dt = move_dt
    if holding then
        local tail = elapsed - (wait or 0)
        local dash_dt = Timers.consume_pulse(clocks, "dash", tail, tail)
        -- End an upward burst at the waterline. Normal swimming and the
        -- existing exit grace still govern motion at the surface.
        local to_surface = current_velocity.y > 0 and math.max(0, (water_surface_y - player_y - dy) / current_velocity.y)
        local crossed = to_surface and to_surface <= dash_dt
        if crossed then dash_dt = to_surface end
        dx, dy = dx + current_velocity.x * dash_dt, dy + current_velocity.y * dash_dt
        local after = tail - dash_dt
        move_dt, swim_dt = dt, after * draw_scale
        is_dashing = Timers.is_active(clocks, "dash")
        if crossed then
            Timers.clear_window(clocks, "dash")
            is_dashing = false
            M.reset_velocity()
            start_dash_cooldown()
        elseif not Timers.has_window(clocks, "dash") then
            start_dash_cooldown()
        end
        tick_dash_cooldown(after)
    else
        tick_dash_cooldown(elapsed)
    end

    local swim_dx, swim_dy = move_swimmer(swim_dt, player_y + dy, input)
    return dx + swim_dx - current_velocity.x * move_dt,
        dy + swim_dy - current_velocity.y * move_dt, sound
end

--- Update swimming state
-- @param dt Delta time
-- @param player_pos Current player position
-- @param input Input direction vector
-- @param oxygen_enabled Whether oxygen mechanic is enabled
-- @param wading Use immersion and oxygen without swim propulsion
-- @return Updated velocity vector
function M.update(dt, player_pos, input, oxygen_enabled, wading)
    if not is_swimming then
        return current_velocity
    end

    -- Check if underwater based on position
    is_underwater = player_pos.y < water_surface_y - 20
    local move_dt, event, event_elapsed = dt

    -- Oxygen management
    if oxygen_enabled then
        local pocket_rate
        for _, rate in pairs(air_pockets) do
            if rate < 0 then rate = OXYGEN_REFILL_RATE end
            pocket_rate = math.max(pocket_rate or 0, rate)
        end
        if pocket_rate ~= nil then
            Timers.clear_window(clocks, "drown")
            oxygen = math.min(OXYGEN_MAX, oxygen + pocket_rate * dt)
        elseif is_underwater then
            if oxygen > 0 and OXYGEN_DRAIN_RATE > 0 and not Timers.has_window(clocks, "drown") then
                Timers.start_window(clocks, "drown", oxygen / OXYGEN_DRAIN_RATE)
            end
            local drowning = oxygen <= 0
            if Timers.has_window(clocks, "drown") then
                local before = Timers.window_remaining(clocks, "drown")
                local expired, paid = Timers.tick_deadline(clocks, "drown", dt)
                drowning = expired
                if expired then
                    event_elapsed = dt - paid
                elseif Timers.reference_frame(dt) then
                    -- Retain the saved arithmetic on the last breathing draw.
                    move_dt = math.max(0, math.min(dt, before - Timers.REFERENCE_STEP))
                    if dt - move_dt <= 1e-7 then move_dt = dt end
                    if move_dt <= 1e-12 then move_dt = 0 end
                end
            end
            oxygen = drowning and 0 or math.max(1e-12, oxygen - OXYGEN_DRAIN_RATE * dt)

            if not Timers.is_active(clocks, "bubble") then
                Timers.start_window(clocks, "bubble", math.max(Timers.REFERENCE_STEP, BUBBLE_INTERVAL))
            end
            local bubble, before = Timers.tick_deadline(clocks, "bubble", dt)
            if bubble then
                bubble_timer = 0
                local excess = Timers.reference_frame(dt) and 0 or dt - before
                Timers.start_window(clocks, "bubble", math.max(Timers.REFERENCE_STEP, BUBBLE_INTERVAL), false, excess)
            else
                bubble_timer = bubble_timer + dt
            end

            if drowning then
                event = "drowning"
            end
        else
            -- At surface - refill oxygen
            Timers.clear_window(clocks, "drown")
            oxygen = math.min(OXYGEN_MAX, oxygen + OXYGEN_REFILL_RATE * dt)
        end
    end

    if wading then
        M.tick_dash_cooldown(dt)
        return nil, event, nil, nil, event_elapsed
    end
    if dt <= 0 then
        return current_velocity, event, 0, 0, event_elapsed
    end
    local dx, dy, sound = move_with_dash(dt, move_dt, player_pos.y, input)
    return current_velocity, event, dx, dy, event_elapsed, sound
end

function M.drowning_ticks(owner, elapsed, interval)
    local left = (owner._drown_tick_t or 0) - elapsed
    if left > 1e-12 then
        owner._drown_tick_t = left
        return 0
    end
    local duration = Timers.reference_duration(interval)
    local count = 1 + math.floor((math.max(0, -left) + 1e-12) / duration)
    owner._drown_tick_t = left + count * duration
    return count
end

--- Take over the rules of another overlapping pool without refilling oxygen.
function M.use_source(source, surface_y, params)
    local remaining = oxygen
    M.reset_params()
    M.set_params(params)
    oxygen = math.min(remaining, OXYGEN_MAX)
    M.set_surface_y(surface_y)
    water_source = source
end

--- Trigger underwater dash
-- @param direction Direction vector
-- @return True if dash was triggered
function M.dash(direction)
    if not M.can_dash() then return false end

    local dash_dir = vmath.normalize(direction)
    current_velocity = dash_dir * SWIM_DASH_SPEED
    is_dashing = true
    Timers.start_window(clocks, "dash", math.max(Timers.REFERENCE_STEP, SWIM_DASH_DURATION))
    vertical_sample = nil

    swim_log("Underwater dash")
    return true
end

--- Check if can perform underwater dash
-- @return True if can dash
function M.can_dash()
    return is_swimming and dash_setting("swim_dash_enabled", true) == true
        and not Timers.has_window(clocks, "dash") and not Timers.is_active(clocks, "dash_cooldown")
end

function M.request_dash(player, input)
    if not player._swim_gate_ok or player._water_exit_grace_t or player._room_arrival
        or dash_request or not M.can_dash() then return false end
    local x, y = AirDash.direction(input, player.facing, false, nil, eight_directions)
    dash_request = vmath.vector3(x, y, 0)
    return true
end

function M.discard_dash_press()
    dash_request = nil
end

function M.tick_dash_cooldown(dt)
    if dt > 0 and Timers.is_active(clocks, "dash_cooldown") then
        local _, elapsed, next_phase = dash_grid(dt)
        clocks.dash_phase = next_phase
        tick_dash_cooldown(elapsed)
    end
end

--- Get swimming stats for UI/debugging
-- @return Stats table
function M.get_stats()
    return {
        is_swimming = is_swimming,
        is_underwater = is_underwater,
        oxygen = oxygen,
        oxygen_percent = oxygen / OXYGEN_MAX,
        is_dashing = is_dashing,
        velocity = current_velocity,
        speed = vmath.length(current_velocity),
        swim_speed = SWIM_SPEED,
        swim_speed_mult = SWIM_SPEED_MULT,
        buoyancy_speed = BUOYANCY_SPEED,
        source = water_source,
    }
end

--- Set swimming physics parameters
-- @param params Table of parameters to override
function M.set_params(params)
    if type(params) ~= "table" then return end
    if params.swim_speed then SWIM_SPEED = params.swim_speed end
    if params.swim_acceleration then SWIM_ACCELERATION = params.swim_acceleration end
    if params.swim_friction then SWIM_FRICTION = params.swim_friction end
    if params.swim_dash_speed then SWIM_DASH_SPEED = params.swim_dash_speed end
    if params.swim_dash_duration then SWIM_DASH_DURATION = params.swim_dash_duration end
    if params.oxygen_max then
        OXYGEN_MAX = params.oxygen_max
        oxygen = OXYGEN_MAX
        Timers.clear_window(clocks, "drown")
    end
    if params.oxygen_drain_rate then
        if OXYGEN_DRAIN_RATE ~= params.oxygen_drain_rate then Timers.clear_window(clocks, "drown") end
        OXYGEN_DRAIN_RATE = params.oxygen_drain_rate
    end
    if params.oxygen_refill_rate then OXYGEN_REFILL_RATE = params.oxygen_refill_rate end
    if params.swim_speed_mult ~= nil then SWIM_SPEED_MULT = math.max(0, tonumber(params.swim_speed_mult) or 1.0) end
    -- Water-volume drag is authored as retention per second. Convert it to
    -- the internal 60 Hz reference value used by the dt-independent damping.
    if params.water_drag ~= nil then
        local retention = math.max(0, math.min(1, tonumber(params.water_drag) or 1.0))
        SWIM_FRICTION = math.pow(retention, 1 / 60)
    end
    if params.buoyancy_speed ~= nil then BUOYANCY_SPEED = math.max(0, tonumber(params.buoyancy_speed) or 0) end
    if params.no_swim_sink_speed ~= nil then NO_SWIM_SINK_SPEED = tonumber(params.no_swim_sink_speed) end
    vertical_sample = nil
end

--- Restore all authored developer/config/swim_settings.lua defaults.
function M.reset_params()
    Timers.clear_window(clocks, "drown")
    vertical_sample = nil
    SWIM_SPEED = DEFAULTS.swim_speed
    SWIM_ACCELERATION = DEFAULTS.swim_acceleration
    SWIM_FRICTION = DEFAULTS.swim_friction
    SWIM_DASH_SPEED = DEFAULTS.swim_dash_speed
    SWIM_DASH_DURATION = DEFAULTS.swim_dash_duration
    BUBBLE_INTERVAL = DEFAULTS.bubble_interval
    OXYGEN_MAX = DEFAULTS.oxygen_max
    OXYGEN_DRAIN_RATE = DEFAULTS.oxygen_drain_rate
    OXYGEN_REFILL_RATE = DEFAULTS.oxygen_refill_rate
    SURFACE_SPLASH_THRESHOLD = DEFAULTS.surface_splash_threshold
    SWIM_SPEED_MULT = DEFAULTS.swim_speed_mult
    BUOYANCY_SPEED = DEFAULTS.buoyancy_speed
    NO_SWIM_SINK_SPEED = DEFAULTS.no_swim_sink_speed
    oxygen = math.min(oxygen, OXYGEN_MAX)
end

--- Force set oxygen level
-- @param amount Oxygen amount (0 to OXYGEN_MAX)
function M.set_oxygen(amount)
    oxygen = math.max(0, math.min(OXYGEN_MAX, amount))
    Timers.clear_window(clocks, "drown")
end

--- Reset velocity (useful for state transitions)
function M.reset_velocity()
    current_velocity = vmath.vector3(0, 0, 0)
    vertical_sample = nil
end

function M.stop_propulsion()
    if current_velocity.x ~= 0 or current_velocity.y ~= 0 then M.reset_velocity() end
    vertical_sample = nil
    if Timers.has_window(clocks, "dash") then
        Timers.clear_window(clocks, "dash")
        start_dash_cooldown()
    end
    M.discard_dash_press()
    is_dashing = false
end

function M.stop_dash()
    M.discard_dash_press()
    if Timers.has_window(clocks, "dash") then M.stop_propulsion() end
end

function M.reset_dash()
    M.stop_dash()
    Timers.clear_window(clocks, "dash_cooldown")
    clocks.dash_phase = nil
end

--- Check if should generate bubbles this frame
-- @return True if should spawn bubble particle
function M.should_spawn_bubble()
    return is_underwater and bubble_timer == 0
end

return M
