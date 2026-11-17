-- Creator defaults for player accessibility preferences. Existing saved choices win.
-- Reading text scales independently of HUD labels, menus and prompts.
return {
    player = { -- Starting preferences for players without saved choices.
        text_size = 1, -- Reading-text scale, chosen from text_sizes below; menus/HUD stay at 1.
        shake = "auto", -- auto follows Camera shake; full, reduced and off override it.
        flashes = "full", -- Full-screen flashes: full, reduced or off. Sprite tints are separate.
        freeze_frames = "full", -- Impact freeze frames: full, reduced or off.
        assist = { -- Starting assist preferences; existing saved choices still win.
            damage_taken = 1, -- Full ordinary incoming damage until the player chooses otherwise.
            game_speed = 1, -- Normal gameplay speed; menus always retain their normal speed.
            pit_rescue = false, -- Kill contacts remain lethal until the player chooses safe returns.
        },
    },
    show = { -- Whether each corresponding player row will be offered in Settings.
        text_size = true, -- Offer reading-text size.
        shake = true, -- Offer Screen shake.
        flashes = true, -- Offer Flashes.
        freeze_frames = true, -- Offer Freeze frames.
        vibration = true, -- Offer Vibration On/Off; its saved preference is gameplay.rumble.
        toggles = true, -- Offer press-instead-of-hold rows for the actions this game uses.
    },
    toggles = { -- Starting press-instead-of-hold choices; hidden rows use these creator defaults.
        grab = false, -- Press Interact once to grab a block and again to let go; false keeps holding.
        grapple = false, -- Press Grapple again to let go; false follows the creator's Stay hooked choice.
        heal = false, -- Tap Quick Use to channel healing and press again to stop; channel model only.
        run = false, -- Press Slide to keep running after the slide; press again or stop moving to end it.
        glide = false, -- Press Jump while falling with no air jump spent to glide; press again or land to stop.
        aim = false, -- Press Ranged to hold the grounded aim stance and press again to fire and leave it.
    },
    text_sizes = { 1, 1.25, 1.5 }, -- Available reading-text scales (100, 125 and 150 percent).
    captions = { -- Clip choices and caption defaults; saved player choices override enabled/background.
        enabled = false, -- Player default: off uses base/language clips, on prefers burned-in subtitles.
        background = "dim", -- Caption-line backdrop: off, dim or solid; native video covers game captions.
        show_options = true, -- Offer Captions and Caption background in the player Settings menu.
        sound = true, -- Allow sound_bank sound descriptions when the player's Captions choice is on.
        sound_seconds = 2.5, -- Seconds to keep each sound description on screen.
        sound_repeat_gap = 4.0, -- Minimum seconds between repeated descriptions of the same sound id.
    },
    assist = { -- Optional player aids; hiding them also stops applying saved assist choices.
        allowed = true, -- Offer assist in Settings; creators can turn every assist option off here.
        record_use = true, -- Mark saves that use assist and show Assist used in Records and ending statistics.
        block_achievements = false, -- Refuse achievement unlocks on marked saves while record_use is on.
        damage_taken = { 1, 0.75, 0.5, 0.25, 0 }, -- Incoming damage factors; 0 ignores ordinary hits, not kills.
        game_speed = { 1, 0.9, 0.8, 0.7, 0.6, 0.5 }, -- Whole-game speed factors; game-time clocks slow too.
        pit_damage = 1, -- Damage charged for a rescued pit/kill contact (0 to 100); normal damage factors apply.
    },
    reduced = { -- Multipliers and limits used by the reduced choices.
        shake = 0.5, -- Multiply shake magnitude; duration stays unchanged.
        freeze = 0.5, -- Multiply each impact freeze duration.
        flash_alpha = 0.35, -- Multiply full-screen flash opacity.
        flash_min_seconds = 0.3, -- Minimum reduced flash duration, in seconds.
        flash_min_gap = 0.34, -- Minimum gap between flash starts; keeps under three per second.
    },
}
