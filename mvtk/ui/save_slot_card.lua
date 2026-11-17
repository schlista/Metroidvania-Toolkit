-- mvtk/ui/save_slot_card.lua
-- The two text lines and region colour of one save slot card on the boot save
-- slot screen (developer/ui/menus/boot_save_slot_select.gui_script).
--
--   SaveSlotCard.build(meta, opts) -> { line1 = text, line2 = text, swatch = colour or nil }
--
-- meta is the slot's save meta (Checkpoint.list_slots); its `summary` holds ids
-- and integers written by mvtk/game/save_summary.lua. Names are resolved here,
-- when the card is drawn, through the caller's DisplayText: saves hold no text.
-- opts:
--   display       DisplayText (render, ui)
--   localization  Localization (plural_form)
--   saves         game_config progression.saves (show_summary, summary_fields)
--   cycle         New Game+ cycle of the slot (0 when none)
--   region_info   optional region lookup, default Regions.info
--
-- A save without a summary, or show_summary = false, shows the play time and
-- last-saved lines the screen always showed. Unknown summary field ids are
-- skipped. The New Game+ cycle joins line 2 whenever it is above 0.

local Regions = require "mvtk.world.regions"

local M = {}

M.FIELDS = { "completion", "playtime", "bosses", "abilities", "level", "ending", "last_saved" }
M.DEFAULT_FIELDS = { "completion", "playtime", "bosses" }

function M.playtime(seconds, display, localization)
    seconds = tonumber(seconds or 0) or 0
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then
        local hours = display.ui(localization.plural_form({ one = "save.hours_one", other = "save.hours_other" }, h), { hours = h })
        local minutes = display.ui(localization.plural_form({ one = "save.remaining_minutes_one", other = "save.remaining_minutes_other" }, m), { minutes = m })
        return display.ui("save.hours_minutes", { hours = hours, minutes = minutes })
    end
    return display.ui(localization.plural_form({ one = "save.minutes_one", other = "save.minutes_other" }, m), { minutes = m })
end

function M.date(timestamp)
    if not timestamp or timestamp == 0 then return "" end
    local ok, date = pcall(os.date, "*t", timestamp)
    if ok and type(date) == "table" then
        return string.format("%04d-%02d-%02d %02d:%02d", date.year, date.month, date.day, date.hour, date.min)
    end
    return ""
end

local function count(value)
    value = tonumber(value)
    if not value then return nil end
    return math.floor(value)
end

local function plural(display, localization, one, other, n, name)
    return display.ui(localization.plural_form({ one = one, other = other }, n), { [name] = n })
end

-- One rendered field, or nil when the save has no value for it.
local function field_text(id, meta, summary, display, localization)
    if id == "completion" then
        local percent = count(summary.percent)
        return percent and display.ui("save.summary_percent", { percent = percent }) or nil
    elseif id == "playtime" then
        return M.playtime(meta.playtime_s, display, localization)
    elseif id == "bosses" then
        local n = count(summary.bosses)
        return n and plural(display, localization, "save.summary_bosses_one", "save.summary_bosses_other", n, "count") or nil
    elseif id == "abilities" then
        local n = count(summary.abilities)
        return n and plural(display, localization, "save.summary_abilities_one", "save.summary_abilities_other", n, "count") or nil
    elseif id == "level" then
        local n = count(summary.level)
        return n and display.ui("save.summary_level", { level = n }) or nil
    elseif id == "ending" then
        return (summary.ending ~= nil and summary.ending ~= false and summary.ending ~= "") and display.ui("save.summary_ending") or nil
    elseif id == "last_saved" then
        local date = M.date(meta.last_saved)
        return date ~= "" and date or nil
    end
    return nil
end

-- Today's lines: play time, then the last-saved date (with the cycle).
local function plain_card(meta, opts)
    local display = opts.display
    local cycle = tonumber(opts.cycle) or 0
    local date = M.date(meta.last_saved)
    local line2 = ""
    if cycle > 0 then
        line2 = display.ui("save.meta_cycle", { cycle = cycle, date = date })
    elseif date ~= "" then
        line2 = display.ui("save.last_saved", { date = date })
    end
    return {
        line1 = display.ui("save.playtime", { time = M.playtime(meta.playtime_s, display, opts.localization) }),
        line2 = line2,
    }
end

function M.build(meta, opts)
    meta = type(meta) == "table" and meta or {}
    opts = opts or {}
    local saves = type(opts.saves) == "table" and opts.saves or {}
    local summary = meta.summary
    if type(summary) ~= "table" or saves.show_summary == false then
        return plain_card(meta, opts)
    end
    local display, localization = opts.display, opts.localization
    local info = summary.region ~= nil and (opts.region_info or Regions.info)(summary.region) or nil
    local line1
    if info and info.name ~= "" then
        line1 = display.render(info.name)
    else
        line1 = display.ui("save.summary_unknown_region")
    end
    local parts = {}
    local fields = type(saves.summary_fields) == "table" and saves.summary_fields or M.DEFAULT_FIELDS
    for _, id in ipairs(fields) do
        local text = field_text(id, meta, summary, display, localization)
        if text and text ~= "" then parts[#parts + 1] = text end
    end
    local cycle = tonumber(opts.cycle) or 0
    if cycle > 0 then parts[#parts + 1] = display.ui("save.summary_cycle", { cycle = cycle }) end
    local color = info and info.color
    return {
        line1 = line1,
        line2 = table.concat(parts, display.ui("save.summary_separator")),
        swatch = (type(color) == "table" or type(color) == "userdata") and color or nil,
    }
end

return M
