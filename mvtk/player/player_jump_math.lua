-- Pure jump calculations shared by the player and the movement reach read-out.

local M = {}

--- Compute the initial jump speed for the configured jump height.
-- If `cfg.jump_speed` is provided and positive it is returned verbatim
-- (lets creators override the derived speed). Otherwise derives from
-- gravity and jump_height with sensible fallbacks.
function M.compute_jump_speed(cfg)
    cfg = cfg or {}
    if cfg.jump_speed and cfg.jump_speed > 0 then
        return cfg.jump_speed
    end
    local g = math.abs(cfg.gravity or 1200)
    local h = cfg.jump_height or 256
    return math.sqrt(2 * g * h)
end

--- Compute the extended-jump speed bonus from cfg.extended_jump_height.
-- Used when the player holds the jump button for the extended-jump
-- mechanic. Falls back to gravity=1200, height=64 to match the prior
-- inline defaults.
function M.compute_extended_jump_speed(cfg)
    cfg = cfg or {}
    local g = math.abs(cfg.gravity or 1200)
    local extended_h = cfg.extended_jump_height or 64
    return math.sqrt(2 * g * extended_h)
end

-- The release can act from the opening of the reference frame that spends
-- the rest of the hold. Treat values near a whole frame as that frame count.
function M.shortest_jump_release_time(hold, reference_step)
    local frames = hold / reference_step
    local nearest = math.floor(frames + 0.5)
    if math.abs(frames - nearest) <= 1e-6 then frames = nearest end
    return math.max(0, math.ceil(frames) - 1) * reference_step
end

return M
