-- Pure list/book controller. Context holds identities, never engine nodes.
local M = {}
local function selectable(row) return row and row.kind ~= "section" and row.selectable ~= false end

function M.new(opts)
  local registry = opts.registry or require "mvtk.ui.menu_registry"
  local settings = opts.settings or require("mvtk.ui.menu_nav").settings()
  local s = { tabs = {}, tab_index = 1, rows = {}, selected = nil, page = 1,
    page_size = math.max(1, math.min(12, settings.list.page_size)), status = "", book = opts.book,
    ctx = { context = opts.context, owner = opts.owner, screen = opts.screen, book = opts.book,
      token = opts.token, registry = registry, settings = settings } }
  local function call(name, ...)
    local fn = s.provider and s.provider[name]
    if not fn then return nil end
    local ok, value = pcall(fn, s.ctx, ...)
    if ok then return value end
    (opts.log or print)("[LIST_MENU] " .. name .. ": " .. tostring(value))
    s.status = { key = "list.entry_failed" }
  end
  function s.refresh()
    local id = s.rows[s.selected or 0] and s.rows[s.selected].id
    s.rows = call("rows") or {}
    s.selected = nil
    for i, row in ipairs(s.rows) do
      if selectable(row) and (not s.selected or row.id == id) then s.selected = i end
      if row.id == id and selectable(row) then break end
    end
    s.page = s.selected and math.ceil(s.selected / s.page_size) or 1
    s.confirm_step, s.hold = nil, nil
  end
  if opts.book then
    s.tabs = registry.tabs(opts.book, s.ctx)
    if #s.tabs == 0 then return nil, { key = "list.no_tabs" } end
    for i, tab in ipairs(s.tabs) do if tab.id == opts.tab then s.tab_index = i end end
    s.provider = s.tabs[s.tab_index].provider
  else
    s.provider = registry.screen(opts.screen)
    if not s.provider then return nil, { key = "list.unknown_screen" } end
  end
  local book = (settings.books or {})[opts.book] or {}
  if opts.book then s.pauses = book.pause else s.pauses = s.provider.pause end
  if s.pauses == "with_gear" then
    s.pauses = false
    for _, tab in ipairs(s.tabs) do if tab.id ~= "items" then s.pauses = true end end
  elseif s.pauses == nil then s.pauses = settings.pause_while_open end
  s.refresh()

  function s.move(delta)
    s.confirm_step, s.hold = nil, nil
    if #s.rows == 0 then return end
    local index = s.selected or (delta > 0 and 0 or 1)
    for _ = 1, #s.rows do
      index = (index - 1 + delta) % #s.rows + 1
      if selectable(s.rows[index]) then s.selected = index; s.page = math.ceil(index / s.page_size); return end
    end
  end
  function s.page_by(delta)
    local pages = math.max(1, math.ceil(#s.rows / s.page_size))
    s.page = (s.page - 1 + delta) % pages + 1
    s.selected, s.confirm_step, s.hold = nil, nil, nil
    for i = (s.page - 1) * s.page_size + 1, math.min(#s.rows, s.page * s.page_size) do
      if selectable(s.rows[i]) then s.selected = i; break end
    end
  end
  function s.select(index)
    local absolute = (s.page - 1) * s.page_size + index
    if selectable(s.rows[absolute]) then s.selected = absolute; s.confirm_step, s.hold = nil, nil; return true end
  end
  function s.tab(index)
    if not s.tabs[index] then return end
    s.tab_index, s.provider = index, s.tabs[index].provider
    s.rows, s.selected, s.status = {}, nil, ""
    s.refresh() -- Pausing was decided on open, never on tab switches.
  end
  local function apply(result)
    result = result or {}
    if result.status then s.status = result.status end
    if result.refresh then s.refresh() end
    return result
  end
  local function execute(row)
    if row.read then return { read = row.read, sfx = "confirm" } end
    local ok, result = pcall(function()
      if s.provider.on_confirm then return s.provider.on_confirm(s.ctx, row) end
      return {}
    end)
    if not ok then
      (opts.log or print)("[LIST_MENU] confirm: " .. tostring(result))
      return apply({ status = { key = "list.action_failed" }, sfx = "error" })
    end
    result = result or {}
    if not result.sfx then result.sfx = "confirm" end
    if result.delegate then result.row_id = row.id end
    return apply(result)
  end
  function s.confirm(action)
    if not action.pressed then return end
    local row = s.rows[s.selected or 0]
    if not row then return end
    if row.enabled == false then return apply({ status = row.disabled_reason or { key = "list.unavailable" }, sfx = "error" }) end
    if row.confirm and not s.confirm_step then
      s.confirm_step = { question = row.confirm, yes = false }
      return { sfx = "confirm" }
    elseif s.confirm_step then
      local yes = s.confirm_step.yes
      s.confirm_step = nil
      if not yes then return {} end
    end
    local duration = row.hold
    if duration == nil then duration = settings.list.hold_to_confirm_seconds end
    if duration > 0 then s.hold = { remaining = duration, row = row }; return {} end
    return execute(row)
  end
  function s.cancel_hold() s.hold = nil end
  function s.update(dt)
    if not s.hold then return end
    s.hold.remaining = s.hold.remaining - dt
    if s.hold.remaining <= 0 then
      local row = s.hold.row; s.hold = nil
      return execute(row)
    end
  end
  function s.command(command, action)
    action = action or { pressed = true }
    if command == "confirm" then return s.confirm(action) end
    if command == "close" then return { close = true, result = "closed", sfx = "back" } end
    if s.confirm_step then
      if command == "back" or command == "close" then s.confirm_step = nil
      elseif command == "left" or command == "right" or command == "up" or command == "down" then
        s.confirm_step.yes = not s.confirm_step.yes
      end
      return {}
    end
    if command == "back" or command == "close" then return { close = true, result = command == "back" and "back" or "closed", sfx = "back" } end
    if command == "up" or command == "down" then s.move(command == "up" and -1 or 1)
    elseif command == "left" or command == "right" then s.page_by(command == "left" and -1 or 1)
    elseif #s.tabs > 1 and (command == "tab_prev" or command == "tab_next") then
      s.tab((s.tab_index - 1 + (command == "tab_prev" and -1 or 1)) % #s.tabs + 1)
    end
    return { sfx = "move" }
  end
  function s.view()
    local rows, start = {}, (s.page - 1) * s.page_size
    for i = start + 1, math.min(#s.rows, start + s.page_size) do rows[#rows + 1] = s.rows[i] end
    local row = s.rows[s.selected or 0]
    local detail = row and call("detail", row)
    if type(detail) ~= "table" then detail = { title = row and (row.detail_title or row.label), body = detail or (row and row.detail) } end
    return { layout = #s.tabs > 1 and "tabbed" or "list", title = opts.book and book.title or call("title"),
      subtitle = call("subtitle"), header_right = call("header_right"), tabs = s.tabs, tab_index = s.tab_index,
      rows = rows, selected = s.selected and s.selected - start, detail = detail, status = s.status,
      page_text = { key = "list.page", params = { current = s.page, total = math.max(1, math.ceil(#s.rows / s.page_size)) } },
      confirm = s.confirm_step, prompts = { "confirm", "back", "tab_prev", "tab_next" } }
  end
  return s
end

return M
