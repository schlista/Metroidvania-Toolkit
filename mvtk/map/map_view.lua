-- Pure world map view math (G8-06). No engine calls, so desktop tests run it.
--
-- Three spaces:
--   world  - runtime positions (the layout normalised so its minimum room is 0,0);
--   map    - baked-map space, used by layout_map.lua and layout_vectors.lua:
--            map = world + origin_shift (mvtk/rooms/layout_io.lua);
--   screen - design pixels of the world map's view rectangle, origin bottom-left.
-- A view is {center_x, center_y (map), scale (screen px per map unit),
-- screen_w, screen_h}.
--
-- Zoom levels and detail pages (G8-06b) work in image space: the overview
-- image's pixels, origin bottom-left, which is the space the world map's
-- map_image node and its children use. A scale there is screen pixels per
-- image pixel.
local M = {}

-- Node pools of developer/ui/menus/world_map.gui (G8-06 slice b correction
-- 12). `cap` bounds how many items a pool shows; `nodes` is the GUI nodes
-- each item takes. world_map.gui_script reads the caps; the budget test sums
-- every pool against mvtk/ui/gui_budgets.lua and max_nodes. Rows not built yet
-- (stamps, items) reserve their planned size.
M.POOLS = {
    { id = "static", cap = 10, nodes = 1 },      -- overlay, root, image, fog, player, preview x3, title, legend
    { id = "pages", cap = 24, nodes = 1 },       -- detail pages (pages.cache_max is clamped to this)
    { id = "pages_root", cap = 1, nodes = 1 },
    { id = "detail_fog", cap = 1, nodes = 1 },
    { id = "labels", cap = 32, nodes = 1 },      -- region labels
    { id = "info", cap = 8, nodes = 1 },         -- info panel: backdrop and three lines
    { id = "cursor", cap = 2, nodes = 1 },       -- cursor cross: two bars
    { id = "legend", cap = 32, nodes = 1 },      -- kinds on screen: swatch and name each
    { id = "screenshot", cap = 100, nodes = 2 }, -- marker box and its inner square
    { id = "poi", cap = 128, nodes = 3 },        -- icon, facing tick and label
    { id = "travel", cap = 64, nodes = 1 },      -- fast-travel points
    { id = "stamps", cap = 72, nodes = 1 },      -- 64 stamps and 8 palette nodes (G8-07)
    { id = "items", cap = 193, nodes = 1 },      -- 192 item icons and the overlay (G8-08)
}
M.CAPS = {}
for _, pool in ipairs(M.POOLS) do M.CAPS[pool.id] = pool.cap end

-- Fixed dynamic textures besides the page pool: the overview fog, the detail
-- fog, the hot-reloaded overview, the screenshot preview and the room status
-- overlay (G8-08c, mvtk/ui/world_map_items.lua).
M.FIXED_TEXTURES = 5

function M.pool_nodes()
    local total = 0
    for _, pool in ipairs(M.POOLS) do total = total + pool.cap * pool.nodes end
    return total
end

local function num(v, default)
    local n = tonumber(v)
    if n == nil then return default end
    return n
end

function M.world_to_map(x, y, shift)
    shift = shift or {}
    return x + num(shift.x, 0), y + num(shift.y, 0)
end

function M.map_to_world(x, y, shift)
    shift = shift or {}
    return x - num(shift.x, 0), y - num(shift.y, 0)
end

-- Screen pixels per image pixel that fit the whole overview image, honouring
-- fit_mode, margin_px and max_screen_fraction from world_map_settings.lua, but
-- not scale_multiplier or min_scale: this is the true fit.
function M.fit_scale(screen_w, screen_h, image_w, image_h, cfg)
    cfg = cfg or {}
    image_w, image_h = math.max(1, num(image_w, 1)), math.max(1, num(image_h, 1))
    local margin = num(cfg.margin_px, 50)
    local scale_w = math.max(1, screen_w - margin * 2) / image_w
    local scale_h = math.max(1, screen_h - margin * 2) / image_h
    local scale = math.min(scale_w, scale_h)
    if cfg.fit_mode == "cover" then scale = math.max(scale_w, scale_h) end
    local frac = cfg.max_screen_fraction
    if type(frac) == "table" then
        if frac.w then scale = math.min(scale, screen_w * math.max(0.1, math.min(1, frac.w)) / image_w) end
        if frac.h then scale = math.min(scale, screen_h * math.max(0.1, math.min(1, frac.h)) / image_h) end
    end
    if scale <= 0 then scale = 1 end
    return scale
