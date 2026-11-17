-- Pure feature-HUD geometry. Rectangles use design coordinates, Y upwards;
-- minimap top/bottom and column height are distances down from the design top.
local Model = require "mvtk.core.creator_settings_model"
local HudLayout = require "mvtk.ui.hud_layout"
local M = {}

function M.entry(block, layout, overrides)
    return Model.merge(Model.copy(block.default_entry), HudLayout.entry(layout, block.layout_key, overrides))
end

-- Ceiling is in final design pixels, independent of authored/HUD scaling.
function M.scaled_width(width, scale, maximum)
    return math.min(width * scale, maximum or math.huge)
end

function M.rectangle(entry, size, width, height, scale, max_width)
    local w, h = M.scaled_width(size.w, scale, max_width), size.h * scale
    local x, y = HudLayout.top_left(entry, width, height, w, h)
    return { left = x, right = x + w, top = y, bottom = y - h }
end

function M.overlaps(a, b)
    return a.left < b.right and b.left < a.right and a.bottom < b.top and b.bottom < a.top
end

-- Authored node extents are supplied by the caller (resource census or editor),
-- keeping file access and engine APIs outside this reusable warning geometry.
function M.core_rectangles(layout, theme, sizes, width, height, shown)
    local records, result = {}, {}
    for key, size in pairs(sizes) do
        local entry = HudLayout.entry(layout, key)
        local theme_key = "show_" .. key:gsub("_bar$", "")
        records[key] = { entry = entry, size = size, shown = entry.enabled ~= false and entry.visible ~= false
            and (theme.visibility or {})[theme_key] ~= false and (shown or {})[key] ~= false }
    end
    local kept, freed = {}, 0
    for _, key in ipairs((layout.global or {}).collapse_column or {}) do
        if records[key] and records[key].entry.anchor == "top_left" then kept[#kept + 1] = key end
    end
    if (layout.global or {}).collapse_hidden ~= false then
        for i, key in ipairs(kept) do
            local record = records[key]
            local original_y = record.entry.offset.y
            record.entry.offset.y = original_y + freed
            if not record.shown and kept[i + 1] then
                freed = freed + original_y - records[kept[i + 1]].entry.offset.y
            end
        end
    end
    for key, record in pairs(records) do
        if record.shown then
            if key=="interact_hint" and record.entry.max_height then
                result[key]=HudLayout.message_rectangle(record.entry,width,height)
            else result[key] = M.rectangle(record.entry, record.size, width, height, (layout.global or {}).scale or 1) end
        end
    end
    return result
end

-- A hidden entry frees its authored distance to the next registered entry,
-- just as the shared HUD's collapse column does. Offsets never scale.
function M.pack(records, order, scale)
    local entries, column, freed, bottom = {}, {}, 0, 0
    if not order then
        -- Copied older layouts have no column settings. Registered defaults
        -- still establish a top-to-bottom column and reserve minimap space.
        order = {}
        for id, record in pairs(records) do
            if record.entry.anchor == "top_right" and not record.entry.follow_minimap then order[#order + 1] = id end
        end
        table.sort(order, function(a, b)
            local ay, by = (records[a].entry.offset or {}).y or 0, (records[b].entry.offset or {}).y or 0
            if ay == by then return a < b end
            return ay > by
        end)
    end
    for _, slot in ipairs(order or {}) do
        local id = type(slot) == "table" and slot.id or slot
        local record = records[id]
        -- Unimplemented column owners still have a reserved slot, never nodes
        -- or a toggle. Their absence frees the same distance as hidden data.
        if not record and type(slot) == "table" then
            record = { block = { id = id }, entry = { anchor = "top_right", offset = slot.offset }, shown = false }
        end
        if record and record.entry.anchor == "top_right" then column[#column + 1] = record end
    end
    for i, record in ipairs(column) do
        local entry = Model.copy(record.entry)
        entry.offset = entry.offset or {}
        entry.offset.y = (entry.offset.y or 0) + freed
        -- Offsets themselves stay unscaled. Enlarged shown blocks can need
        -- more room than the authored slots; push the next one below them.
        if record.shown then entry.offset.y = -math.max(-entry.offset.y, bottom) end
        entries[record.block.id] = entry
        if record.shown then
            bottom = math.max(bottom, -entry.offset.y + record.size.h * scale)
        elseif column[i + 1] then
            freed = freed + ((record.entry.offset or {}).y or 0)
                - ((column[i + 1].entry.offset or {}).y or 0)
        end
    end
    return entries, bottom
end

function M.minimap(cfg, column_height, gap, shown)
    local size, offset = cfg.size_px or {}, cfg.panel_offset_px or {}
    local margin = cfg.margin_px or 32
    local distance = margin
    if column_height > 0 then distance = math.max(margin, column_height + gap) end
    local top = distance - (offset.y or 0)
    return { shown = shown and cfg.enabled ~= false, top = top,
        bottom = top + (size.h or 200), width = size.w or 200,
        right_margin = margin - (offset.x or 0) }
end

function M.below_minimap(entry, rect, gap, top_floor)
    local result = Model.copy(entry)
    result.offset = result.offset or {}
    local column_top = rect.shown and (rect.bottom + gap) or rect.top
    result.offset.y = -math.max(column_top, top_floor or entry.top_floor or 0)
    return result
end
return M
