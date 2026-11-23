-- Estimates an ordinary ground jump in open space from runtime-scaled settings.
local JumpMath = require "mvtk.player.player_jump_math"
local M = {}

-- The game advances the player once per displayed frame. Sixty a second is the
-- usual rate, and the numbers shown match a real run at that rate.
local dt = 1 / 60
local max_steps = 10 / dt

local function jump(cfg, speed, release, fall_cap)
    if speed <= 0 then return nil end
    local apex = cfg.apex_hang_speed
    if apex <= 0 then apex = cfg.apex_threshold_vy or 0 end
    local vy, y, height, falling = speed, 0, 0, 0
    local release_time = JumpMath.shortest_jump_release_time(cfg.jump_min_hold_time, dt)
    local cut_pending = cfg.variable_jump_mode == "cut"
    for step = 1, max_steps do
        local gravity = cfg.gravity
        if vy < 0 then gravity = gravity * cfg.fall_gravity_mult end
        if apex > 0 and math.abs(vy) <= apex then gravity = gravity * cfg.apex_gravity_mult end
        if release and vy > 0 and (step - 1) * dt >= release_time then
            if cfg.variable_jump_mode ~= "cut" then
                gravity = gravity * cfg.jump_release_gravity_mult
            elseif cut_pending then
                vy = vy * cfg.jump_cut_speed_mult
                cut_pending = false
            end
        end
        vy = vy + gravity * dt
        if fall_cap then vy = math.max(vy, fall_cap) end
        local previous_y = y
        y = y + vy * dt
        height = math.max(height, y)
        falling = math.max(falling, -vy)
        if y <= 0 then
            local fraction = vy < 0 and previous_y / (-vy * dt) or 0
            return height, (step - 1 + fraction) * dt, falling
        end
    end
end

-- Physics fall cap is the signed cap from the project, before transient stats.
-- Returns nil if any of the three jumps fails to complete within ten seconds.
function M.measure(cfg, tile_height, physics_fall_cap)
    if type(tile_height) ~= "number" or not (tile_height > 0) or tile_height == math.huge then return nil end
    local cap = physics_fall_cap or cfg.max_fall_speed
    if cfg.max_fall_speed_px > 0 then
        cap = math.max(cap or -cfg.max_fall_speed_px, -cfg.max_fall_speed_px)
    end
    local speed = JumpMath.compute_jump_speed(cfg)
    local full, time, falling = jump(cfg, speed, false, cap)
    if not full then return nil end
    local short = jump(cfg, speed, true, cap)
    if not short then return nil end

    local run_time = time
    if cfg.run_speed > cfg.walk_speed and cfg.speed_jump_bonus > 0 then
        local _, boosted_time = jump(cfg, speed * math.sqrt(1 + cfg.speed_jump_bonus), false, cap)
        if not boosted_time then return nil end
        run_time = boosted_time
    end
    local walk, run = cfg.walk_speed * time, cfg.run_speed * run_time
    return {
        full_height = full, short_height = short, air_time = time,
        walk_distance = walk, run_distance = run, top_fall_speed = falling,
        full_tiles = full / tile_height, short_tiles = short / tile_height,
        walk_tiles = walk / tile_height, run_tiles = run / tile_height,
    }
end

return M
