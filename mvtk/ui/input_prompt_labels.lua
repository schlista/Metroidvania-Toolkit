-- Pure physical-input names and icons shared by prompts and creator tools.
local M = {}
local PAD = {
  gamepad_rpad_down = { { "A", "xbox_a" }, { "Cross", "ps_cross" }, { "B", "switch_b" } },
  gamepad_rpad_right = { { "B", "xbox_b" }, { "Circle", "ps_circle" }, { "A", "switch_a" } },
  gamepad_rpad_left = { { "X", "xbox_x" }, { "Square", "ps_square" }, { "Y", "switch_y" } },
  gamepad_rpad_up = { { "Y", "xbox_y" }, { "Triangle", "ps_triangle" }, { "X", "switch_x" } },
  gamepad_lshoulder = { { "LB", "xbox_lb" }, { "L1", "ps_l1" }, { "L", "switch_l" } },
  gamepad_rshoulder = { { "RB", "xbox_rb" }, { "R1", "ps_r1" }, { "R", "switch_r" } },
  gamepad_ltrigger = { { "LT", "xbox_lt" }, { "L2", "ps_l2" }, { "ZL", "switch_zl" } },
  gamepad_rtrigger = { { "RT", "xbox_rt" }, { "R2", "ps_r2" }, { "ZR", "switch_zr" } },
  gamepad_start = { { "Menu", "xbox_menu" }, { "Options", "ps_options" }, { "+", "switch_plus" } },
  gamepad_back = { { "View", "xbox_view" }, { "Share", "ps_share" }, { "-", "switch_minus" } },
  gamepad_guide = { { "Guide" }, { "PS" }, { "Home" } },
  gamepad_lstick_click = { { "LS" }, { "L3" }, { "L-Stick" } },
  gamepad_rstick_click = { { "RS" }, { "R3" }, { "R-Stick" } },
}
local THEMES = { xbox = 1, playstation = 2, switch = 3 }
local KEYS = {
  key_pause = "input.key_pause",
  key_caps_lock = "input.key_caps_lock",
  key_insert = "input.key_insert",
  key_end = "input.key_end",
  key_home = "input.key_home",
  key_page_up = "input.key_page_up",
  key_page_down = "input.key_page_down",
  editor_export = "input.editor_export",
  editor_load = "input.editor_load",
  editor_save = "input.editor_save",
  editor_rescan = "input.editor_rescan",
  marked_text = "input.marked_text",
  text = "input.text",
  touch = "input.touch",
  click = "input.click",
  mouse_wheel_down = "input.mouse_wheel_down",
  mouse_wheel_up = "input.mouse_wheel_up",
  mouse_button_3 = "input.mouse_button_3",
  key_delete = "input.key_delete",
  key_tab = "input.tab", key_space = "input.space", key_enter = "input.enter",
  key_esc = "input.esc", key_escape = "input.esc", key_lshift = "input.shift", key_rshift = "input.shift",
  key_lctrl = "input.ctrl", key_rctrl = "input.ctrl", key_lalt = "input.alt", key_ralt = "input.alt",
  key_backspace = "input.backspace", key_up = "input.up", key_down = "input.down",
  key_left = "input.left", key_right = "input.right",
  mouse_button_1 = "input.left_click", mouse_button_left = "input.left_click",
  mouse_button_2 = "input.right_click", mouse_button_right = "input.right_click",
}

local function english(key, params)
  local text = require("developer.config.ui_text")[key]
  return (text:gsub("{([%w_]+)}", function(name) return tostring((params or {})[name] or "{" .. name .. "}") end))
end

function M.pad_label(id, theme, ui)
  ui = ui or english
  local row = PAD[id]
  if row then return row[THEMES[theme or "xbox"] or 1][1] end
  if id == "gamepad_connected" then return ui("input.connected") end
  if id == "gamepad_disconnected" then return ui("input.disconnected") end
  local direction = tostring(id):match("^gamepad_lpad_(%a+)$")
  local directions = { up = "input.up", down = "input.down", left = "input.left", right = "input.right" }
  if directions[direction] then return ui("input.pad_direction", { direction = ui(directions[direction]) }) end
  if tostring(id):match("^gamepad_lstick_") then return ui("input.left_stick") end
  if tostring(id):match("^gamepad_rstick_") then return ui("input.right_stick") end
  local number = tostring(id):match("^gamepad_button_(%d+)$")
  if number then return ui("input.pad_button", { number = tonumber(number) }) end
  return ui("input.unknown")
end

function M.pad_icon(id, theme)
  local row = PAD[id]
  return row and row[THEMES[theme or "xbox"] or 1][2] or nil
end

function M.key_label(id, ui)
  ui = ui or english
  if KEYS[id] then return ui(KEYS[id]) end
  local single = tostring(id):match("^key_([a-z0-9])$")
  if single then return ui("input.character", { key = single:upper() }) end
  local number = tostring(id):match("^key_f(%d+)$")
  if number then return ui("input.function_key", { number = tonumber(number) }) end
  return ui("input.unknown")
end

function M.label(id, theme, ui)
  if tostring(id):match("^gamepad_") then return M.pad_label(id, theme, ui) end
  return M.key_label(id, ui)
end


function M.has_theme(id) return PAD[id] ~= nil end

return M
