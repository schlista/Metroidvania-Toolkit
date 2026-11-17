-- Render source text at the screen boundary; data and saves keep the source.
local M = {}
local InputPrompts = require "mvtk.ui.input_prompts"
local Localization = require "mvtk.core.localization"

-- Prompts are also loaded by the editor. Inject runtime translation here so
-- their editor path needs only the English vocabulary.
if InputPrompts.set_ui then
  InputPrompts.set_ui(function(key, params) return Localization.format(Localization.ui(key), params) end)
end

function M.render(text, opts)
  return InputPrompts.expand(Localization.format(Localization.tr(tostring(text or "")), opts and opts.params), opts)
end

function M.ui(key, params, opts)
  return InputPrompts.expand(Localization.format(Localization.ui(key), params), opts)
end

function M.revision()
  return tostring(Localization.revision()) .. ":" .. tostring(InputPrompts.revision())
end

local function append_ids(out, ids, theme)
  if type(ids) == "string" then ids = { ids } end
  for _, id in ipairs(ids or {}) do out[#out + 1] = InputPrompts.label(id, theme) end
end

local function buttons(part, command, device, theme, opts)
  if part.button_key then return M.ui(part.button_key, part.params, opts) end
  if part.button then
    local value = part.button
    if type(value) == "table" then value = value[device] end
    return value and M.render(value, opts) or nil
  end
  local out = {}
  local kind = device == "gamepad" and "pad" or "key"
  append_ids(out, command[kind], theme)
  append_ids(out, part[kind], theme)
  if #out > 0 then return table.concat(out, "/") end
end

function M.legend(parts, opts)
  opts = opts or {}
  local device = opts.device or InputPrompts.device()
  if device == "active" then device = InputPrompts.device() end
  local theme = opts.theme or InputPrompts.theme()
  local out = {}
  for _, part in ipairs(parts) do
    local command = part.command and InputPrompts.menu_inputs(part.command) or {}
    local button
    if device == "both" then
      local key, pad = buttons(part, command, "keyboard", theme, opts), buttons(part, command, "gamepad", theme, opts)
      button = key and pad and (key == pad and key or key .. " / " .. pad) or key or pad
    else button = buttons(part, command, device, theme, opts) end
    if button and button ~= "" then
      out[#out + 1] = button .. M.ui("legend.binding_separator")
        .. (part.text_key and M.ui(part.text_key, part.params, opts) or M.render(part.text, opts))
    end
  end
  return table.concat(out, opts.separator or M.ui("legend.part_separator"))
end

return M
