-- Gameplay-only window policy; window callbacks never call GUI component APIs.
local WindowEvents = require "mvtk.core.window_events"
local Settings = require "mvtk.core.settings"
local Pause = require "mvtk.core.pause"
local InputCtl = require "mvtk.rooms.input_controller"
local GameManager = require "mvtk.game.game_manager"
local PauseModel = require "mvtk.ui.pause_menu_model"
local MenuSettings = require "developer.config.menu_settings"
local M = {}

PauseModel.add_info("controller", 100, function(ctx)
  return ctx.reason == "controller" and MenuSettings.controller_disconnect_text or ""
end)

local function request_pause(reason)
  if not GameManager.is_playing() or Pause.get() then return end
  if InputCtl.get_blocked() then
    local screen = InputCtl.get_auto_pause_screen()
    if reason ~= "focus" or (screen ~= "list_menu" and screen ~= "lore_popup") then return end
    -- Close both: a list menu may currently own a nested lore reader. Their
    -- ordered close messages retain ownership until Pause acquires it.
    msg.post("main:/list_menu_gui#list_menu", "close_list_menu", { reason = "auto_pause" })
    msg.post("main:/lore_popup_gui#lore_popup", "close_lore_popup", { preserve_blocked = true })
  end
  msg.post("main:/pause_gui#pause", "menu_open", { reason = reason })
end

WindowEvents.subscribe(function(event)
  if event == window.WINDOW_EVENT_FOCUS_LOST or event == window.WINDOW_EVENT_ICONIFIED then
    if Settings.get_mute_when_unfocused() then Settings.set_focus_muted(true) end
    if Settings.get_pause_on_focus_loss() then request_pause("focus") end
  elseif event == window.WINDOW_EVENT_FOCUS_GAINED or event == window.WINDOW_EVENT_DEICONIFIED then
    Settings.set_focus_muted(false)
  end
end)

InputCtl.on_active_gamepad_lost = function(index)
  if Settings.get_pause_on_controller_disconnect() then request_pause("controller") end
end

function M.uninstall() Settings.set_focus_muted(false) end
return M
