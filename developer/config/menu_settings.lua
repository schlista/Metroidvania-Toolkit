-- Shared list menus and navigation. Edit the scene for spacing and typography;
-- edit ui_theme.lua for colours. These inputs are independent of player remaps.
return {
  -- Pause-menu info when the controller in use disconnects; rendered through DisplayText.
  controller_disconnect_text = "Controller disconnected. Reconnect it or use the keyboard.",
  -- Physical action ids from developer/input/game.input_binding and the inputs
  -- allowlist in default_bindings.lua. Keep each id in only one command below.
  -- Order matters: prompts use the first keyboard and first controller entry.
  navigation = {
    -- Activate the selected row or accept a confirmation.
    confirm = { "key_enter", "key_space", "gamepad_rpad_down" },
    -- Return to the caller, or close a book opened directly.
    back = { "key_backspace", "key_m", "gamepad_rpad_right", "gamepad_back" },
    -- Close directly, without returning to the caller.
    close = { "key_escape", "key_p", "gamepad_start" },
    -- Move to the preceding or following selectable row; selection wraps.
    up = { "key_up", "key_w", "gamepad_lpad_up", "gamepad_lstick_up" },
    down = { "key_down", "key_s", "gamepad_lpad_down", "gamepad_lstick_down" },
    -- Move to the preceding or following page of rows.
    left = { "key_left", "key_a", "gamepad_lpad_left", "gamepad_lstick_left" },
    right = { "key_right", "key_d", "gamepad_lpad_right", "gamepad_lstick_right" },
    -- Switch between enabled tabs in a book.
    tab_prev = { "key_q", "gamepad_lshoulder" },
    tab_next = { "key_e", "gamepad_rshoulder" },
    -- Select with touch or a mouse button. Wheel actions page the list; keep
    -- the wheel ids here when changing the click or touch inputs.
    pointer = { "touch", "click", "mouse_button_1", "mouse_wheel_up", "mouse_wheel_down" },
  },
  list = {
    -- Number of visible rows, from 1 to 12. Longer lists have multiple pages.
    page_size = 10,
    -- Default seconds to hold Confirm. Zero makes confirmation immediate;
    -- an individual row can supply its own hold duration.
    hold_to_confirm_seconds = 0,
    -- Seconds before a held stick starts repeating, then between repeats.
    -- Keys and digital controller buttons use the engine's repeated events.
    repeat_delay = 0.35,
    repeat_interval = 0.10,
    -- Minimum absolute stick value for a menu push (0 to 1). Digital inputs
    -- (keys, D-pad, buttons) are unchanged.
    stick_press_threshold = 0.5,
    -- A pushed stick direction counts as let go only at or below this value
    -- (0 to 1, no higher than stick_press_threshold). The gap stops a stick
    -- resting near the press point from moving the selection twice.
    stick_release_threshold = 0.3,
    -- Seconds to ignore the opposite direction after a fired push releases.
    -- Filters spring-back past centre; a reversal held longer is accepted.
    -- Zero disables this window. Uses real time even while gameplay is paused.
    stick_rebound_seconds = 0.15,
    -- Sound ids from the audio configuration. Use an empty string for silence.
    sfx = { move = "ui_move", confirm = "ui_confirm", back = "ui_back", error = "ui_back" },
  },
  -- Default for a plain screen whose provider does not choose its own pause.
  pause_while_open = true,
  books = {
    -- true always pauses; false keeps the world running. 'with_gear' pauses
    -- the entire session if any enabled tab other than Items exists on open.
    inventory = { title = "Inventory", pause = "with_gear" },
    -- The title and pause rule also apply to a book with only one enabled tab.
    -- show_records lets a records provider decide whether to show its tab.
    journal = { title = "Journal", pause = true, show_records = true },
    -- Opened from the title screen's EXTRAS entry, so no game runs behind it.
    extras = { title = "Extras", pause = false },
  },
}
