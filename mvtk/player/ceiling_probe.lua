-- Pure ceiling probe/clamp math. The caller supplies raycast_fn so this module
-- can be tested outside Defold and the runtime adapter can reuse scratch vectors.

local M = { SHOULDER_FRACTION = 0.8 }

function M.evaluate(opts)
    opts = opts or {}
    local pos = opts.pos or {}
    local prev_pos = opts.prev_pos or pos
    local pos_y = tonumber(pos.y) or 0
    local prev_y = tonumber(prev_pos and prev_pos.y) or pos_y
    local vy = tonumber(opts.vy) or 0
    local dy_up = pos_y - prev_y
    if vy <= 0 and dy_up <= 0.01 then
        return { should_run = false, dy_up = dy_up, hits = {} }
    end

    local half_width = tonumber(opts.half_width) or 30
    local half_height = tonumber(opts.half_height) or 60
    local effective_head = tonumber(opts.collider_top) or tonumber(opts.head_offset) or half_height
    local clearance = tonumber(opts.clearance) or 8
    -- Margin extends detection only; it must not enlarge the collision body.
    local ray_length = effective_head + clearance + (tonumber(opts.head_margin) or 0) + math.max(0, dy_up)
    local pos_x = tonumber(pos.x) or 0
    local bottom = tonumber(opts.collider_bottom)
    -- A compact fixture can sit wholly below the root. Starting in its live
    -- body avoids starting inside the ceiling (which Box2D raycasts ignore).
    local origin_y = pos_y + (bottom and (bottom + effective_head) * 0.5 or 0)
    local shoulder = half_width * M.SHOULDER_FRACTION
    local samples = { pos_x - shoulder, pos_x, pos_x + shoulder }
    local hits = {}
    local min_ceiling_y

    for _, sample_x in ipairs(samples) do
        local hit = opts.raycast_fn
            and opts.raycast_fn(sample_x, origin_y, pos_y + ray_length, opts.groups)
            or nil
        local is_platform = hit and opts.platform_group ~= nil and hit.group == opts.platform_group
        local accepted = hit and not is_platform
            and ((not opts.classify) or opts.classify(hit, opts.max_slope_angle))
        if accepted then
            local ceiling_y = hit.position.y - effective_head - clearance
            hits[#hits + 1] = { hit = hit, ceiling_y = ceiling_y, sample_x = sample_x }
            if min_ceiling_y == nil or ceiling_y < min_ceiling_y then
                min_ceiling_y = ceiling_y
            end
        end
    end

    local clamp_y
    if min_ceiling_y and pos_y > min_ceiling_y then
        -- A low ceiling can refuse a rise, never push us below the frame start.
        clamp_y = math.max(prev_y, min_ceiling_y)
        clamp_y = math.min(pos_y, clamp_y)
    end
    return {
        should_run = true,
        dy_up = dy_up,
        effective_head = effective_head,
        ray_length = ray_length,
        samples = samples,
        hits = hits,
        min_ceiling_y = min_ceiling_y,
        clamp_y = clamp_y,
        stop_upward_velocity = clamp_y ~= nil and vy > 0,
    }
end

return M
