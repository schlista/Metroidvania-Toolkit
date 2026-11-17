-- Button names and atlas ids shared by screen prompts. No GUI dependencies.
local function labels() return require "mvtk.ui.input_prompt_labels" end

local function english(key, params)
  local text = require("developer.config.ui_text")[key]
  return (text:gsub("{([%w_]+)}", function(name) return tostring((params or {})[name] or "{" .. name .. "}") end))
end

-- Dependencies may be injected for headless consumers. Default requires stay
-- inside calls so merely loading this module never loads Settings or bindings.
local function new(deps)
  deps = deps or {}
  local M = { new = new }
  local ui = deps.ui or english
  -- DisplayText supplies the game renderer; editor Controls keeps English and
  -- never loads the runtime translation registry. Isolated instances own theirs.
  function M.set_ui(renderer) ui = renderer end
  local function pair(key, pad)
    if key and pad then return ui("input.pair", { key = key, pad = pad }) end
    return key or pad or ui("input.unbound")
  end
  local warned = {}
  local revision, last_theme, last_device, last_bindings = 0

  function M.device()
    local controller = deps.input_controller or require "mvtk.rooms.input_controller"
    return controller.get_last_device()
  end

  function M.revision()
    local bindings = deps.input_bindings or require "mvtk.core.input_bindings"
    local theme, device = M.theme(), M.device()
    local binding_revision = bindings.revision and bindings.revision() or 0
    if theme ~= last_theme or device ~= last_device or binding_revision ~= last_bindings then
      revision = revision + 1
      last_theme, last_device, last_bindings = theme, device, binding_revision
    end
    return revision
  end

  -- Menu navigation is creator-configured and independent of player remaps.
  -- Older screens combine Back and Close; list books keep them separate.
  function M.menu_inputs(command)
    local nav = deps.menu_nav or require "mvtk.ui.menu_nav"
    return nav.legacy_inputs(command)
  end

  function M.menu_matches(command, id)
    local nav = deps.menu_nav or require "mvtk.ui.menu_nav"
    return nav.legacy_matches(command, id)
  end

  function M.theme()
    local settings = deps.settings or require "mvtk.core.settings"
    return settings.get_icon_theme()
  end

  function M.pad_label(id, theme)
    local shared = labels()
    return shared.pad_label(id, theme or (shared.has_theme(id) and M.theme()), ui)
  end

  function M.pad_icon(id, theme)
    local shared = labels()
    return shared.pad_icon(id, theme or (shared.has_theme(id) and M.theme()))
  end

  function M.key_label(id) return labels().key_label(id, ui) end

  function M.label(id, theme)
    if tostring(id):match("^gamepad_") then return M.pad_label(id, theme) end
    return M.key_label(id)
  end

  -- Keep this callable: authored-text tokens use the same row/action resolver.
  function M.resolve(name)
    local bindings = deps.input_bindings or require "mvtk.core.input_bindings"
    local lower = tostring(name or ""):lower()
    for _, row in ipairs(bindings.remappable and bindings.remappable() or {}) do
      if row.id == lower then return row.action end
    end
    return lower:upper()
  end

  function M.action_label(name, opts)
    opts = opts or {}
    local bindings = deps.input_bindings or require "mvtk.core.input_bindings"
    local action = M.resolve(name)
    local key, pad
    for _, id in ipairs(bindings.get(action)) do
      if not id:match("^gamepad_") then key = M.key_label(id); break end
    end
    local pad_id = bindings.get_controller_binding(action)
    if pad_id then pad = M.pad_label(pad_id, opts.theme) end
    local device = opts.device or "active"
    if device == "active" then
      device = M.device()
    end
    if device == "both" then return pair(key, pad) end
    if device == "gamepad" then return pad or ui("input.unbound") end
    return key or ui("input.unbound")
  end

  -- A physical pair uses nav_label(key_id, pad_id, theme). A row/action uses
  -- nav_label(name, opts), with both devices shown by default.
  function M.nav_label(key_id, pad_id, theme)
    if type(pad_id) == "table" or (pad_id == nil and key_id
        and not tostring(key_id):match("^key_") and not tostring(key_id):match("^mouse_")) then
      local opts = {}
      for key, value in pairs(type(pad_id) == "table" and pad_id or {}) do opts[key] = value end
      opts.device = opts.device or "both"
      return M.action_label(key_id, opts)
    end
    return pair(key_id and M.key_label(key_id), pad_id and M.pad_label(pad_id, theme))
  end

  -- Build source text here; DisplayText remains the only expansion boundary.
  function M.token(row)
    return "{input:" .. tostring(row) .. "}"
  end

  function M.expand(text, opts)
    text = tostring(text or "")
    local start = text:find("{input:", 1, true)
    if not start then return text end
    local bindings = deps.input_bindings or require "mvtk.core.input_bindings"
    local actions = bindings.defaults().actions or {}
    local out, cursor = {}, 1
    while start do
      local finish = text:find("}", start, true)
      if not finish then break end
      out[#out + 1] = text:sub(cursor, start - 1)
      local token = text:sub(start, finish)
      local body = text:sub(start + 7, finish - 1)
      local name, modifier = body:match("^([a-z][a-z0-9_]*)(.*)$")
      if name and (modifier == "" or modifier == "|both") and actions[M.resolve(name)] then
        out[#out + 1] = M.action_label(name, {
          device = modifier == "|both" and "both" or (opts and opts.device or "active"),
          theme = opts and opts.theme,
        })
      else
        out[#out + 1] = token
        if not warned[token] then
          warned[token] = true
          local warn = deps.warn or print
          warn("[INPUT_PROMPTS] Unknown token: " .. token)
        end
      end
      cursor = finish + 1
      start = text:find("{input:", cursor, true)
    end
    out[#out + 1] = text:sub(cursor)
    return table.concat(out)
  end

  return M
end

return new()
