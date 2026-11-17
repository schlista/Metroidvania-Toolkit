-- Per-placement discovery; no manager or engine state loads with the registry.
local M = {}

function M.new(deps)
  deps = deps or {}
  local provider = {}
  local function collection() return require("mvtk.ui.screens.journal_collection").new(deps) end
  function provider.title() return { key = "journal.relics" } end
  function provider.enabled() return #collection().entries("relic") > 0 end
  function provider.header_right() return collection().progress("relic") end
  function provider.rows()
    local catalog, out = collection(), {}
    local entries = catalog.entries("relic")
    table.sort(entries, function(a, b)
      local ad, bd = catalog.definition(a), catalog.definition(b)
      local an, bn = ad.collection_number or 0, bd.collection_number or 0
      if an ~= bn then return an < bn end
      local at, bt = ad.name or a.type, bd.name or b.type
      if at ~= bt then return at < bt end
      return a.id < b.id
    end)
    for _, entry in ipairs(entries) do
      local def, found = catalog.definition(entry), catalog.found(entry)
      out[#out + 1] = { id = entry.id, label = found and (type(def.name) == "string" and def.name:find("%S") and def.name or { key = "list.missing_name" }) or { key = "journal.unknown" },
        state = found and "available" or "unknown", selectable = found and true or false,
        detail = found and def.description or nil }
    end
    return out
  end
  return provider
end

local default = M.new()
default.new = M.new
return default
