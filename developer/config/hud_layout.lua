-- developer/config/hud_layout.lua
-- HUD element positioning and layout configuration
-- Developers can easily customize HUD placement by modifying this file
--
-- DEMO LAYOUT: Classic Metroidvania (Top-Left)
-- This is optimized for the Classic theme with comfortable spacing
-- Want to try other layouts? See developer/config/hud_layout_examples.lua

-- Position reference:
-- - anchor: "top_left", "top_right", "bottom_left", "bottom_right", "center"
-- - offset: {x, y} offset from anchor point (in pixels)
-- - For top/left anchors: positive values move right/down
-- - For bottom/right anchors: positive values move left/up

return {
  theme_preset = "authored", -- authored, classic, neon, minimal, retro or horror; HUD/prompt palette.
  -- Shared dark backing for toasts, prompts, contact hints and Saving off.
  -- Channels are red/green/blue/opacity, each from 0 to 1. Game Settings exposes
  -- these four values. An entry's optional plate_color table overrides them.
  -- Use "authored" instead of a colour table to use each GUI plate's editor
  -- colour, or set plate_color="authored" on just toast/interact_hint below.
  message_plate = { r = 0, g = 0, b = 0, a = 0.75 },
  tutorial = {
    bottom_top_offset = 280, -- Distance down from picture top for a "bottom" tutorial; above dialogue and message bands.
  },
  toast = {
    anchor = "bottom_center", -- Text and plate are centred on this anchor point.
    offset = { x = 0, y = 120 }, -- Keeps the original bottom-centre toast spot.
    text_scale = 1.857142857, -- 26 px type with the shipped 14 px font (readable capitals).
    text_color = { r = 1, g = 1, b = 1, a = 1 }, -- Text tint; channels from 0 to 1.
    opacity = 1, -- Text opacity, multiplied by text_color.a and the fade.
    -- Optional plate_color = { r=0, g=0, b=0, a=0.75 } overrides message_plate.
    padding = { x = 24, y = 12 }, -- Horizontal/vertical plate inset, in final design pixels.
    max_width = 848, -- Full plate width ceiling; text wraps inside the padding.
    max_height = 96, -- Full plate height ceiling; long text shortens. A font too tall for one line is capped to fit.
    fade_in = 0.12, -- Seconds to fade in; zero appears immediately.
    fade_out = 0.35, -- Seconds to fade out; zero disappears immediately.
    -- A shortened toast reserves Interact while its read-more marker shows.
    read_more = {
      enabled = true, -- False keeps the previous trimming without a marker or Interact claim.
      speed_px_per_second = 80, -- Smooth scroll speed in design pixels per second; finite and greater than zero.
    },
  },
  status_chips = {
    enabled = true, -- Enable transient player status chips in the feature HUD.
    anchor = "top_left", -- Position relative to the picture's top-left corner.
    offset = { x = 12, y = -380 }, -- Below the quick slot and goal; clears dialogue at HUD scales 0.5 to 2.
    size = { w = 200, h = 108 }, -- Four readable chips, stacked down the left edge.
    chip_step = { x = 0, y = -28 }, -- Distance between chip origins; 24 px cell plus 4 px gap.
    text_offset = { x = 6, y = -3 }, -- Text inset inside each authored chip background.
    visible = true, -- Game Settings > HUD and prompts > Show on screen > Status chips.
    max_chips = 4, -- One chip per effect, bounded to four (six live cloned nodes).
  },
  quick_item = {
    enabled = true, -- Enable the feature-HUD quick slot.
    anchor = "top_left", -- Same picture corner as the shared health bar.
    -- Below the shared HUD column; the readable label clears the tutorial
    -- and the area title even at HUD scale 2.
    offset = { x = 12, y = -220 },
    size = { w = 360, h = 36 }, -- Label plus the flask-pip row, in design pixels.
    pip_step = 18, -- Pip spacing in the scaled text root's local coordinates.
    pip_y = -22, -- Pip row below the 18 px label, in text-root coordinates.
    visible = true, -- Game Settings Quick item toggle.
    show_button = true, -- Show the active device's Quick Use prompt.
    separator = " | ", -- Separator while holding to step through owned items.
  },
  level_xp = {
    enabled = true, -- Enable the level label and XP progress bar.
    visible = true, -- Game Settings > HUD and prompts > Show on screen > Level and XP.
    anchor = "top_right", -- Position relative to the safe picture top-right.
    offset = { x = 16, y = -72 }, -- Column slot below the optional play timer.
    -- Final design-pixel ceiling, independent of HUD scale. At scale 2 this
    -- clears the fixed boss panel: 1920 - inset 16 - (panel right 1536 + gap 12).
    max_width = 356,
  },
  weapon = {
    enabled = true, -- Enable the equipped weapon block.
    visible = true, -- Game Settings > HUD and prompts > Show on screen > Weapon.
    anchor = "top_right", -- Safe picture top-right feature column.
    offset = { x = 16, y = -108 }, -- Between level/XP and power-up slots.
    max_width = 356, -- Final design pixels; clears the boss panel at HUD scale 2.
  },
  powerups = {
    enabled = true, -- Enable the temporary world-pickup countdown block.
    visible = true, -- Game Settings > HUD and prompts > Show on screen > Power-ups.
    anchor = "top_right", -- Safe picture top-right feature column.
    offset = { x = 16, y = -136 }, -- Below level and weapon slots when shown.
    max_width = 356, -- Final design pixels; clears the fixed boss panel at HUD scale 2.
  },
  trial = {
    enabled = true, -- Enable the active trial goal, countdown, clock and result.
    visible = true, -- Game Settings > HUD and prompts > Show on screen > Trial.
    anchor = "top_right", -- Safe picture top-right feature column.
    offset = { x = 16, y = -214 }, -- Below the power-up slot when shown.
    max_width = 356, -- Final design pixels; clears the boss panel at HUD scale 2.
    size = { w = 200, h = 48 }, -- Two 24 px rows before optional limit wrapping.
    line_height = 24, -- Room for an 18 px line and its vertical spacing.
    max_goal_height = 60, -- Trim wrapped limits here so the full column, map and notices fit at HUD scale 2.
  },
  area_title = {
    enabled = true, -- Enable region and landmark title cards (developer/config/biomes.lua names regions).
    visible = true, -- Game Settings > HUD and prompts > Show on screen > Area titles.
    anchor = "top_center", -- Centre of the safe picture's top edge.
    offset = { x = 0, y = -300 }, -- Below the tutorial box; clears every HUD panel at HUD scales 0.5 to 2.
    max_width = 440, -- Final design pixels; a long name is shortened to fit this width.
    -- When a region's card shows: "first_visit" (once per save) or "every_entry"
    -- (each time the player enters the region). A region's own title_card in
    -- biomes.lua wins. Game Settings > HUD and prompts > Area titles > When to show.
    mode = "first_visit",
    duration = 3, -- Fully visible seconds, excluding the fades. Game Settings > Area titles > Seconds shown.
    delay = 0.5, -- Seconds to wait after entering, so the room-arrival fade finishes first.
    fade_in = 0.4, -- Fade-in seconds; zero shows the card at once.
    fade_out = 0.6, -- Fade-out seconds; zero hides it at once.
  },
  goal = {
    enabled = true, -- Enable the current goal line (developer/config/goals.lua).
    visible = false, -- Game Settings > HUD and prompts > Show on screen > Goal.
    anchor = "top_left", -- Position relative to the safe picture's top-left corner.
    -- Below the shared HUD column. It clears the interact prompt, the core HUD
    -- and the boss, toast and tutorial panels at HUD scales 0.5 to 2.
    offset = { x = 12, y = -310 },
    size = { w = 360, h = 24 }, -- One readable 18 px line with vertical room.
    -- Final design-pixel width ceiling, independent of HUD scale. Longer goal
    -- titles are shortened to fit one line.
    max_width = 500,
  },
  countdown = {
    enabled = true, -- Enable the countdown clock (developer/config/countdowns.lua).
    visible = true, -- Game Settings > HUD and prompts > Show on screen > Countdown.
    anchor = "bottom_center", -- Centre of the safe picture's bottom edge.
    -- Up from the bottom edge: just above the toast band. It clears the core
    -- HUD and the toast, tutorial, dialogue and boss panels at HUD scales 0.5 to 2.
    offset = { x = 0, y = 180 },
    -- Final design-pixel width ceiling, independent of HUD scale. A long label
    -- is shortened to fit one line.
    max_width = 356,
    -- Clock colour once a countdown's warning time is reached (red, green, blue,
    -- alpha; 0 to 1). The clock uses its authored colour before that.
    warning_color = { r = 1, g = 0.35, b = 0.25, a = 1 },
  },
  play_timer = {
    enabled = true, -- Enable the feature HUD's in-game clock.
    visible = false, -- Game Settings > HUD and prompts > Show on screen > Play timer.
    anchor = "top_right", -- Position relative to the safe picture's top-right corner.
    offset = { x = 16, y = -44 }, -- Right inset and signed distance down from the top.
  },
  -- Gap in design pixels between shown feature blocks, the minimap and notices.
  -- Block heights follow global.scale; this gap, offsets and minimap size do not.
  column_gap = 12,
  -- Minimum notice distance from picture top, in unscaled design pixels.
  -- Reserve the full boss band even when the narrower notice clears it
  -- horizontally. Bottoms are y=1020 (boss_hp) and y=986 (boss band):
  -- 1080 - min(1020, 986) + column_gap (12) = 106.
  notices_top_floor = 106,
  -- Maximum final notice width in unscaled picture design pixels. Normal width
  -- is 400 * HUD scale until it reaches this ceiling; text wraps to the result.
  -- Notice right edge 1920 - inset 16 = 1904; toast right edge 1384:
  -- 1904 - (1384 + column_gap 12) = 508. The fully populated column can
  -- place notices beside the toast band at HUD scale 2; keep that gap too.
  notices_max_width = 508,
  -- Top-right slot order. Missing/hidden blocks free the distance to the next
  -- slot; registered entries supply their own merged offsets and anchor.
  -- These reservations create no nodes or toggles. Each owner adds its full
  -- entry and Show on screen toggle only when its feature lands.
  feature_column = {
    { id = "play_timer", offset = { x = 16, y = -44 } }, -- Time display slot.
    { id = "level_xp", offset = { x = 16, y = -72 } },   -- Level and progress slot.
    { id = "weapon", offset = { x = 16, y = -108 } },    -- Equipped weapon slot.
    { id = "powerups", offset = { x = 16, y = -136 } },  -- Timed effects slot.
    { id = "trial", offset = { x = 16, y = -214 } },     -- Active combat trial slot.
  },
  -- Milestone queue, below the minimap; never pushes the map. When the map is
  -- off, the panel moves up to its top, stopping at notices_top_floor.
  -- Not part of feature_column.
  notices = {
    enabled = true,           -- False routes new messages to instant toasts.
    visible = true,           -- Game Settings Notices toggle; false also uses toasts.
    anchor = "top_right",     -- Screen edge used for the horizontal position.
    offset = { x = 16, y = 0 }, -- Right inset; Y follows the minimap rectangle.
    follow_minimap = true,    -- False permits a custom anchor/offset instead.
    width = 400,             -- Panel width in design pixels, before HUD scale.
    max_height = 160,        -- Measured text is shortened to fit this height cap.
    duration = 2.5,          -- Fully visible seconds, excluding the fades.
    max_queue = 6,           -- Waiting messages; overflow drops the oldest waiting one.
    fade_in = 0.15,          -- Fade-in seconds; zero displays immediately.
    fade_out = 0.25,         -- Fade-out seconds; zero hides immediately.
  },
  -- Global HUD settings
  global = {
    scale = 1,               -- Uniform element scale; anchors stay on screen edges.
    anchor = "top_left",      -- Default anchor for all HUD elements
    margin = 12,              -- Comfortable margin from screen edges
    -- Move items below hidden entries up to close gaps. False keeps authored spacing.
    -- Covers Max 0 with auto_hide, enabled/visible false, and Game Settings Show toggles.
    collapse_hidden = true,
    -- Column order, top to bottom. Only entries whose merged anchor is top_left
    -- move or free space; presets and position overrides at other anchors stay put.
    collapse_column = { "health_bar", "energy_bar", "stamina_bar", "currency", "abilities", "interact_hint" },
  },

  -- Movement label: the player's current movement ("Walk", "Run", "Air Dash", "Swim").
  -- A testing aid, hidden by default; the F1 debug overlay shows it as State.
  -- Game Settings > HUD > Movement label turns it on for players.
  mode_label = {
    enabled = true,
    anchor = "top_left",
    offset = {x = 12, y = -30},  -- Below menu button
    visible = false,
  },

  -- Health bar (most important, prominent position)
  health_bar = {
    enabled = true,
    anchor = "top_left",
    offset = {x = 12, y = -54},  -- Below mode label
    visible = true,
    show_text = false,           -- Show numeric health value
    text_format = "%d/%d",       -- Format string for health display
  },

  -- Energy bar (auto_hide controls visibility at maximum 0)
  energy_bar = {
    enabled = true,
    anchor = "top_left",
    offset = {x = 12, y = -74},  -- Below health bar
    visible = true,
    auto_hide = true,            -- Hide at maximum 0; false keeps the bar shown, empty.
    show_text = false,
  },

  -- Stamina bar (auto_hide controls visibility at maximum 0)
  stamina_bar = {
    enabled = true,
    anchor = "top_left",
    offset = {x = 12, y = -90},  -- Below energy bar
    visible = true,
    auto_hide = true,            -- Hide at maximum 0; false keeps the bar shown, empty.
    show_text = false,
  },

  -- Currency display
  currency = {
    enabled = true,
    anchor = "top_left",
    offset = {x = 12, y = -112},  -- Clear gap after bars
    visible = true,
    -- One amount placeholder: {amount} (preferred) or legacy %d, e.g. "{amount} Gems".
    -- Write %% for a literal percent; no other percent sequences are supported.
    -- Maximum 40 characters. Invalid formats display the fallback "$ %d".
    format = "$ %d",
    -- Optional separator between groups of three integer digits: "," gives 1,200.
    -- Leave empty for 1200. Applies to currency in the HUD, menus and prompts.
    thousands_separator = "",
  },

  -- Unlocked abilities as short labels ("G S CA DS RA"). A testing aid, hidden by
  -- default; the F1 debug overlay of debug builds lists them. Game Settings > HUD >
  -- Abilities turns the line on for players.
  abilities = {
    enabled = true,
    anchor = "top_left",
    offset = {x = 12, y = -134},  -- Below currency
    visible = false,
    format = "compact",           -- "compact" or "icons" (future)
  },


  -- Interact hint (contextual prompt)
  interact_hint = {
    enabled = true, -- Enable candidate prompts and gate contact hints.
    anchor = "bottom_center", -- Centre text and plate together at the bottom.
    offset = {x = 0, y = 360}, -- Band 300..420; clears countdown (180..292) and dialogue (430..650).
    visible = true, -- Game Settings > Show on screen > Interact prompt.
    opacity = 1, -- Full text opacity by default; applies to contact hints too.
    text_scale = 1.857142857, -- 26 px type with the shipped 14 px font.
    text_color = { r = 1, g = 1, b = 1, a = 1 }, -- Red/green/blue/alpha, each 0 to 1.
    -- Optional plate_color = { r=0, g=0, b=0, a=0.75 } overrides message_plate.
    padding = { x = 24, y = 12 }, -- Final design pixels around measured text.
    max_width = 848, -- Full plate width; long hints wrap before shortening.
    max_height = 120, -- Full plate height, independent of HUD scale; preserves the reserved band.
    fade_duration = 0.25, -- Retained for custom prompt transitions.
  },

  -- Cooldown flash (temporary ability feedback)
  cooldown_flash = {
    enabled = true,
    anchor = "top_left",
    offset = {x = 140, y = -54},  -- To the right of health bar
    visible = true,
    duration = 0.40,
  },

  -- Boss health bar (prominent top-center placement)
  boss_health_bar = {
    enabled = true,
    anchor = "top_center",
    offset = {x = 0, y = -70},   -- Larger offset for new boss bar size
    visible = true,
    show_name = true,
    name_offset = {x = 0, y = 10},  -- Name above the bar
  },

  -- Minimap
  minimap = {
    enabled = true,
    anchor = "bottom_right",
    offset = {x = -20, y = 20},
    visible = true,
    default_mode = "panel",     -- "off", "panel", "fullscreen"
    panel_size = {w = 200, h = 150},
  },

  -- Damage numbers (floating combat text)
  damage_numbers = {
    enabled = true,
    visible = true,
    lifetime = 1.0,             -- How long numbers stay on screen
    rise_speed = 50,            -- Pixels per second upward
    fade_start = 0.5,           -- When to start fading (0-1)
  },

  -- Low health warning (screen vignette)
  low_health_warning = {
    enabled = true,
    visible = true,
    pulse_speed = 2.0,          -- Pulse frequency
    threshold = 0.25,           -- Show below 25% health
  },

  -- Menu button (top-left corner)
  menu_button = {
    enabled = true,
    anchor = "top_left",
    offset = {x = 8, y = -8},
    visible = true,
    label = "Menu",
  },

  -- Layout presets
  -- Developers can switch between these or create custom ones
  presets = {
    -- Default layout (standard placement)
    default = {
      powerups = { visible = true }, -- Keep temporary countdowns in every preset.
      -- Uses the positions defined above
    },

    -- Minimal layout (reduced clutter)
    minimal = {
      powerups = { visible = true }, -- Keep temporary countdowns in every preset.
      weapon = { visible = false }, -- Hide equipped weapon in the minimal preset.
      level_xp = { visible = false }, -- Hide level and XP in the minimal preset.
      play_timer = { visible = false }, -- Keep the optional timer hidden in this preset.
      mode_label = { visible = false },
      abilities = { visible = false },
      currency = { visible = false },
    },

    -- Bottom-left layout (bars at bottom)
    bottom_left = {
      powerups = { visible = true }, -- Keep temporary countdowns in every preset.
      health_bar = { anchor = "bottom_left", offset = {x = 8, y = 80} },
      energy_bar = { anchor = "bottom_left", offset = {x = 8, y = 64} },
      stamina_bar = { anchor = "bottom_left", offset = {x = 8, y = 52} },
      currency = { anchor = "bottom_left", offset = {x = 8, y = 32} },
    },

    -- Centered layout (bars at bottom center)
    centered = {
      powerups = { visible = true }, -- Keep temporary countdowns in every preset.
      health_bar = { anchor = "bottom_center", offset = {x = 0, y = 34} }, -- Top 70 with the tallest theme at scale 2, below toast bottom 72.
      energy_bar = { anchor = "bottom_center", offset = {x = -180, y = 4} }, -- Below health even with the tallest theme at scale 2.
      stamina_bar = { anchor = "bottom_center", offset = {x = 180, y = 4} }, -- Beside energy, below the toast band.
    },
  },

  -- Active preset (change this to switch layouts)
  active_preset = "default",
}
