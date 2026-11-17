-- developer/config/default_bindings.lua
-- Default high-level game action bindings mapped to low-level input actions
-- defined in `developer/input/game.input_binding`. Game Settings > Controls overrides
-- keys, buttons and hold times without rewriting this file. Player remaps stay on top.

local M = {
  -- Persistable low-level actions emitted by game.input_binding. Keep this
  -- allowlist synchronized when adding or renaming a physical input action.
  inputs = {
    "key_b", "key_f", "key_h", "key_l", "key_n", "key_o", "key_t",
    "key_0", "key_1", "key_2", "key_3", "key_4", "key_5", "key_6", "key_7", "key_8", "key_9",
    "key_delete", "key_backspace", "text", "marked_text",
    "editor_rescan", "editor_save", "editor_load", "editor_export",
    "key_lctrl", "key_rctrl", "key_lshift", "key_rshift",
    "mouse_button_1", "mouse_button_2", "mouse_button_3",
    "mouse_wheel_up", "mouse_wheel_down", "click", "touch",
    "key_tab",
    "gamepad_connected", "gamepad_disconnected",
    "gamepad_lpad_left", "gamepad_lpad_right", "gamepad_lpad_up", "gamepad_lpad_down",
    "gamepad_rpad_left", "gamepad_rpad_right", "gamepad_rpad_up", "gamepad_rpad_down",
    "gamepad_lshoulder", "gamepad_rshoulder", "gamepad_ltrigger", "gamepad_rtrigger",
    "gamepad_lstick_left", "gamepad_lstick_right", "gamepad_lstick_up", "gamepad_lstick_down",
    "gamepad_lstick_click",
    "gamepad_rstick_left", "gamepad_rstick_right", "gamepad_rstick_up", "gamepad_rstick_down",
    "gamepad_rstick_click", "gamepad_start", "gamepad_back", "gamepad_guide",
    "key_escape", "key_p",
    "key_up", "key_down", "key_left", "key_right",
    "key_w", "key_s", "key_a", "key_d",
    "key_m", "key_z", "key_y", "key_x", "key_c", "key_enter",
    "key_f1", "key_f2", "key_f3", "key_f4", "key_f5", "key_f6", "key_f7", "key_f9", "key_f12",
    "key_g", "key_r", "key_space", "key_v", "key_j", "key_k", "key_i", "key_q", "key_u", "key_e",
  },

  -- Controls rows, in display order; every action has exactly one row.
  -- id: stable name other features and text use to refer to the row.
  -- label: the name players see. player = true lists the row in
  -- Pause > Settings > Controls; player = false keeps it off that page.
  -- optional = true rows appear only once the feature using them turns
  -- them on. keyboard/controller: which capture slots the row offers; the
  -- buttons themselves come from actions below. owner: the system that
  -- defines the action ("core" for the built-in actions). The camera
  -- stick, Escape for Pause and menu navigation stay fixed. A taken key
  -- or button swaps with its previous owner. Keyboard capture excludes
  -- movement keys, Escape, R and the F1-F7 debug keys.
  remappable = {
    { id = "jump", action = "JUMP", label = "Jump", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "dash", action = "SLIDE", label = "Dash", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "attack", action = "LIGHT_MELEE", label = "Attack", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "special", action = "HEAVY_MELEE", label = "Special", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "ranged", action = "RANGED", label = "Ranged Attack", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "interact", action = "INTERACT", label = "Interact", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "map", action = "MINIMAP_TOGGLE", label = "Minimap", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "inventory", action = "INVENTORY_TOGGLE", label = "Inventory", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "parry", action = "PARRY", label = "Parry", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "grapple", action = "GRAPPLE", label = "Grapple", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "world_map", action = "WORLD_MAP_TOGGLE", label = "World Map", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "marker", action = "MAP_MARKER", label = "Map Marker", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "quick_use", action = "QUICK_USE", label = "Heal / Item", player = true, optional = false, owner = "healing", keyboard = true, controller = true },
    { id = "loadout_cycle", action = "LOADOUT_CYCLE", label = "Next Weapon", player = true, optional = true, owner = "weapons", keyboard = true, controller = true },
    { id = "backdash", action = "BACKDASH", label = "Backdash", player = true, optional = true, owner = "core", keyboard = true, controller = true },
    { id = "ground_pound", action = "GROUND_POUND", label = "Ground Pound", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "morph", action = "MORPH_TOGGLE", label = "Compact Form", player = true, optional = true, owner = "core", keyboard = true, controller = true },
    { id = "potion", action = "POTION", label = "Potion", player = false, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "settings", action = "SETTINGS_TOGGLE", label = "Settings", player = false, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "pause", action = "PAUSE_TOGGLE", label = "Pause", player = true, optional = false, owner = "core", keyboard = true, controller = true },
    { id = "camera_up", action = "CAMERA_UP", label = "Camera Up", player = false, optional = false, owner = "core", keyboard = false, controller = false },
    { id = "camera_down", action = "CAMERA_DOWN", label = "Camera Down", player = false, optional = false, owner = "core", keyboard = false, controller = false },
  },

  -- Per-action tap/hold thresholds in seconds (0.05 to 5); player remaps do not store timing.
  hold_seconds = { QUICK_USE = 0.35 }, -- Hold to step quick items, or to heal under channel healing; repeat is in healing.quick.

  -- Controller budget: sixteen of seventeen digital buttons are bound.
  -- D-pad Right / G: Quick Use. L3 / C: Loadout cycle.
  -- Blink: press Dash again during an air dash or a ground slide
  -- gamepad_guide belongs to OS/Steam overlays and is never a default;
  -- key_r stays unallocated. Each capturable key and physical button has one owner.
  -- Prefer context reuse and tap/hold variants; chords are not supported.

  actions = {
    -- Movement is handled directly in input_controller for now.

    -- Core actions
    JUMP              = { "key_space", "gamepad_rpad_down" },
    SLIDE             = { "key_v", "gamepad_rtrigger" },       -- slide / air dash
    PARRY             = { "key_q", "gamepad_ltrigger" },
    GRAPPLE           = { "key_tab", "gamepad_lshoulder" },    -- Tab / left shoulder
    BACKDASH          = { },
    LIGHT_MELEE       = { "key_j", "gamepad_rpad_left" },
    HEAVY_MELEE       = { "key_k", "key_y", "gamepad_rpad_up" },
    GROUND_POUND      = { },
    RANGED            = { "key_i", "gamepad_rpad_right" },
    MORPH_TOGGLE      = { },
    INTERACT          = { "key_e", "key_u", "gamepad_rshoulder" },

    -- Utility / UI
    MINIMAP_TOGGLE    = { "key_m", "gamepad_rstick_click" }, -- M / R3 cycles map display
    WORLD_MAP_TOGGLE  = { "gamepad_lpad_up" },       -- D-pad Up for world map
    INVENTORY_TOGGLE  = { "gamepad_lpad_left" },     -- D-pad Left for inventory
    MAP_MARKER        = { "key_f12", "gamepad_lpad_down" }, -- Screenshot marker
    LOADOUT_CYCLE = { "key_c", "gamepad_lstick_click" },
    QUICK_USE         = { "key_g", "gamepad_lpad_right" }, -- G / D-pad Right: heal or item.
    POTION            = { }, -- Old instant-potion path; never bind alongside QUICK_USE.

    -- Camera look (analog right-stick direction values)
    CAMERA_UP         = { "gamepad_rstick_up" },
    CAMERA_DOWN       = { "gamepad_rstick_down" },

    -- Settings
    SETTINGS_TOGGLE   = { },

    -- Pause
    PAUSE_TOGGLE      = {
      "key_escape", "key_p",
      "gamepad_start", "gamepad_back",
    },
  }
}

return M
