-- Pure rasterizer for world map detail pages (G8-06).
--
-- Draws one rectangle of map space from layout_vectors.lua into an RGBA string:
-- room fills by even-odd scanline spans, then outlines, platforms and doors as
-- thin quads through the same span filler, painted in that order (as
-- developer/tools/layout_minimap.lua paints the overview image). Rows are
-- string.rep runs, as mvtk/ui/minimap/fog.lua builds its mask. Row 0 is the
-- page's min_y, so callers pass the result to DynamicTexture.update with
-- flip = true, as fog.lua does.
local M = {}

M.COLORS = {
    outline = { 210, 238, 255, 255 },
    platform = { 180, 255, 255, 255 },
    door = { 255, 240, 96, 255 },
    locked = { 255, 96, 96, 255 },
}

local CLEAR = string.char(0, 0, 0, 0)

local function b(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 0) + 0.5))) end

-- RGBA bytes of colour c. With a background, c is composited over it
-- (source-over), so the page is as opaque as the background.
local function bytes(c, bg)
    if not bg then return string.char(b(c[1]), b(c[2]), b(c[3]), b(c[4])) end
    local a, ba = b(c[4]) / 255, b(bg[4]) / 255
    local out_a = a + ba * (1 - a)
    if out_a <= 0 then return CLEAR end
    local function mix(i) return (b(c[i]) * a + b(bg[i]) * ba * (1 - a)) / out_a end
    return string.char(b(mix(1)), b(mix(2)), b(mix(3)), b(out_a * 255))
end

