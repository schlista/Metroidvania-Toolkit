-- mvtk/core/settings.lua
-- Comprehensive settings management system
-- Handles audio, graphics, and gameplay settings. Input bindings are stored
-- independently by mvtk.core.input_bindings.

local Util = require "mvtk.core.util"
local C = require "mvtk.core.constants"
local SafeRequire = require "mvtk.core.safe_require"
-- Literal require: Settings loads at boot, before any script registers Gamefeel,
-- so a named load stayed nil all session (AUDIT_BUILD_BUNDLING row 2).
local Gamefeel = require "mvtk.core.gamefeel"
local SettingsDefaults = Util.require_config("developer.config.settings_defaults")
local Config = Util.require_config("developer.config.resolved_config")
local RuntimeSettings = Util.require_config("developer.config.runtime_settings")
local SavePaths = require "mvtk.core.save_paths"
local Migrations = require "mvtk.core.save_migrations"
local ViewPolicy = require "mvtk.render.view_policy"
local Pause = require "mvtk.core.pause"
local Accessibility = require "mvtk.ui.accessibility"
local AccessibilityConfig = require "developer.config.accessibility"
-- volume_groups.lua requires this module, so its name stays in a variable here
-- (no require cycle for Bob); audio_controller.script requires it literally.
local VOLUME_GROUPS_MODULE = "mvtk.audio.volume_groups"
-- Assist reads Settings; keep this direction named to avoid Bob's literal require cycle.
-- build_deps -> multiplier_sources supplies its literal boot-world dependency.
local ASSIST_MODULE = "mvtk.player.assist"

local M = {}
local SAVE_KEY = 'mvtk_settings'

-- Default settings structure
local _s = {}
-- Session state stays outside the serialized preferences, including across load().
local focus_muted = false
local preference_defaults = {}
local accessibility_revision, accessibility_cache
local accessibility_generation = 0

-- section() copies creator overrides, so only refresh when the authored revision changes.
local function accessibility_config()
  local revision = RuntimeSettings and RuntimeSettings.revision and RuntimeSettings.revision()
  if not accessibility_cache or accessibility_revision ~= revision then
    accessibility_cache = RuntimeSettings and RuntimeSettings.section
      and RuntimeSettings.section("accessibility", AccessibilityConfig) or AccessibilityConfig
    accessibility_revision = revision
    accessibility_generation = accessibility_generation + 1
  end
  return accessibility_cache
end

local function base_defaults()
  local defaults
  if type(SettingsDefaults) == "table" and next(SettingsDefaults) then
    defaults = Util.deep_merge({}, SettingsDefaults)
  else
    defaults = {
    audio = {
      master_volume = 0.8,
      music_volume = 0.7,
      sfx_volume = 0.8,
      muted = false,
      mute_when_unfocused = false,
    },
    graphics = {
      window_mode = "windowed",  -- "windowed", "fullscreen_windowed", "fullscreen"
      vsync = true,
      show_fps = false,
      brightness = 1.0, -- Picture multiplier, 0.5-1.5.
      view_fill = "auto", -- Follow the creator until a permitted player choice is saved.
    },
    gameplay = {
      camera_shake = true,
      pause_on_focus_loss = true,
      pause_on_controller_disconnect = true,
      rumble = true,
      damage_numbers = false,
      number_options = {
        enemies = true,
        player  = true,
        heal    = true,
        crit    = true,
      },
      auto_save = true,
      icon_theme = "xbox",
    },
    language = 'auto',
    }
  end
  defaults.accessibility = Util.deep_merge({}, accessibility_config().player)
  defaults.accessibility.toggles = Util.deep_merge({}, accessibility_config().toggles or {})
  local captions = accessibility_config().captions or {}
  defaults.accessibility.captions = {enabled = captions.enabled == true, background = captions.background or "dim"}
  return defaults
end

_s = base_defaults()

