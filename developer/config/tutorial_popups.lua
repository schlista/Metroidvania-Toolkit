-- developer/config/tutorial_popups.lua
-- Tutorial popup definitions and triggers.
-- Each entry: id key -> { title/body text, trigger_flag to set, condition.event it listens for, position hint }.

return {
    popups = {
        -- First health drop while a flask charge or potion is usable.
        healing = {
            title = "Healing",
            body = "Press {input:quick_use} to heal. Hold it to switch quick items.",
            trigger_flag = "healing_popup_shown", -- Once per save slot.
            condition = { event = "heal_hint" }, -- Raised by the healing feature.
        },
        -- First health drop while the channel heal is usable; creator text is collected for translation.
        channel_healing = {
            title = "Healing",
            body = "Hold {input:quick_use} to heal. Hit enemies to fill your energy.",
            trigger_flag = "channel_heal_popup_shown", -- Once per save slot.
            condition = { event = "channel_heal_hint" }, -- Channel mode never raises heal_hint.
        },
        jump = {
            title = "Jump",
            body = "Use your Jump action to clear obstacles.",
            trigger_flag = "first_jump_shown", -- Flag set after showing (prevents repeats)
            condition = { event = "first_jump" }, -- Raised from input_controller on first jump
        },
        dash = {
            title = "Dash",
            body = "Use your Slide / Air Dash action. Hold it after a ground slide to run when Dash is unlocked.",
            trigger_flag = "first_dash_shown", -- Prevent repeats
            condition = { event = "first_dash" }, -- Shared Slide / Air Dash press in input_controller
        },
        map = {
            title = "Map",
            body = "Open the map to see explored rooms.",
            trigger_flag = "map_popup_shown", -- Prevent repeats
            condition = { event = "opened_map" }, -- From input_controller when map opened
            position = "top", -- Optional: "top"|"center"|"bottom"
        },
    }
}