end

-- The legacy world opening and fallback: fit times scale_multiplier, raised
-- to min_scale. Room opening selects from the same zoom levels below.
function M.open_scale(screen_w, screen_h, image_w, image_h, cfg)
    cfg = cfg or {}
    local scale = M.fit_scale(screen_w, screen_h, image_w, image_h, cfg)
    local multiplier = num(cfg.scale_multiplier, 1)
    if multiplier > 0 then scale = scale * multiplier end
    local min_scale = num(cfg.min_scale, 0)
    if min_scale > 0 then scale = math.max(min_scale, scale) end
    if scale <= 0 then scale = 1 end
    return scale
end

-- Converts a screen-per-image-pixel scale to screen pixels per map unit, using
-- layout_map.lua's image pixels per map unit.
function M.units_scale(image_scale, map_meta)
    local s = map_meta and map_meta.scale
    return image_scale * num(s and s.x, 1)
end

function M.new_view(center_x, center_y, scale, screen_w, screen_h)
    return { center_x = center_x, center_y = center_y, scale = scale, screen_w = screen_w, screen_h = screen_h }
end

function M.map_to_screen(view, x, y)
    return view.screen_w * 0.5 + (x - view.center_x) * view.scale,
        view.screen_h * 0.5 + (y - view.center_y) * view.scale
end

function M.screen_to_map(view, sx, sy)
    return view.center_x + (sx - view.screen_w * 0.5) / view.scale,
        view.center_y + (sy - view.screen_h * 0.5) / view.scale
end

-- The map rectangle the view shows.
function M.visible_rect(view)
    local half_w, half_h = view.screen_w * 0.5 / view.scale, view.screen_h * 0.5 / view.scale
    return { min_x = view.center_x - half_w, min_y = view.center_y - half_h,
        max_x = view.center_x + half_w, max_y = view.center_y + half_h }
end

-- Changes the scale so the map point under screen point (sx, sy) stays there.
function M.zoom_at(view, new_scale, sx, sy)
    if not (new_scale and new_scale > 0) then return view end
    local mx, my = M.screen_to_map(view, sx, sy)
    view.scale = new_scale
    view.center_x = mx - (sx - view.screen_w * 0.5) / new_scale
    view.center_y = my - (sy - view.screen_h * 0.5) / new_scale
    return view
end

-- Keeps the view centre inside the world bounds plus margin (map units).
function M.clamp_pan(view, world_min, world_max, margin)
    margin = math.max(0, num(margin, 0))
    local function clamp(v, lo, hi)
        if lo > hi then return (lo + hi) * 0.5 end
        return math.max(lo, math.min(hi, v))
    end
    view.center_x = clamp(view.center_x, world_min.x - margin, world_max.x + margin)
    view.center_y = clamp(view.center_y, world_min.y - margin, world_max.y + margin)
    return view
end