function M.load()
  accessibility_generation = accessibility_generation + 1
  _s = base_defaults()
  -- Creator overrides supply defaults; explicit player preferences win below.
  if RuntimeSettings and RuntimeSettings.get_game_settings then
    local wizard = RuntimeSettings.get_game_settings() or {}
    for _, key in ipairs({ "camera_shake", "damage_numbers", "icon_theme", "pause_on_focus_loss", "pause_on_controller_disconnect" }) do
      if wizard[key] ~= nil then _s.gameplay[key] = wizard[key] end
    end
    if wizard.mute_when_unfocused ~= nil then _s.audio.mute_when_unfocused = wizard.mute_when_unfocused end
  end
  for _, key in ipairs({ "pause_on_focus_loss", "pause_on_controller_disconnect" }) do
    preference_defaults[key] = _s.gameplay[key] ~= false
  end
  preference_defaults.mute_when_unfocused = _s.audio.mute_when_unfocused == true
  local ok, data = pcall(sys.load, SavePaths.path(SAVE_KEY))
  local had_settings = ok and type(data) == "table" and next(data) ~= nil
  local reason
  if ok then data, reason = Migrations.preferences(data) end
  M.last_save_error = not ok and "unreadable_settings" or reason
  if ok and type(data) == 'table' then
    -- Load only current top-level settings. Controller bindings have their own
    -- versioned store and unknown settings sections are intentionally ignored.
    for key, default_value in pairs(_s) do
      local saved_value = data[key]
      if type(default_value) == "table" and type(saved_value) == "table" then
        _s[key] = Util.deep_merge(default_value, saved_value)
      elseif saved_value ~= nil and type(saved_value) == type(default_value) then
        _s[key] = saved_value
      end
    end
  end

  _s.graphics.brightness = M.get_brightness()
  _s.graphics.view_fill = M.get_view_fill()
  ViewPolicy.set_view_fill(_s.graphics.view_fill)
  require("mvtk.core.localization").set_language(M.get_language())
  return _s, had_settings and data ~= nil
end

function M.save()
  -- Checkpoint is already loaded whenever a test session exists. Avoid a
  -- literal dependency cycle through boot-time settings/provider imports.
  local checkpoint = package.loaded["mvtk.core.checkpoint"]
  if checkpoint and checkpoint.is_save_suspended_by("dev_tools") then return false, "save_suspended:dev_tools" end
  local path = SavePaths.path(SAVE_KEY)
  local readable, previous = pcall(sys.load, path)
  local supported, reason
  if readable then supported, reason = Migrations.preferences(previous) end
  if not readable or not supported then
    M.last_save_error = reason or "unreadable_settings"
    return false, M.last_save_error
  end
  if next(previous) and previous.version == nil then
    local backup = path .. "_pre_upgrade_v0"
    local read_ok, saved = pcall(sys.load, backup)
    if not read_ok then return false, "Cannot read settings backup" end
    if not next(saved) then
      local wrote, result = pcall(sys.save, backup, previous)
      if not wrote or result == false then return false, "Cannot preserve settings backup" end
      local checked, copy = pcall(sys.load, backup)
      if not checked or not Migrations.equal(previous,copy) then return false, "Settings backup verification failed" end
    elseif not Migrations.preferences(saved) then
      return false, "Unsupported settings backup; original preserved"
    end
  end
  local payload = Migrations.copy(_s)
  payload.version = 1
  local ok, err = pcall(sys.save, path, payload)
  ok = ok and err ~= false
  M.last_save_error = not ok and tostring(err) or nil
  return ok, M.last_save_error
end

-- SaveManager and the menu use the same live preferences, including after reload.
function M.data() return _s end

-- Keep the saved preference (including auto), separate from the resolved language.
function M.get_language() return _s.language end

function M.get(path)
  -- path like "gameplay.rumble"
  return Util.get_nested(_s, path)
end