-- Even-odd spans of a pixel-space polygon on the row whose centre is cy.
-- Pixel x is covered when its centre lies in [left, right).
local function polygon_spans(xs, ys, cy, width, color, out)
    local hits = {}
    local n = #xs
    local j = n
    for i = 1, n do
        local yi, yj = ys[i], ys[j]
        if (yi > cy) ~= (yj > cy) then
            hits[#hits + 1] = xs[i] + (cy - yi) * (xs[j] - xs[i]) / (yj - yi)
        end
        j = i
    end
    table.sort(hits)
    for k = 1, #hits - 1, 2 do
        local x0 = math.max(0, math.ceil(hits[k] - 0.5))
        local x1 = math.min(width, math.ceil(hits[k + 1] - 0.5))
        if x1 > x0 then out[#out + 1] = { x0, x1, color } end
    end
end

-- A segment as a quad `px` pixels thick, in pixel space.
local function segment_quad(x0, y0, x1, y1, px)
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    local h = px * 0.5
    if len < 1e-9 then
        return { x0 - h, x0 + h, x0 + h, x0 - h }, { y0 - h, y0 - h, y0 + h, y0 + h }
    end
    -- Extend along the segment by half the width so corners close.
    local ux, uy = dx / len * h, dy / len * h
    local nx, ny = -uy, ux
    local ax, ay, bx, by = x0 - ux, y0 - uy, x1 + ux, y1 + uy
    return { ax + nx, bx + nx, bx - nx, ax - nx }, { ay + ny, by + ny, by - ny, ay - ny }
end

-- Paints shape lists ({xs, ys, colour bytes, min_y, max_y} in pixel space) in
-- order into an RGBA string of width x height, row 0 first. Later shapes win.
local function paint(fills, lines, width, height, clear)
    local rows = {}
    for y = 0, height - 1 do
        local cy = y + 0.5
        local spans = {}
        for _, list in ipairs({ fills, lines }) do
            for _, shape in ipairs(list) do
                if cy >= shape[4] and cy < shape[5] then
                    polygon_spans(shape[1], shape[2], cy, width, shape[3], spans)
                end
            end
        end
        if #spans == 0 then
            rows[#rows + 1] = string.rep(clear, width)
        else
            -- Later spans paint over earlier ones: resolve each elementary
            -- interval between span edges to its topmost span.
            local edges, seen = { 0, width }, { [0] = true, [width] = true }
            for _, s in ipairs(spans) do
                for e = 1, 2 do
                    if not seen[s[e]] then seen[s[e]] = true; edges[#edges + 1] = s[e] end
                end
            end
            table.sort(edges)
            local chunks = {}
            for e = 1, #edges - 1 do
                local a, b = edges[e], edges[e + 1]
                local color = clear
                for k = #spans, 1, -1 do
                    local s = spans[k]
                    if s[1] <= a and s[2] >= b then color = s[3]; break end
                end
                chunks[#chunks + 1] = string.rep(color, b - a)
            end
            rows[#rows + 1] = table.concat(chunks)
        end
    end
    return table.concat(rows)
end

-- vectors: decoded layout_vectors.lua. page: {min_x, min_y, max_x, max_y} in
-- map space. width, height: page pixels. opts.skip: set of room ids not drawn
-- (rooms concealed as secrets); opts.line_px: line width in page pixels
-- (default 1); opts.colors overrides M.COLORS entries; opts.background
-- ({r, g, b, a} bytes) fills the empty texels, with every colour composited
-- over it, so an opaque background gives an opaque page that hides the
-- overview image beneath it.
function M.rasterize(vectors, page, width, height, opts)
    opts = opts or {}
    local skip = opts.skip or {}
    local colors = opts.colors or {}
    local bg = opts.background
    local clear = bg and bytes(bg) or CLEAR
    local line_px = math.max(1, tonumber(opts.line_px) or 1)
    local sx = width / (page.max_x - page.min_x)
    local sy = height / (page.max_y - page.min_y)
    local function to_px(x, y) return (x - page.min_x) * sx, (y - page.min_y) * sy end

    -- Shapes in paint order: {xs, ys, color, min_y, max_y} in pixel space.
    -- Shapes wholly beside or above/below the page paint nothing and are dropped.
    local fills, lines = {}, {}
    local function add(list, xs, ys, color)
        local lo, hi = math.huge, -math.huge
        for i = 1, #ys do
            if ys[i] < lo then lo = ys[i] end
            if ys[i] > hi then hi = ys[i] end
        end
        local left, right = math.huge, -math.huge
        for i = 1, #xs do
            if xs[i] < left then left = xs[i] end
            if xs[i] > right then right = xs[i] end
        end
        if hi > 0 and lo < height and right > 0 and left < width then list[#list + 1] = { xs, ys, color, lo, hi } end
    end
    local outline = bytes(colors.outline or M.COLORS.outline, bg)
    local platform = bytes(colors.platform or M.COLORS.platform, bg)
    local door = bytes(colors.door or M.COLORS.door, bg)
    local locked = bytes(colors.locked or M.COLORS.locked, bg)
    local outlines, platforms, doors = {}, {}, {}
    -- A line covers the pixels whose centres lie within line_px / 2 of it,
    -- half-open like the fills: a 1 px line on edge X paints pixel X - 1.
    local function add_segment(list, x0, y0, x1, y1, color)
        if color:byte(4) == 0 or (bg and color == clear) then return end
        local ax, ay = to_px(x0, y0)
        local bx, by = to_px(x1, y1)
        local xs, ys = segment_quad(ax, ay, bx, by, line_px)
        add(list, xs, ys, color)
    end
    for _, room in ipairs(vectors and vectors.rooms or {}) do
        if not skip[room.id] then
            local poly = room.poly or {}
            local count = math.floor(#poly / 2)
            if count >= 3 then
                local xs, ys = {}, {}
                for i = 1, count do xs[i], ys[i] = to_px(poly[i * 2 - 1], poly[i * 2]) end
                local c = room.color or {}
                if (tonumber(c[4]) or 0) > 0 then add(fills, xs, ys, bytes(c, bg)) end
                for i = 1, count do
                    local k = i % count + 1
                    add_segment(outlines, poly[i * 2 - 1], poly[i * 2], poly[k * 2 - 1], poly[k * 2], outline)
                end
            end
            local p = room.platforms or {}
            for i = 1, #p - 3, 4 do add_segment(platforms, p[i], p[i + 1], p[i + 2], p[i + 3], platform) end
            local d = room.doors or {}
            for i = 1, #d - 4, 5 do
                add_segment(doors, d[i], d[i + 1], d[i + 2], d[i + 3], d[i + 4] == 1 and locked or door)
            end
        end
    end
    for _, list in ipairs({ outlines, platforms, doors }) do
        for _, shape in ipairs(list) do lines[#lines + 1] = shape end
    end

    return paint(fills, lines, width, height, clear)
end

-- Room status overlay (G8-08 step 3): one texture over the overview image.
-- shapes = {{xs, ys, color = {r, g, b, a} bytes}} in texture pixels, painted in
-- order (a room tint first, then its dot). Empty texels stay clear, so only
-- the shapes show over the map. Row 0 is the image's min_y (flip = true).
function M.status(shapes, width, height)
    local fills = {}
    for _, shape in ipairs(shapes or {}) do
        local xs, ys = shape.xs or {}, shape.ys or {}
        local lo, hi = math.huge, -math.huge
        for i = 1, #ys do
            if ys[i] < lo then lo = ys[i] end
            if ys[i] > hi then hi = ys[i] end
        end
        local c = shape.color or {}
        if #xs >= 3 and hi > 0 and lo < height and b(c[4]) > 0 then
            fills[#fills + 1] = { xs, ys, bytes(c), lo, hi }
        end
    end
    return paint(fills, {}, width, height, CLEAR)
end

return M