-- Zoom levels (G8-06 slice b correction 6), in screen pixels per image pixel:
-- today's opening scale, then the true fit times 1, 2, 4 and 8 (powers of two
-- up to zoom.max_level, plus max_level itself), sorted and deduplicated. Levels
-- above zoom.max_px_per_tile screen pixels per tile are dropped, except the
-- opening scale, which always stays so a small world opens as it does today.
-- image_px_per_tile is the overview image's pixels per tile (nil: no tile cap).
-- Returns the levels and the index of the opening scale.
function M.zoom_levels(open_scale, fit, zoom, image_px_per_tile)
    zoom = zoom or {}
    open_scale = num(open_scale, 1)
    fit = num(fit, open_scale)
    local max_level = math.max(1, num(zoom.max_level, 8))
    local cap = math.huge
    local max_ppt = num(zoom.max_px_per_tile, 64)
    local per_tile = num(image_px_per_tile, 0)
    if max_ppt > 0 and per_tile > 0 then cap = max_ppt / per_tile end
    local candidates = { open_scale }
    local m = 1
    while m <= max_level do
        candidates[#candidates + 1] = fit * m
        m = m * 2
    end
    if m / 2 < max_level then candidates[#candidates + 1] = fit * max_level end
    local levels = {}
    for i, v in ipairs(candidates) do
        if v > 0 and (i == 1 or v <= cap) then levels[#levels + 1] = v end
    end
    table.sort(levels)
    local out = {}
    for _, v in ipairs(levels) do
        local last = out[#out]
        if not last or math.abs(v - last) > last * 1e-6 then out[#out + 1] = v end
    end
    local open_index = 1
    for i, v in ipairs(out) do
        if math.abs(v - open_scale) <= open_scale * 1e-6 then open_index = i end
    end
    return out, open_index
end

-- Deepest existing level fitting a room inside `fraction` of each screen
-- dimension. Room dimensions are overview-image pixels, levels are screen
-- pixels per image pixel. Unknown bounds retain the legacy opening index;
-- if even the shallowest level cannot fit, use that shallowest level.
function M.room_open_level(levels, room_w, room_h, screen_w, screen_h, fraction, old_index)
    if not (room_w and room_h and room_w > 0 and room_h > 0) then return old_index end
    fraction = num(fraction, 0.5)
    if fraction <= 0 or fraction > 1 then fraction = 0.5 end
    for i = #levels, 1, -1 do
        if room_w * levels[i] <= screen_w * fraction
            and room_h * levels[i] <= screen_h * fraction then return i end
    end
    return 1
end

-- Published outline coordinates are baked game units, not image pixels.
-- Only compatible outlines supplied by layout_vectors.load are used. This
-- same player-room scale also serves fast travel, whose selected stop keeps
-- its existing centring rule in the GUI.
function M.open_level(levels, old_index, cfg, vectors, room_id, map_meta, screen_w, screen_h)
    cfg = cfg or {}
    if cfg.open_zoom == "world" or not (vectors and room_id) then return old_index end
    local scale = map_meta and map_meta.scale
    if not (scale and scale.x and scale.y and scale.x > 0 and scale.y > 0) then return old_index end
    for _, room in ipairs(vectors.rooms or {}) do
        if room.id == room_id then
            local poly = room.poly or {}
            if #poly < 6 or #poly % 2 ~= 0 then return old_index end
            local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
            for i = 1, #poly, 2 do
                local x, y = tonumber(poly[i]), tonumber(poly[i + 1])
                if not (x and y) then return old_index end
                x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
            end
            return M.room_open_level(levels, (x1 - x0) * scale.x, (y1 - y0) * scale.y,
                screen_w, screen_h, cfg.open_room_fraction, old_index)
        end
    end
    return old_index
end

-- Level of detail. nil keeps the overview image: the scale is at or below
-- pages.threshold. Otherwise the page density in texels per image pixel: the
-- power of two at or below the scale, so a texel never covers less than one
-- screen pixel (thin outlines stay visible) and a 256-texel page covers at
-- least 256 screen pixels. fit_density then makes the pages fit the pool.
function M.detail_density(scale, pages)
    pages = pages or {}
    scale = num(scale, 0)
    if scale <= num(pages.threshold, 1.5) or scale <= 0 then return nil end
    local k = math.floor(math.log(scale) / math.log(2) + 1e-9)
    return 2 ^ k, k
end

-- Halves the density (doubling each page's span) until every page a view_w x
-- view_h screen area can touch fits `slots`, so the whole screen gets detail.
-- A 1920 x 1080 view needs up to 54 pages of 256 screen pixels, more than the
-- 24-page pool; a texel then spans up to 4 screen pixels. The image's own page
-- count (image_w x image_h image pixels) bounds the count on each axis.
function M.fit_density(density, scale, page_px, view_w, view_h, image_w, image_h, slots)
    scale, page_px, slots = num(scale, 1), num(page_px, 256), math.max(1, num(slots, 24))
    local function count(d)
        local span = page_px / d
        local function axis(view, image)
            local n = math.ceil(num(view, 0) / (span * scale)) + 1
            return math.min(n, math.max(1, math.ceil(num(image, 0) / span)))
        end
        return axis(view_w, image_w) * axis(view_h, image_h)
    end
    for _ = 1, 8 do
        if count(density) <= slots then break end
        density = density / 2
    end
    return density
end

-- The image rectangle a screen area shows when the image's origin sits at
-- screen (origin_x, origin_y) and one image pixel spans `scale` screen pixels.
-- area = {min_x, min_y, max_x, max_y} in the same screen space.
function M.image_rect(origin_x, origin_y, scale, area)
    return { min_x = (area.min_x - origin_x) / scale, min_y = (area.min_y - origin_y) / scale,
        max_x = (area.max_x - origin_x) / scale, max_y = (area.max_y - origin_y) / scale }
end

function M.page_key(k, col, row)
    return k .. ":" .. col .. ":" .. row
end

-- Pages covering `rect` (image space) plus `ring` pages on every side, within
-- the image (image_w x image_h). Each page is {key, k, col, row, x, y, span}
-- with x, y, span in image pixels. Visible pages come first, then the ring;
-- each group is sorted nearest the rectangle's centre first.
function M.page_keys(rect, density, page_px, ring, image_w, image_h)
    local span = num(page_px, 256) / density
    local k = math.floor(math.log(density) / math.log(2) + 0.5)
    ring = math.max(0, math.floor(num(ring, 1)))
    local last_col = math.max(0, math.ceil(image_w / span) - 1)
    local last_row = math.max(0, math.ceil(image_h / span) - 1)
    local c0 = math.max(0, math.floor(rect.min_x / span) - ring)
    local c1 = math.min(last_col, math.ceil(rect.max_x / span) - 1 + ring)
    local r0 = math.max(0, math.floor(rect.min_y / span) - ring)
    local r1 = math.min(last_row, math.ceil(rect.max_y / span) - 1 + ring)
    local cx, cy = (rect.min_x + rect.max_x) * 0.5, (rect.min_y + rect.max_y) * 0.5
    local pages = {}
    for row = r0, r1 do
        for col = c0, c1 do
            local x, y = col * span, row * span
            local dx, dy = x + span * 0.5 - cx, y + span * 0.5 - cy
            pages[#pages + 1] = { key = M.page_key(k, col, row), k = k, col = col, row = row,
                x = x, y = y, span = span, dist = dx * dx + dy * dy }
        end
    end
    table.sort(pages, function(a, b)
        local a_visible = a.x < rect.max_x and a.x + a.span > rect.min_x
            and a.y < rect.max_y and a.y + a.span > rect.min_y
        local b_visible = b.x < rect.max_x and b.x + b.span > rect.min_x
            and b.y < rect.max_y and b.y + b.span > rect.min_y
        if a_visible ~= b_visible then return a_visible end
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.key < b.key
    end)
    return pages
end

-- The page-grid rectangle (image space) that a page list covers, clipped to
-- the image. The detail fog uses it, so its rectangle changes only when the
-- view crosses a page edge.
function M.pages_rect(pages, image_w, image_h)
    if #pages == 0 then return nil end
    local r = { min_x = math.huge, min_y = math.huge, max_x = -math.huge, max_y = -math.huge }
    for _, p in ipairs(pages) do
        r.min_x = math.min(r.min_x, p.x); r.min_y = math.min(r.min_y, p.y)
        r.max_x = math.max(r.max_x, p.x + p.span); r.max_y = math.max(r.max_y, p.y + p.span)
    end
    r.min_x, r.min_y = math.max(0, r.min_x), math.max(0, r.min_y)
    r.max_x, r.max_y = math.min(image_w, r.max_x), math.min(image_h, r.max_y)
    return r
end

-- Rooms concealed as secrets (G8-06 slice b correction 9). is_hidden(id) is
-- Discovery.is_secret_hidden(nil, nil, id): hidden_rectangles carry padding, so
-- rooms are skipped by id. Returns the skip set and a signature that changes
-- whenever the set does; pages cache under it.
function M.concealed_rooms(vectors, is_hidden)
    local skip, ids = {}, {}
    for _, room in ipairs(vectors and vectors.rooms or {}) do
        if room.id and is_hidden(room.id) then
            skip[room.id] = true
            ids[#ids + 1] = tostring(room.id)
        end
    end
    table.sort(ids)
    return skip, table.concat(ids, "\n")
end

-- The page pool: a fixed number of slots, each owning one GUI node and one
-- texture name for the whole session (G8-06 slice b correction 10: there is no
-- public texture delete, so slots are reused, never freed).
-- slot = {index, key, ready, signature, used}.
local Cache = {}
Cache.__index = Cache

function M.new_page_cache(size)
    local cache = setmetatable({ slots = {}, by_key = {}, clock = 0 }, Cache)
    for i = 1, math.max(0, math.floor(num(size, 0))) do
        cache.slots[i] = { index = i, used = 0 }
    end
    return cache
end

function Cache:get(key)
    return self.by_key[key]
end

function Cache:touch(slot)
    self.clock = self.clock + 1
    slot.used = self.clock
end

-- A slot for `key`: its own slot, an empty one, or the least recently used
-- slot whose page is not in `needed` (a set of keys). nil when every slot holds
-- a needed page.
function Cache:acquire(key, needed)
    local slot = self.by_key[key]
    if slot then return slot end
    local victim
    for _, s in ipairs(self.slots) do
        if not s.key then victim = s; break end
        if not needed[s.key] and (not victim or s.used < victim.used) then victim = s end
    end
    if not victim then return nil end
    if victim.key then self.by_key[victim.key] = nil end
    victim.key, victim.ready, victim.signature = key, false, nil
    self.by_key[key] = victim
    return victim
end

-- Forgets every page, keeping the slots (their textures stay allocated).
function Cache:clear()
    for _, s in ipairs(self.slots) do s.key, s.ready, s.signature, s.used = nil, false, nil, 0 end
    self.by_key = {}
end

-- Map inputs (G8-06 slice b correction 13). Raw input ids from
-- developer/input/game.input_binding, read only while the world map is open.
-- No gameplay action or binding is added.
M.INPUTS = {
    zoom_in = { "gamepad_rstick_up", "gamepad_rtrigger", "mouse_wheel_up", "key_e" },
    zoom_out = { "gamepad_rstick_down", "gamepad_ltrigger", "mouse_wheel_down", "key_q" },
    center = { "gamepad_rstick_click", "key_c" },
    drag = { "mouse_button_1" },
    previous_stop = { "gamepad_lshoulder" },
    next_stop = { "gamepad_rshoulder" },
    -- Shows or hides the legend (G8-06c): top face button or I.
    legend = { "gamepad_rpad_up", "key_i" },
}
-- Pan directions. Stick ids are analog: their value scales the speed.
M.PAN_STICK = { gamepad_lstick_left = { -1, 0 }, gamepad_lstick_right = { 1, 0 },
    gamepad_lstick_up = { 0, 1 }, gamepad_lstick_down = { 0, -1 } }
M.PAN_KEYS = { key_left = { -1, 0 }, key_a = { -1, 0 }, key_right = { 1, 0 }, key_d = { 1, 0 },
    key_up = { 0, 1 }, key_w = { 0, 1 }, key_down = { 0, -1 }, key_s = { 0, -1 },
    -- The D-pad pans too (G8-06c): screenshot markers are chosen by pointing.
    gamepad_lpad_left = { -1, 0 }, gamepad_lpad_right = { 1, 0 },
    gamepad_lpad_up = { 0, 1 }, gamepad_lpad_down = { 0, -1 } }
-- Analog zoom inputs (stick and triggers) step once each time they pass this value.
M.ANALOG_STEP = 0.5
-- A stepped stick or trigger counts as let go only at or below this value: Defold
-- reports it released while it is still about 0.8 in, so the value decides.
M.ANALOG_RELEASE = 0.3

local input_index
local function index_inputs()
    if input_index then return input_index end
    input_index = {}
    local function put(name, kind, dir)
        local row = { kind = kind, name = name, dir = dir }
        input_index[name] = row
        if hash then input_index[hash(name)] = row end
    end
    for kind, names in pairs(M.INPUTS) do
        for _, name in ipairs(names) do put(name, kind) end
    end
    for name, dir in pairs(M.PAN_STICK) do put(name, "pan_stick", dir) end
    for name, dir in pairs(M.PAN_KEYS) do put(name, "pan_key", dir) end
    return input_index
end

-- What a raw input id does on the map: {kind, name, dir} or nil. Kinds:
-- zoom_in, zoom_out, center, drag, previous_stop, next_stop, legend, pan_stick,
-- pan_key.
function M.input(id)
    if id == nil then return nil end
    return index_inputs()[id]
end

function M.is_analog(name)
    return name ~= nil and (name:match("stick_") ~= nil or name:match("trigger$") ~= nil)
end

-- Next zoom level index, clamped to the list. Returns the index and whether it changed.
function M.step_level(levels, index, dir)
    local count = levels and #levels or 0
    if count == 0 then return index, false end
    local now = math.max(1, math.min(count, num(index, 1)))
    local nxt = math.max(1, math.min(count, now + (dir or 0)))
    return nxt, nxt ~= now
end

-- Pan velocity as a unit-or-shorter vector from held stick values and keys.
-- sticks: {name = value 0..1}; keys: {name = true}.
function M.pan_vector(sticks, keys)
    local x, y = 0, 0
    for name, value in pairs(sticks or {}) do
        local dir = M.PAN_STICK[name]
        if dir then x = x + dir[1] * num(value, 0); y = y + dir[2] * num(value, 0) end
    end
    for name, on in pairs(keys or {}) do
        local dir = M.PAN_KEYS[name]
        if dir and on then x = x + dir[1]; y = y + dir[2] end
    end
    local len = math.sqrt(x * x + y * y)
    if len > 1 then x, y = x / len, y / len end
    return x, y
end

-- Root origin (screen position of image pixel 0,0) that puts image point
-- (cx, cy) at the view centre. Along an axis where the image is no larger than
-- the view, the image is centred; otherwise its edges stay at most `margin`
-- screen pixels inside the view. With margin 0 this is the world map's
-- original follow rule. Returns origin_x, origin_y and the image point now at
-- the view centre.
function M.root_origin(screen_w, screen_h, image_w, image_h, scale, cx, cy, margin)
    scale = num(scale, 1)
    if scale <= 0 then scale = 1 end
    margin = math.max(0, num(margin, 0))
    local function axis(screen, size, c)
        local extent = size * scale
        local slack = screen - extent
        if slack >= 0 then return slack * 0.5 end
        local origin = screen * 0.5 - c * scale
        return math.max(slack - margin, math.min(margin, origin))
    end
    local ox = axis(screen_w, image_w, cx)
    local oy = axis(screen_h, image_h, cy)
    return ox, oy, (screen_w * 0.5 - ox) / scale, (screen_h * 0.5 - oy) / scale
end

-- The image point to centre after a zoom from old_scale to new_scale, so the
-- image point under screen point (ax, ay) stays under it. origin is the root
-- origin before the zoom.
function M.anchor_center(origin_x, origin_y, old_scale, new_scale, ax, ay, screen_w, screen_h)
    local px = (ax - origin_x) / old_scale
    local py = (ay - origin_y) / old_scale
    return px - (ax - screen_w * 0.5) / new_scale, py - (ay - screen_h * 0.5) / new_scale
end

-- ============================================================================
-- Pointing (G8-06c): the cursor, rooms under it, snapping and region labels.
-- ============================================================================

-- Even-odd test of point (x, y) against a flat polygon {x1, y1, x2, y2, ...}.
-- Bounding boxes overlap for L-shaped rooms, so rooms are told apart by this.
function M.point_in_poly(poly, x, y)
    local n = math.floor(#(poly or {}) / 2)
    if n < 3 then return false end
    local inside = false
    local jx, jy = poly[n * 2 - 1], poly[n * 2]
    for i = 1, n do
        local ix, iy = poly[i * 2 - 1], poly[i * 2]
        if (iy > y) ~= (jy > y) and x < (jx - ix) * (y - iy) / (jy - iy) + ix then
            inside = not inside
        end
        jx, jy = ix, iy
    end
    return inside
end

local function poly_box(room)
    local box = room._box
    if box then return box end
    local poly = room.poly or {}
    box = { min_x = math.huge, min_y = math.huge, max_x = -math.huge, max_y = -math.huge }
    for i = 1, #poly - 1, 2 do
        local x, y = poly[i], poly[i + 1]
        if x < box.min_x then box.min_x = x end
        if x > box.max_x then box.max_x = x end
        if y < box.min_y then box.min_y = y end
        if y > box.max_y then box.max_y = y end
    end
    room._box = box
    return box
end

-- The room of layout_vectors.lua whose outline holds map point (x, y), or nil.
-- `skip` is a set of room ids to ignore (rooms concealed as secrets).
function M.room_at(vectors, x, y, skip)
    for _, room in ipairs(vectors and vectors.rooms or {}) do
        if room.id and not (skip and skip[room.id]) then
            local b = poly_box(room)
            if x >= b.min_x and x <= b.max_x and y >= b.min_y and y <= b.max_y
                and M.point_in_poly(room.poly, x, y) then
                return room
            end
        end
    end
    return nil
end

-- The overview-only fallback: the first room whose bounds {id, r = {min_x,
-- min_y, max_x, max_y}} hold the point (MINIMAP_MODULE.snapshot().rooms).
function M.room_in_bounds(rooms, x, y, skip)
    for _, room in ipairs(rooms or {}) do
        local b = room.r
        if room.id and b and not (skip and skip[room.id])
            and x >= b.min_x and x < b.max_x and y >= b.min_y and y < b.max_y then
            return room
        end
    end
    return nil
end

-- Where the cursor points, in screen (design) pixels: the mouse pointer once
-- the mouse moved, else the view centre (a controller or the keyboard pans the
-- map under a fixed centre cursor).
function M.cursor_point(pointer, screen_w, screen_h)
    if pointer and pointer.x and pointer.y then return pointer.x, pointer.y end
    return screen_w * 0.5, screen_h * 0.5
end

-- The item nearest screen point (x, y) within `radius` screen pixels, or nil.
-- items = {{sx, sy, ...}}; ties keep the earlier item.
function M.nearest(items, x, y, radius)
    radius = num(radius, 0)
    local best, best_d = nil, radius * radius
    for _, item in ipairs(items or {}) do
        if item.sx and item.sy then
            local dx, dy = item.sx - x, item.sy - y
            local d = dx * dx + dy * dy
            if d <= best_d and (best == nil or d < best_d) then best, best_d = item, d end
        end
    end
    return best
end

-- Region label opacity from 1 to 0: full while the zoom is at most
-- labels.fade_zoom times the whole-world fit, gone at twice that.
function M.label_alpha(scale, fit, labels)
    labels = labels or {}
    fit = num(fit, 0)
    if fit <= 0 then return 1 end
    local start = math.max(1e-6, num(labels.fade_zoom, 2))
    local ratio = num(scale, fit) / fit
    if ratio <= start then return 1 end
    if ratio >= start * 2 then return 0 end
    return 1 - (ratio - start) / start
end

-- Region labels that do not give rooms away (G8-06 slice b correction 11).
-- rooms: MINIMAP_MODULE.snapshot().rooms ({id, r}); known(id) is true for a
-- room the player visited or had revealed, and false for a concealed one.
-- Only known rooms place a label and its centroid, so a region with none stays
-- unnamed. Regions is mvtk/world/regions.lua (passed in, so this stays pure).
-- Returns {{id, name, x, y}} sorted by region id, at most `max`; a region
-- whose name is blank has no label (never the id).
function M.region_labels(rooms, known, Regions, max)
    local shown = {}
    for _, room in ipairs(rooms or {}) do
        if room.id and known(room.id) then shown[#shown + 1] = room end
    end
    local regions = Regions.layout_regions(shown)
    local ids = {}
    for id in pairs(regions) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do
        local info = Regions.info(id)
        local c = regions[id].centroid
        if info and info.name ~= "" and c and #out < num(max, M.CAPS.labels) then
            out[#out + 1] = { id = id, name = info.name, x = c.x, y = c.y }
        end
    end
    return out
end

return M