function M.set(path, value)
  local parts = {}
  for seg in tostring(path or ''):gmatch('[^%.]+') do table.insert(parts, seg) end
  if #parts == 0 then return end
  local ref = _s
  for i=1,#parts-1 do
    local seg = parts[i]
    ref[seg] = ref[seg] or {}
    ref = ref[seg]
  end
  ref[parts[#parts]] = value
  if parts[1] == "accessibility" or path == "gameplay.camera_shake" then
    accessibility_generation = accessibility_generation + 1
  end
end

function M.apply_gamefeel()
  M.apply_accessibility()
  if not Gamefeel then return end
  local gp = _s.gameplay or {}
  Gamefeel.rumble_enabled = (gp.rumble ~= false)
  Gamefeel.enable_damage_numbers(gp.damage_numbers and true or false)
  if gp.number_options then Gamefeel.set_number_options(gp.number_options) end
end

function M.get_accessibility()
  return Accessibility.resolve(_s.accessibility, accessibility_config(), (_s.gameplay or {}).camera_shake)
end

-- Includes creator-default refreshes as well as saved player changes.
function M.accessibility_revision()
  accessibility_config()
  return accessibility_generation
end

function M.apply_accessibility()
  accessibility_generation = accessibility_generation + 1
  local view = M.get_accessibility()
  Gamefeel.shake_scale = view.shake_scale
  Gamefeel.enabled = view.shake_scale > 0
  Pause.set_hitstop_scale(view.freeze_scale)
  require(ASSIST_MODULE).apply()
end

function M.set_accessibility(key, value)
  M.set("accessibility." .. key, value)
  M.apply_accessibility()
  return M.save()
end

-- Apply audio settings to the engine
function M.apply_audio()
  local audio = _s.audio or {}
  local Audio = Util.require_module("mvtk.audio.audio")

  local function clamp01(v)
    return math.max(0, math.min(1, tonumber(v) or 0))
  end
  -- Only groups sound.get_groups confirms are set (volume_groups.lua): a
  -- group exists once a .sound naming it loads.
  local VolumeGroups = require(VOLUME_GROUPS_MODULE)
  local active_groups = VolumeGroups.active_groups()
  local function safe_set_group_gain(group_hash, value)
    VolumeGroups.set_active_gain(active_groups, group_hash, clamp01(value))
  end

  -- There is no guaranteed engine-level "master" group in game.project.
  -- Apply master as a multiplier to concrete groups instead.
  local master = (audio.muted or focus_muted) and 0 or clamp01(audio.master_volume or 0.8)

  -- Apply music volume (master * music)
  local music = audio.muted and 0 or (master * clamp01(audio.music_volume or 0.7))
  safe_set_group_gain(C.AUDIO_GROUP.MUSIC, music)
  if Audio and Audio.set_volume then
    Audio.set_volume("music", music)
  end

  -- Apply SFX volume (master * sfx)
  local sfx = audio.muted and 0 or (master * clamp01(audio.sfx_volume or 0.8))
  safe_set_group_gain(C.AUDIO_GROUP.SFX, sfx)
  if Audio and Audio.set_volume then
    Audio.set_volume("sfx", sfx)
  end

  -- Ambient follows master because there is no dedicated ambient slider yet.
  safe_set_group_gain(C.AUDIO_GROUP.AMBIENT, master)
  if Audio and Audio.set_volume then
    Audio.set_volume("ambient", master)
  end
end

-- Apply graphics settings to the engine
function M.apply_graphics()
  local gfx = _s.graphics or {}
  ViewPolicy.set_view_fill(M.get_view_fill())
  -- Debug disabled: apply_graphics inputs

  -- Load defos extension. quiet() because defos is a third-party native
  -- extension that's only present when the user installs it; absence is normal.
  local defos_ok, defos = SafeRequire.quiet("defos", "mvtk.core.settings.apply_graphics")
  -- Debug disabled: defos availability
  -- Debug disabled: defos load status

  if not defos_ok or not defos then
    return
  end

  -- Apply window mode
  if gfx.window_mode then
    local mode = gfx.window_mode
    -- Debug disabled: window mode

    if mode == "fullscreen" then
      -- Fullscreen exclusive mode
      defos.set_fullscreen(true)

    elseif mode == "fullscreen_windowed" then
      -- Fullscreen windowed mode (window at native resolution with title bar)
      -- Exit exclusive fullscreen first
      defos.set_fullscreen(false)

      -- Get primary display size
      local displays = defos.get_displays()
      local primary_display = displays and displays[1]
      local screen_width = 1920
      local screen_height = 1080

      if primary_display then
        screen_width = primary_display.bounds.width
        screen_height = primary_display.bounds.height
      end

      -- Set window to cover entire screen
      defos.set_window_size(0, 0, screen_width, screen_height)

    else  -- "windowed"
      -- Regular windowed mode at a fixed 1080p target (clamped to the display)
      -- Exit fullscreen
      defos.set_fullscreen(false)

      -- Get primary display size
      local displays = defos.get_displays()
      local primary_display = displays and displays[1]
      local screen_width = 1920
      local screen_height = 1080

      if primary_display then
        screen_width = primary_display.bounds.width
        screen_height = primary_display.bounds.height
      end

      -- Target 1080p to avoid ultrawide stretching; clamp down if screen is smaller
      local target_w = (Config.window and Config.window.target_width) or 1920
      local target_h = (Config.window and Config.window.target_height) or 1080
      local scale = math.min(screen_width / target_w, screen_height / target_h, 1.0)
      local win_width = math.floor(target_w * scale + 0.5)
      local win_height = math.floor(target_h * scale + 0.5)

      -- Center the window on screen
      local win_x = math.floor((screen_width - win_width) / 2)
      local win_y = math.floor((screen_height - win_height) / 2)

      defos.set_window_size(win_x, win_y, win_width, win_height)
      -- Debug disabled: windowed size log
    end
  end

  -- VSync handling - engine system message (documented socket is @system:,
  -- not the render script, which silently ignored it).
  if gfx.vsync ~= nil then
    local vsync_value = gfx.vsync and 1 or 0
    msg.post("@system:", "set_vsync", { swap_interval = vsync_value })
  end

  -- Show FPS is handled by the HUD system reading M.get("graphics.show_fps")
end

-- Apply all settings
function M.apply_all()
  M.apply_audio()
  M.apply_graphics()
  M.apply_gamefeel()
  M.apply_accessibility()
end

-- Convenience functions for audio
function M.get_master_volume()
  return M.get("audio.master_volume") or 0.8
end

function M.set_master_volume(volume, opts)
  M.set("audio.master_volume", math.max(0, math.min(1, volume)))
  M.apply_audio()
  if not (opts and opts.save == false) then M.save() end
end

function M.get_music_volume()
  return M.get("audio.music_volume") or 0.7
end

function M.set_music_volume(volume, opts)
  M.set("audio.music_volume", math.max(0, math.min(1, volume)))
  M.apply_audio()
  if not (opts and opts.save == false) then M.save() end
end

function M.get_sfx_volume()
  return M.get("audio.sfx_volume") or 0.8
end

function M.set_sfx_volume(volume, opts)
  M.set("audio.sfx_volume", math.max(0, math.min(1, volume)))
  M.apply_audio()
  if not (opts and opts.save == false) then M.save() end
end

function M.is_muted()
  return M.get("audio.muted") or false
end

function M.set_muted(muted)
  M.set("audio.muted", muted)
  M.apply_audio()
  M.save()
end

function M.toggle_mute()
  M.set_muted(not M.is_muted())
end

local function boolean_preference(section, key, fallback)
  local value = M.get(section .. "." .. key)
  if type(value) == "boolean" then return value end
  if preference_defaults[key] ~= nil then return preference_defaults[key] end
  return fallback
end

function M.get_pause_on_focus_loss() return boolean_preference("gameplay", "pause_on_focus_loss", true) end
function M.get_pause_on_controller_disconnect() return boolean_preference("gameplay", "pause_on_controller_disconnect", true) end
function M.get_mute_when_unfocused() return boolean_preference("audio", "mute_when_unfocused", false) end
function M.set_pause_on_focus_loss(on) M.set("gameplay.pause_on_focus_loss", on == true); M.save() end
function M.set_pause_on_controller_disconnect(on) M.set("gameplay.pause_on_controller_disconnect", on == true); M.save() end
function M.set_mute_when_unfocused(on)
  M.set("audio.mute_when_unfocused", on == true)
  if not on then M.set_focus_muted(false) end
  M.save()
end
function M.is_focus_muted() return focus_muted end
function M.set_focus_muted(on)
  on = on == true
  if focus_muted == on then return end
  focus_muted = on
  M.apply_audio()
end

-- Convenience functions for graphics
function M.get_brightness()
  local value = M.get("graphics.brightness")
  if type(value) ~= "number" or value ~= value then return 1 end
  return math.max(0.5, math.min(1.5, value))
end

function M.set_brightness(value, opts)
  M.set("graphics.brightness", value)
  M.set("graphics.brightness", M.get_brightness())
  -- The picture script reads live state; preserve the player's window size.
  if not (opts and opts.save == false) then M.save() end
end

function M.get_view_fill()
  local value = M.get("graphics.view_fill")
  return (value == "expand" or value == "letterbox") and value or "auto"
end

function M.set_view_fill(value)
  M.set("graphics.view_fill", (value == "expand" or value == "letterbox") and value or "auto")
  -- A view-only choice must not reapply the native window mode/target size.
  ViewPolicy.set_view_fill(M.get_view_fill())
  M.save()
end

-- Window mode functions
function M.get_window_mode()
  return M.get("graphics.window_mode") or "windowed"
end

function M.set_window_mode(mode)
  -- Valid modes: "windowed", "fullscreen_windowed", "fullscreen"
  if mode == "windowed" or mode == "fullscreen_windowed" or mode == "fullscreen" then
    M.set("graphics.window_mode", mode)
    -- Debug disabled: window mode set
    M.apply_graphics()
    M.save()
  else
  end
end

function M.cycle_window_mode()
  local current = M.get_window_mode()
  local modes = { "windowed", "fullscreen_windowed", "fullscreen" }
  for i, m in ipairs(modes) do
    if m == current then
      local next_mode = modes[(i % #modes) + 1]
      M.set_window_mode(next_mode)
      return
    end
  end
end

function M.get_vsync()
  return M.get("graphics.vsync")
end

function M.set_vsync(enabled)
  M.set("graphics.vsync", enabled)
  M.apply_graphics()
  M.save()
end

function M.get_show_fps()
  return M.get("graphics.show_fps") or false
end

function M.set_show_fps(enabled)
  M.set("graphics.show_fps", enabled)
  M.save()
end

-- Keyboard and controller remapping share mvtk.core.input_bindings.
-- Settings owns presentation and delegates persistence to that service.
local function get_input_bindings(context)
  local ok, InputBindings = SafeRequire("mvtk.core.input_bindings", context)
  if ok then return InputBindings end
  return nil
end

function M.get_control_rows()
  local InputBindings = get_input_bindings("mvtk.core.settings.get_control_rows")
  local rows = {}
  if not InputBindings then return rows, {} end
  local all_rows = InputBindings.remappable()
  for _, row in ipairs(all_rows) do
    if row.player and (not row.optional or InputBindings.row_visible(row.id)) then
      rows[#rows + 1] = row
    end
  end
  -- The second result lets GUI code disable authored nodes for hidden rows
  -- before the first opening, without maintaining a second list of row ids.
  return rows, all_rows
end

function M.get_control_bindings()
  local InputBindings = get_input_bindings("mvtk.core.settings.get_control_bindings")
  local bindings = {}
  if not InputBindings then return bindings end
  for _, row in ipairs(M.get_control_rows()) do
    bindings[row.id] = InputBindings.get_controller_binding(row.action)
  end
  return bindings
end

function M.get_control_keys()
  local InputBindings = get_input_bindings("mvtk.core.settings.get_control_keys")
  local keys = {}
  if not InputBindings then return keys end
  for _, row in ipairs(M.get_control_rows()) do
    keys[row.id] = InputBindings.get_keyboard_binding(row.action)
  end
  return keys
end

-- Build hashes lazily from this service's current allowlist. Hashes cannot be
-- converted back to names in a release build. No new module-load dependency.
function M.control_key_name(action_id)
  local InputBindings = get_input_bindings("mvtk.core.settings.control_key_name")
  if not InputBindings then return nil end
  if M._key_source ~= InputBindings then
    M._key_source, M._key_names = InputBindings, {}
    for input in pairs(InputBindings.CURRENT_INPUTS) do
      if InputBindings.capturable_key(input) then M._key_names[hash(input)] = input end
    end
  end
  return M._key_names[action_id]
end

function M.set_control_slot(id, input, slot)
  local InputBindings = get_input_bindings("mvtk.core.settings.set_control_slot")
  if not InputBindings then return false end
  local selected
  local labels = {}
  for _, row in ipairs(InputBindings.remappable()) do
    labels[row.action] = row.label
  end
  for _, row in ipairs(M.get_control_rows()) do
    if row.id == id then selected = row end
  end
  if not selected or not selected[slot] then return false end
  if input ~= nil and (slot == "keyboard" and not InputBindings.capturable_key(input)
      or slot == "controller" and not InputBindings.CONTROLLER_INPUTS[input]) then return false end
  local setter = slot == "keyboard" and InputBindings.set_keyboard_binding or InputBindings.set_controller_binding
  local getter = slot == "keyboard" and InputBindings.get_keyboard_binding or InputBindings.get_controller_binding
  local owner = input and InputBindings.owner_of(input)
  if owner == selected.action then owner = nil end
  local previous = getter(selected.action)
  local original = InputBindings.get(selected.action)
  local other = owner and InputBindings.get(owner)
  -- Clear the occupied slot first so every intermediate bind still validates.
  if owner then
    local cleared, reason = setter(owner, nil)
    if not cleared then return false, reason end
  end
  local ok, reason = setter(selected.action, input)
  if ok and owner then ok, reason = setter(owner, previous) end
  if ok and not InputBindings.save() then
    ok, reason = false, { key = "controls.save_failed" }
  end
  if not ok then
    setter(selected.action, nil)
    if owner then setter(owner, nil) end
    InputBindings.bind(selected.action, original)
    if owner then InputBindings.bind(owner, other) end
    return false, reason
  end
  return true, owner and { key = "controls.swapped", params = { action = labels[owner] and { text = labels[owner] } or { key = "list.missing_name" } } } or nil
end

function M.set_control_binding(id, button)
  return M.set_control_slot(id, button, "controller")
end

function M.set_control_key(id, key)
  return M.set_control_slot(id, key, "keyboard")
end

function M.reset_control_bindings()
  local InputBindings = get_input_bindings("mvtk.core.settings.reset_control_bindings")
  return InputBindings and InputBindings.reset() or false
end

function M.reset_to_defaults(category)
  -- Reset specific category or all if nil
  if category then
    _s[category] = Util.deep_merge({}, M.get_defaults()[category])
  else
    _s = Util.deep_merge({}, M.get_defaults())
  end
  M.apply_all()
  M.save()
end

-- Controller icon theme helpers
local VALID_ICON_THEMES = {xbox = true, playstation = true, switch = true}

function M.get_icon_theme()
  local theme = M.get("gameplay.icon_theme")
  return VALID_ICON_THEMES[theme] and theme or "xbox"
end

function M.set_icon_theme(theme)
  if VALID_ICON_THEMES[theme] then
    M.set("gameplay.icon_theme", theme)
  else
    M.set("gameplay.icon_theme", "xbox")
  end
  M.save()
end

function M.toggle_icon_theme()
  local order = {"xbox", "playstation", "switch"}
  local current = M.get_icon_theme()
  for i, t in ipairs(order) do
    if t == current then
      M.set_icon_theme(order[(i % #order) + 1])
      return
    end
  end
  M.set_icon_theme("xbox")
end

function M.get_defaults()
  -- Return a copy of the original default settings, with the creator's
  -- Game Settings focus defaults that load() resolved, so Reset restores them.
  local defaults = base_defaults()
  for _, key in ipairs({ "pause_on_focus_loss", "pause_on_controller_disconnect" }) do
    if preference_defaults[key] ~= nil then defaults.gameplay[key] = preference_defaults[key] end
  end
  if preference_defaults.mute_when_unfocused ~= nil then
    defaults.audio.mute_when_unfocused = preference_defaults.mute_when_unfocused
  end
  return defaults
end

return M
