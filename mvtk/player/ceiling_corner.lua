-- Ray-sampled clearance for a rise that hit exactly one ceiling shoulder.
local M = {}
local SAMPLE_SPACING = 4
local FACE_INSET = 0.001

function M.free_airborne(self)
    local features = self._host and self._host.features
    local launch = features and features.launch
    local zipline = features and features.zipline
    return not self.grounded and not self._is_dead
        and not self._spine_physics_active and not self._in_climb and not self._in_water
        and not self._grapple_active and not self._ledge_hanging and not self._ledge_climbing
        and not self._ledge_kinematic and not self._pound_active
        and not (launch and launch.loaded) and not (zipline and zipline.active)
end

function M.eligible(self)
    return (self.vy or 0) > 0 and M.free_airborne(self)
end

local function measure_overlap(x, edge_x, side, low, top, hit_y, spacing, cast, groups)
    local distance = 0
    -- Also sample just inside the detected underside so a shallow lip
    -- between two of the regular slices can supply its actual edge.
    local slices = math.max(1, math.ceil((top - low) / spacing))
    for i = 0, slices + 1 do
        local y = i <= slices and (low + (top - low) * i / slices) or hit_y
        local hit = cast(x, y, edge_x, y, groups)
        if hit then distance = math.max(distance, (edge_x - hit.position.x) * side) end
    end
    return distance
end

local function destination_clear(pos, x, side, width, bottom, top, previous_y, clearance,
        spacing, inset, cast, groups)
    local low, high = pos.y + bottom + inset, pos.y + top - inset
    local leading_face = x - side * width
    local rows = math.max(1, math.ceil((high - low) / spacing))
    for i = 0, rows do
        local y = low + (high - low) * i / rows
        if cast(pos.x, y, leading_face, y, groups) then return false end
    end

    -- Cover the destination across the vertical approach, including solids
    -- below the midpoint of an offset or shortened body.
    local origin_y = math.min(previous_y, pos.y) + bottom + inset
    local destination_top = pos.y + top + clearance
    local span = 2 * (width - inset)
    local columns = math.max(1, math.ceil(span / spacing))
    for i = 0, columns do
        local sample_x = x - width + inset + span * i / columns
        if cast(sample_x, origin_y, sample_x, destination_top, groups) then return false end
    end
    return true
end

function M.try(self, opts, probe, grounded, physical_wall, cast)
    local cfg = self._cfg or {}
    local limit = tonumber(cfg.corner_correction_px) or 0
    if limit <= 0 or grounded or #probe.hits ~= 1 or not M.eligible(self) then return false end

    local pos, width = self.pos, opts.half_width
    local hit = probe.hits[1]
    if hit.sample_x == pos.x then return false end
    local side = hit.sample_x < pos.x and -1 or 1
    if physical_wall == -side or
        ((self._on_wall or self._wall_sliding) and self._wall_side == -side) then return false end

    local top, bottom = probe.effective_head, opts.collider_bottom
    if not bottom or top <= bottom then return false end
    local scale = cfg.player_scale or 1
    local spacing = SAMPLE_SPACING * scale
    local inset = math.min(FACE_INSET * scale, width * 0.25, (top - bottom) * 0.25)
    local head_y = pos.y + top + opts.clearance
    local low_y = pos.y + (top + bottom) * 0.5
    local hit_y = hit.hit.position.y
    hit_y = hit_y + math.min(inset, (head_y - hit_y) * 0.5)

    local groups = {}
    for _, group in ipairs(opts.groups) do
        if group ~= opts.platform_group then groups[#groups + 1] = group end
    end

    local distance = measure_overlap(pos.x, pos.x + side * width, side, low_y, head_y, hit_y,
        spacing, cast, groups)
    if distance <= 0 or distance > limit + inset then return false end
    local x = pos.x - side * math.min(distance, limit)
    if not destination_clear(pos, x, side, width, bottom, top, opts.prev_pos.y,
        opts.clearance, spacing, inset, cast, groups) then return false end
    pos.x = x
    return true
end

return M
