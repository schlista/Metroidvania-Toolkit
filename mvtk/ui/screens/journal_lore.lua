-- The list controller hands read payloads to the existing token-based reader.
local M = {}

function M.new(deps)
  deps = deps or {}
  local provider = {}
  local function collection() return require("mvtk.ui.screens.journal_collection").new(deps) end
  function provider.title() return { key = "journal.lore" } end
  function provider.enabled() return #collection().entries("lore") > 0 end
  function provider.header_right() return collection().progress("lore") end
  function provider.rows()
    local catalog, out, rows = collection(), {}, {}
    local flags = deps.flags or require "mvtk.core.flags"
    local nonblank = require("mvtk.ui.screens.journal_collection").nonblank
    for _, entry in ipairs(catalog.entries("lore")) do
      local def, found = catalog.definition(entry), catalog.found(entry)
      local id = nonblank(entry.lore_id) and entry.lore_id or def.lore_id or entry.id
      local saved_title = flags.get("lore_title_" .. id)
      local title = nonblank(saved_title) and saved_title or (nonblank(entry.title) and entry.title or def.name or "Lore")
      local source_title = nonblank(saved_title) and saved_title
        or (nonblank(entry.title) and entry.title or (nonblank(def.name) and def.name or ""))
      local saved_category = flags.get("lore_category_" .. id)
      local category = nonblank(saved_category) and saved_category
        or (nonblank(entry.category) and entry.category or def.category or "lore")
      rows[#rows + 1] = { category = category, title = title, row = {
        id = entry.id, label = found and ((nonblank(saved_title) or nonblank(entry.title) or nonblank(def.name)) and title or { key = "journal.lore" }) or { key = "journal.unknown" }, state = found and "available" or "unknown",
        selectable = found and true or false,
        read = found and { title = source_title, text = flags.get("lore_text_" .. id) or "", category = category, lore_id = id } or nil,
      } }
    end
    table.sort(rows, function(a, b)
      if a.category ~= b.category then return a.category < b.category end
      if a.title ~= b.title then return a.title < b.title end
      return a.row.id < b.row.id
    end)
    local category
    for _, item in ipairs(rows) do
      if item.category ~= category then
        category = item.category
        out[#out + 1] = { id = "category:" .. category, kind = "section", label = { key = require("developer.config.ui_text")["journal.category." .. category]
            and ("journal.category." .. category) or "journal.category.other" }, selectable = false }
      end
      out[#out + 1] = item.row
    end
    return out
  end
  return provider
end

local default = M.new()
default.new = M.new
return default
