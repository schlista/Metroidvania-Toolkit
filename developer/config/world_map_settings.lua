-- developer/config/world_map_settings.lua
-- Tuning for world map GUI colors, fog behavior, and label offsets

local v4 = vmath and vmath.vector4 or function(r,g,b,a) return { x=r, y=g, z=b, w=a } end

local M = {
  enabled = true, -- Allow opening the world map (including its fast-travel view).
  fit_mode = "contain",  -- keep whole map visible
  margin_px = 0,
  -- Opening zoom: "room" chooses the deepest existing level that fits the
  -- player's current room; "world" keeps fit * scale_multiplier and min_scale.
  -- Missing room outlines/bounds always use the "world" opening instead.
  open_zoom = "room",
  -- Room opening fits inside this fraction of BOTH screen width and height
  -- (0 < fraction <= 1). Half leaves space around the player and nearby rooms.
  -- Fast travel uses the same zoom, centred on the selected destination.
  open_room_fraction = 0.5,
  scale_multiplier = 0.3, -- World opening/fallback multiplier, before min_scale.
  max_screen_fraction = { w = 1.0, h = 1.0 }, -- allow full screen usage
  min_scale = 0.2,
  show_border = false,  -- no border frame
  show_title = false,   -- no title text
  show_legend = true,   -- Show the button hints and icon kinds under the map (I or the top face button toggles them).
  colors = {
    bg      = v4(0.00, 0.00, 0.00, 1.0),  -- solid black background
    frame   = v4(0.80, 0.93, 0.99, 0.35),
    outline = v4(0.80, 0.93, 0.99, 1.00),
    unexplored = v4(0.60, 0.60, 0.70, 0.35),
    icon_bench = v4(1.00, 0.92, 0.20, 0.95),
    icon_shop  = v4(0.20, 0.85, 0.95, 0.95), -- Colour of shops and trade stations after room entry.
    icon_boss  = v4(0.95, 0.30, 0.30, 0.95),
    icon_custom= v4(0.70, 0.40, 0.95, 0.95),
  },
  fog = {
    darken = 0.65,  -- multiply biome RGB by this for fog color
    alpha  = 0.28,  -- fog opacity
  },
  labels = {
    poi_offset = { x = 10, y = 6 },  -- offset from icon center
    -- Region names from developer/config/biomes.lua, drawn over the map. A
    -- region is named only once the player visited or revealed one of its
    -- rooms; rooms hidden as secrets never place or move a name.
    regions = true,  -- Show region names on the world map.
    max = 32,        -- Most region names shown at once (at most 32).
    fade_zoom = 2,   -- Names fade out above this many times the whole-world zoom, and are gone at twice it.
  },
  -- The pointing cursor: the view centre with a controller or the keyboard,
  -- the mouse pointer once the mouse moves. It snaps to the nearest icon, and
  -- in fast travel only to travel stops, so A travels to the stop it points at.
  cursor = {
    snap_px = 24,       -- Snap to an icon within this many screen (design) pixels of the cursor.
    info_panel = true,  -- Name the region, room title and icon under the cursor in the top-left panel.
  },
  -- Zoom levels for large worlds: the world opening/fallback plus the
  -- whole-world fit times 1, 2, 4 and 8. Room opening chooses from this list.
  zoom = {
    max_level = 8,        -- Deepest zoom, as a multiple of the whole-world fit (2 to 8).
    max_px_per_tile = 64, -- Never zoom in so far that one tile spans more screen pixels than this.
  },
  -- Moving around the open map: left stick, WASD or the arrow keys, or
  -- dragging with the left mouse button. Zoom: right stick up and down, the
  -- triggers, the mouse wheel (at the pointer) or Q and E. Right stick click or
  -- C centres the view again. Fast travel keeps up and down for choosing a
  -- stop, and LB and RB jump to the previous or next stop.
  pan = {
    speed = 900,     -- Stick and key panning speed, in screen (design) pixels per second at any zoom.
    margin_px = 64,  -- How far, in screen pixels, a panned view may show past the map's edges.
  },
  -- Sharp room detail when zoomed in. Above `threshold` the map draws room
  -- outlines, doors and platforms from the exported map outlines
  -- (developer/assets/minimap/layout_vectors.lua) into square pages, and shows
  -- the overview image wherever a page is not ready yet.
  pages = {
    threshold = 1.5, -- Screen pixels per overview pixel above which detail pages replace the overview.
    page_px = 256,   -- Width and height of one page texture, in pixels.
    cache_max = 24,  -- Pages kept at once (at most 24); each 256 px page uses 256 KB of texture memory.
    per_frame = 1,   -- Pages drawn per frame while the map is open; more fills faster but costs frame time.
    ring = 1,        -- Extra pages drawn around the visible area, so short pans need no redraw.
  },
  player_offset_px = { x = 0, y = 8 },
  -- Player map stamps: reminders players leave on the world map, such as a
  -- star, '!' or '?'. On the open map, X (or the X key) opens the palette at
  -- the cursor; left and right choose a stamp, A places it and B cancels. X on
  -- a stamp removes it. Stamps are saved with the slot, in the room they were
  -- placed in, so moving a room in the Layout Editor moves its stamps too.
  -- Game Settings > Map > Player markers edits `enabled` and `max`.
  stamps = {
    enabled = true, -- Let players place stamps. Off hides them and keeps the saved ones.
    max = 32,       -- Most stamps one save can hold (0 to 64).
    -- The palette, in order. `id` is saved with each stamp: keep an id once
    -- players may have used it. A stamp whose id leaves this list is hidden,
    -- not deleted. `glyph` is the character drawn on the world map (the
    -- minimap draws a box in `color`). `label` names it under the cursor.
    -- Glyphs and labels are translated like other creator text.
    icons = {
      { id = "star",     glyph = "*", color = v4(1.00, 0.85, 0.20, 1.0), label = "Star" },
      { id = "alert",    glyph = "!", color = v4(1.00, 0.35, 0.30, 1.0), label = "Important" },
      { id = "question", glyph = "?", color = v4(0.40, 0.75, 1.00, 1.0), label = "Mystery" },
      { id = "blocked",  glyph = "#", color = v4(0.75, 0.75, 0.80, 1.0), label = "Blocked path" },
      { id = "treasure", glyph = "$", color = v4(0.35, 0.95, 0.45, 1.0), label = "Treasure" },
      { id = "health",   glyph = "+", color = v4(1.00, 0.50, 0.75, 1.0), label = "Health" },
    },
  },
}

return M
