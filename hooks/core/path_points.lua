-- Pure exported-map polyline conversion, shared by traversal bakers.
local M = {}

-- Return encoded offsets and absolute room points, or nil and one actionable error.
-- Callers raise once: LuaJ prefixes even error(message, 0).
function M.resolve(map, ref, map_height, origin_x, origin_y, fmt_num, object_id)
    local id = tonumber(type(ref) == "table" and ref.id or ref)
    local target, state
    local function visit(layers, ox, oy, visible)
        for _, layer in ipairs(layers or {}) do
            local x, y = ox + (tonumber(layer.offsetx) or 0), oy + (tonumber(layer.offsety) or 0)
            local shown = visible and layer.visible ~= false
            for _, obj in ipairs(layer.objects or {}) do
                if id and tonumber(obj.id) == id then
                    target, state = obj, {x=x, y=y, visible=shown and obj.visible ~= false}
                end
            end
            visit(layer.layers, x, y, shown)
        end
    end
    visit(map and map.layers, 0, 0, true)
    local problem
    if not target then problem = "path_ref is missing or outside this map"
    elseif not state.visible then problem = "path_ref selects a hidden path"
    elseif (tonumber(target.rotation) or 0) % 360 ~= 0 then problem = "path_ref selects a rotated path"
    elseif type(target.polyline) ~= "table" or #target.polyline < 2 then
        problem = "path_ref must select a polyline with at least 2 points"
    end
    local prefix = "Object " .. tostring(object_id) .. ": "
    local fix = "; draw a visible, unrotated polyline with at least 2 points in this map and select it in path_ref."
    if problem then return nil, prefix .. problem .. fix end
    local points, encoded, distinct = {}, {}, false
    for _, pt in ipairs(target.polyline) do
        local px, py = tonumber(pt.x), tonumber(pt.y)
        if not px or not py then return nil, prefix .. "path contains invalid coordinates" .. fix end
        local x = (tonumber(target.x) or 0) + px + state.x
        local y = map_height - ((tonumber(target.y) or 0) + py + state.y)
        points[#points+1] = {x=x, y=y}
        if #points > 1 and (x ~= points[1].x or y ~= points[1].y) then distinct = true end
        if fmt_num then encoded[#encoded+1] = fmt_num(x - (origin_x or 0)) .. "," .. fmt_num(y - (origin_y or 0)) end
    end
    if not distinct then return nil, prefix .. "path has no length" .. fix end
    return table.concat(encoded, ";"), points
end
return M
