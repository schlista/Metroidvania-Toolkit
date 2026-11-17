-- Journal membership differs from completion: only the tab's filters apply.
-- Census.entries already restricts this view to the published layout.
local M = {}

function M.nonblank(value)
  return type(value) == "string" and value:find("%S") ~= nil
end

function M.new(deps)
  deps = deps or {}
  local catalog = {}
  local function census() return deps.census or require "mvtk.world.census" end
  function catalog.definition(entry)
    return (deps.collectible_types or require "developer.config.collectible_types")[entry.type] or {}
  end
  function catalog.entries(category)
    local out = {}
    for _, entry in ipairs(census().entries()) do
      local def = catalog.definition(entry)
      if (category == "relic" and entry.kind == "item" and def.category == "relic" and def.show_in_collection ~= false)
        or (category == "lore" and ((entry.kind == "lore" and M.nonblank(entry.id))
          or (entry.kind == "item" and def.category == "lore"))) then
        out[#out + 1] = entry
      end
    end
    return out
  end
  function catalog.found(entry) return census().state(entry) end
  function catalog.totals(category)
    local found, entries = 0, catalog.entries(category)
    for _, entry in ipairs(entries) do if catalog.found(entry) then found = found + 1 end end
    return { found = found, total = #entries }
  end
  function catalog.progress(category)
    local totals = catalog.totals(category)
    return { forms = { one = "journal.progress_one", other = "journal.progress_other" }, count = totals.total,
      params = { found = totals.found, total = totals.total } }
  end
  return catalog
end

return M
