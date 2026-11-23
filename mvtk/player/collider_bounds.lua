-- Local fixture edges, including the authored offset and baked player scale.
-- Read on demand: compact/roll swaps can change the live shape between frames.
local M = {}

local function fixture_edges(body)
    local left, right, top, bottom
    -- Same pixel-space polygon geometry used by player placement, without
    -- the extra skin included in a Box2D AABB.
    for _, fixture in ipairs(b2d.body.get_fixtures(body)) do
        local shape = b2d.fixture.get_shape(body, fixture.index)
        if shape.vertices then
            for _, vertex in ipairs(shape.vertices) do
                left = math.min(left or math.huge, vertex.x or 0)
                right = math.max(right or -math.huge, vertex.x or 0)
                top = math.max(top or -math.huge, vertex.y)
                bottom = math.min(bottom or math.huge, vertex.y)
            end
        elseif shape.radius then
            local center_x = shape.center and shape.center.x or 0
            local center_y = shape.center and shape.center.y or 0
            left = math.min(left or math.huge, center_x - shape.radius)
            right = math.max(right or -math.huge, center_x + shape.radius)
            top = math.max(top or -math.huge, center_y + shape.radius)
            bottom = math.min(bottom or math.huge, center_y - shape.radius)
        end
    end
    return top, bottom, left, right
end

function M.body(component)
    local body = assert(b2d.get_body(component), "Player headroom needs its live collision body")
    local top, bottom = fixture_edges(body)
    assert(top and bottom, "Player headroom needs a polygon or circle collision shape")
    return top, bottom
end

function M.rect(component)
    local body = b2d and b2d.get_body(component)
    if not body then return nil end
    local top, bottom, left, right = fixture_edges(body)
    if not top then return nil end
    return {
        half_w = (right - left) * 0.5, half_h = (top - bottom) * 0.5,
        x = (left + right) * 0.5, y = (bottom + top) * 0.5,
    }
end

function M.top(self, component)
    local ctx = self._bone_physics
    if not component and ctx and ctx.use_bone_feet ~= false then
        -- Spine keeps its resolved head bone; it has no sprite body component.
        return ctx.head_offset or self.collider_half_height or 60
    end
    -- The second result lets a sprite probe start inside its offset body even
    -- when a very short compact form lies entirely below the player origin.
    return M.body(component or (self._compact_active and "#co_compact" or "#co"))
end

return M
