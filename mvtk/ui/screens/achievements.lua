-- Journal models keep creator source text and UI descriptions until display.
-- The static registry can load this provider without loading any runtime state.
local M = {}
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end
local function name(def) return nonblank(def.name) and def.name or { key = "list.missing_name" } end

function M.new(deps)
  deps = deps or {}
  local provider = {}
  local function achievements() return deps.achievements or require "mvtk.game.progression.achievements" end
  function provider.title() return { key = "journal.achievements" } end
  function provider.enabled() return achievements().settings().enabled == true end
  function provider.header_right()
    local cfg, saved = achievements().settings(), achievements().snapshot()
    local unlocked, total, hidden = 0, 0, 0
    for id, def in pairs(cfg.achievements or {}) do
      total = total + 1
      if saved.unlocked[id] ~= nil then unlocked = unlocked + 1
      elseif def.hidden then hidden = hidden + 1 end
    end
    local progress = { key = "journal.achievements_progress", params = { unlocked = unlocked, total = total } }
    if cfg.show_hidden_count ~= false then
      -- MenuText selects the plural through Localization.plural_form in the GUI.
      return { parts = { progress, { forms = { one = "journal.achievements_hidden_one",
        other = "journal.achievements_hidden_other" }, count = hidden, params = { count = hidden } } } }
    end
    return progress
  end
  function provider.rows()
    local cfg, saved = achievements().settings(), achievements().snapshot()
    local items, out = {}, {}
    for id, def in pairs(cfg.achievements or {}) do
      local unlocked = saved.unlocked[id] ~= nil
      local hidden = def.hidden and not unlocked
      local row = { id = id, label = hidden and { key = "journal.unknown" } or name(def),
        state = hidden and "unknown" or (unlocked and "completed" or "available"), selectable = not hidden }
      if not hidden then
        row.detail = { title = name(def), body = def.description }
        if unlocked then row.value = { key = "notice.achievement_unlocked" }
        elseif (def.trigger or {}).type == "event" then
          row.value = { key = "journal.achievement_progress", params = {
            count = math.min(saved.counters[id] or 0, def.trigger.count), target = def.trigger.count } }
        end
      end
      items[#items + 1] = { category = def.category, definition = def, row = row }
    end
    local function category_order(id) return ((cfg.categories or {})[id] or {}).order or math.huge end
    table.sort(items, function(a, b)
      local ac, bc = category_order(a.category), category_order(b.category)
      if ac ~= bc then return ac < bc end
      if a.category ~= b.category then return (a.category or "") < (b.category or "") end
      local ao, bo = a.definition.order or 0, b.definition.order or 0
      if ao ~= bo then return ao < bo end
      local an, bn = nonblank(a.definition.name) and a.definition.name or "", nonblank(b.definition.name) and b.definition.name or ""
      if an ~= bn then return an < bn end
      return a.row.id < b.row.id
    end)
    local previous
    for _, item in ipairs(items) do
      local category = (cfg.categories or {})[item.category]
      if category and item.category ~= previous then
        out[#out + 1] = { id = "category:" .. item.category, kind = "section", selectable = false, label = name(category) }
      end
      previous = item.category
      out[#out + 1] = item.row
    end
    return out
  end
  function provider.detail(_, row) return row.detail end
  return provider
end
local default = M.new()
default.new = M.new
return default
