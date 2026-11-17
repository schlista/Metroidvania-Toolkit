-- developer/config/gate_types.lua
-- Pre-built gate type definitions for MV Toolkit
-- Developers can use these out-of-the-box or create custom types
--
-- TILE_PX is the project's tile width in pixels, read from
-- `developer/config/tile_settings.lua`. Distances and offsets in this file
-- are expressed as `TILE_PX` multiples so a gate that wants to react when
-- the player is "1 tile away" stays correct after the project's tile size
-- changes (e.g. switching from 128px to 64px tiles in the wizard). Falls
-- back to 128 when tile_settings.lua is unavailable.
-- Entries here become the Tiled gates dropdown after Project > Prepare & Check.

local vmath = _G.vmath or { vector4 = function(...) return {...} end }
local ok_tile, Tile = pcall(require, "developer.config.tile_settings")
local TILE_PX = (ok_tile and Tile and Tile.width) or 128  -- tile-relative proximity distances

return {
    -----------------------------------------------------------
    -- COMPATIBILITY TYPES (USED BY TILED TEMPLATES)
    -----------------------------------------------------------

    ability_requirement = {
        type = "ability_requirement",
        required_ability = "",
        visual = {
            sprite = "gate_energy_barrier",
            color = vmath.vector4(0.7, 0.8, 1.0, 0.85),
            particle = "energy_shimmer",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "A sealed path blocks your way.",
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = false,
            require_explicit_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "gate_locked",
            unlock_sound = "gate_unlock_energy"
        }
    },

    item_requirement = {
        type = "item_requirement",
        required_item = "",
        consume_item = false,
        visual = {
            sprite = "locked_door_red",
            color = vmath.vector4(0.9, 0.4, 0.4, 1.0),
            particle = "key_sparkle_red",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "This gate requires a key item.",
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = false,
            require_explicit_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "door_locked",
            unlock_sound = "door_unlock"
        }
    },

    key_gate = {
        type = "item_requirement",
        required_item = "key_red",
        consume_item = true,
        visual = {
            sprite = "locked_door_red",
            color = vmath.vector4(1.0, 0.2, 0.2, 1.0),
            particle = "key_sparkle_red",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Locked Door", -- The game adds "Requires:" with the required key's name.
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = false,
            require_explicit_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "door_locked",
            unlock_sound = "door_unlock"
        }
    },

    action_barrier = {
        type = "action_barrier",
        required_action = "dash",
        visual = {
            sprite = "gate_energy_barrier",
            color = vmath.vector4(0.3, 0.6, 1.0, 0.8),
            particle = "energy_shimmer",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "A reinforced barrier blocks your path.\nYou need the right action to break through.",
            proximity_distance = TILE_PX,
            pass_through = false,
            destroy_on_unlock = false,
            require_explicit_unlock = true,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "gate_locked",
            unlock_sound = "gate_unlock_energy"
        }
    },

    -----------------------------------------------------------
    -- MOVEMENT-BASED GATES
    -----------------------------------------------------------

    -- Temporary passage only: never opens permanently or joins a saved gate group.
    intangible_barrier = {
        type = "intangible_barrier", -- Keep its baked collision solid outside passage.
        required_ability = "intangible_dash", -- Map/progression also require Air Dash.
        visual = {
            color = vmath.vector4(0.65, 0.35, 1.0, 0.8), -- Tint the Gate's authored art.
        },
        interaction = {
            proximity_hint = "A shimmering wall. Something fast could pass through it.", -- DisplayText renders hints.
            proximity_distance = TILE_PX, -- Hint range in project pixels.
            pass_through = false, -- Collision is controlled only by temporary intangibility.
            destroy_on_unlock = false, -- Passage keeps the baked gameobject intact.
            damage_per_second = 0, -- This barrier does not damage the player.
        },
        audio = { locked_sound = "gate_locked" }, -- Existing locked-contact feedback.
    },

    dash_barrier = {
        type = "ability_requirement",
        required_ability = "air_dash",
        visual = {
            sprite = "gate_energy_barrier",
            color = vmath.vector4(0.3, 0.6, 1.0, 0.8),  -- Blue energy
            particle = "energy_shimmer",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "A shimmering barrier blocks your path.\nTry dashing through it!",
            proximity_distance = TILE_PX,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "gate_locked",
            unlock_sound = "gate_unlock_energy"
        }
    },

    -- Invisible annotation for a crossing already enforced by room geometry.
    -- Choose the required ability on the placed Gate; no sprite, hint or map icon.
    ability_marker = {
        type = "height_barrier",
        required_ability = "", -- Inherit no ability; set Required ability in Tiled.
        visual = { hidden = true }, -- Keep the baked gate sprite disabled.
        interaction = {
            proximity_distance = 0, -- No proximity interaction or hint.
            pass_through = true, -- Geometry, not this marker, blocks passage.
            destroy_on_unlock = false, -- Retain the baked instance after unlock.
            damage_per_second = 0, -- An annotation never damages the player.
        },
    },

    double_jump_ledge = {
        type = "height_barrier",
        required_ability = "double_jump",
        visual = {
            sprite = "high_ledge_marker",
            color = vmath.vector4(1, 1, 1, 0.5),
            particle = nil,
            scale = 0.8
        },
        interaction = {
            proximity_hint = "Too high to reach...\nIf only you could jump higher!",
            proximity_distance = 96,
            pass_through = true,  -- Not a physical barrier
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = nil,
            unlock_sound = nil
        }
    },

    wall_climb_wall = {
        type = "ability_requirement",
        required_ability = "wall_climb",
        visual = {
            sprite = "smooth_wall",
            color = vmath.vector4(0.7, 0.8, 0.9, 1.0),
            particle = nil,
            scale = 1.0
        },
        interaction = {
            proximity_hint = "The wall is too smooth to grip.\nYou need climbing gear!",
            proximity_distance = 64,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "wall_scrape",
            unlock_sound = nil
        }
    },

    grapple_point = {
        type = "ability_requirement",
        required_ability = "grapple",
        visual = {
            sprite = "grapple_anchor",
            color = vmath.vector4(0.9, 0.7, 0.3, 1.0),  -- Gold anchor
            particle = "grapple_hint_pulse",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "A grapple point!\nYou'll need a grappling hook to reach it.",
            proximity_distance = 200,
            pass_through = true,  -- Can see/pass by it, just can't use it
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = nil,
            unlock_sound = "grapple_attach"
        }
    },

    -----------------------------------------------------------
    -- DESTRUCTIBLE BARRIERS
    -----------------------------------------------------------

    breakable_wall = {
        type = "destructible",
        required_ability = "charge_attack",
        visual = {
            sprite = "cracked_wall",
            color = vmath.vector4(0.8, 0.7, 0.6, 1.0),
            particle = "dust_particles",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Cracked wall...\nA powerful attack might break through!",
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = true,  -- Wall breaks and disappears
            damage_per_second = 0,
            health = 3,  -- Takes 3 hits
            shake_on_hit = true
        },
        audio = {
            locked_sound = "wall_hit",
            unlock_sound = "wall_break"
        }
    },

    breakable_floor = {
        type = "destructible",
        required_ability = "down_strike",
        visual = {
            sprite = "cracked_floor",
            color = vmath.vector4(0.7, 0.6, 0.5, 1.0),
            particle = "crack_pulse",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Fragile floor...\nStrike downward to break through!",
            proximity_distance = 80,
            pass_through = false,
            destroy_on_unlock = true,
            damage_per_second = 0,
            health = 1  -- One down-strike breaks it
        },
        audio = {
            locked_sound = "floor_crack",
            unlock_sound = "floor_shatter"
        }
    },

    -----------------------------------------------------------
    -- KEY/ITEM GATES
    -----------------------------------------------------------

    key_door_red = {
        type = "item_requirement",
        required_item = "key_red",
        consume_item = true,
        visual = {
            sprite = "locked_door_red",
            color = vmath.vector4(1.0, 0.2, 0.2, 1.0),
            particle = "key_sparkle_red",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Locked Door", -- The game adds "Requires:" with the required key's name.
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "door_locked",
            unlock_sound = "door_unlock"
        }
    },

    key_door_blue = {
        type = "item_requirement",
        required_item = "key_blue",
        consume_item = true,
        visual = {
            sprite = "locked_door_blue",
            color = vmath.vector4(0.2, 0.4, 1.0, 1.0),
            particle = "key_sparkle_blue",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Locked Door", -- The game adds "Requires:" with the required key's name.
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "door_locked",
            unlock_sound = "door_unlock"
        }
    },

    key_door_gold = {
        type = "item_requirement",
        required_item = "key_gold",
        consume_item = true,
        visual = {
            sprite = "locked_door_gold",
            color = vmath.vector4(1.0, 0.8, 0.2, 1.0),
            particle = "key_sparkle_gold",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Ornate Locked Door", -- The game adds "Requires:" with the required key's name.
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "door_locked",
            unlock_sound = "door_unlock_special"
        }
    },

    boss_key_door = {
        type = "item_requirement",
        required_item = "key_boss",
        consume_item = false,  -- Boss keys are not consumed
        visual = {
            sprite = "locked_door_boss",
            color = vmath.vector4(0.6, 0.1, 0.6, 1.0),  -- Purple/ominous
            particle = "boss_door_aura",
            scale = 1.2
        },
        interaction = {
            proximity_hint = "Sealed Boss Door", -- The game adds "Requires:" with the required key's name.
            proximity_distance = TILE_PX,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "boss_door_locked",
            unlock_sound = "boss_door_unlock"
        }
    },

    -----------------------------------------------------------
    -- RESOURCE GATES
    -----------------------------------------------------------

    energy_gate = {
        type = "resource_requirement",
        required_resource = "energy",
        -- Energy spent to pass. Keep this <= the player's max_energy
        -- (developer/config/player_settings.lua, default 3) or the gate can
        -- never open. A Tiled gate's requirements.required_energy overrides it.
        resource_amount = 1,
        visual = {
            sprite = "energy_gate",
            color = vmath.vector4(1.0, 1.0, 0.3, 0.9),  -- Yellow energy
            particle = "energy_flow",
            scale = 1.0
        },
        interaction = {
            -- The "Costs: N Energy" line is added from resource_amount at runtime.
            proximity_hint = "Energy Gate",
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = false,
            allow_repeated_use = true,  -- Can pass through multiple times (paying each time)
            damage_per_second = 0
        },
        audio = {
            locked_sound = "insufficient_energy",
            unlock_sound = "energy_gate_pass"
        }
    },

    toll_gate = {
        type = "resource_requirement",
        required_resource = "currency",
        resource_amount = 100,
        visual = {
            sprite = "toll_gate",
            color = vmath.vector4(0.7, 0.6, 0.3, 1.0),
            particle = "coin_glint",
            scale = 1.0
        },
        interaction = {
            -- The "Costs: N Gold" line is added from resource_amount at runtime.
            proximity_hint = "Toll Gate",
            proximity_distance = 96,
            pass_through = false,
            destroy_on_unlock = false,
            allow_repeated_use = true,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "insufficient_funds",
            unlock_sound = "coins_paid"
        }
    },

    -----------------------------------------------------------
    -- HAZARD BARRIERS
    -----------------------------------------------------------

    lava_floor = {
        type = "hazard_barrier",
        required_ability = "heat_resistance", -- Replaces the undefined lava_resistance id.
        visual = {
            sprite = "lava_surface",
            color = vmath.vector4(1.0, 0.4, 0.1, 1.0),
            particle = "lava_bubble",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Scorching lava!\nYou'll need Heat Resistance.",
            proximity_distance = 80,
            pass_through = true,  -- Can enter but takes damage
            destroy_on_unlock = false,
            damage_per_second = 2
        },
        audio = {
            locked_sound = "lava_sizzle",
            unlock_sound = nil
        }
    },

    acid_pool = {
        type = "hazard_barrier",
        required_ability = "acid_resistance",
        visual = {
            sprite = "acid_surface",
            color = vmath.vector4(0.3, 1.0, 0.3, 0.8),
            particle = "acid_bubble",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Toxic acid!\nYou'll need Acid Resistance.",
            proximity_distance = 80,
            pass_through = true,
            destroy_on_unlock = false,
            damage_per_second = 3
        },
        audio = {
            locked_sound = "acid_hiss",
            unlock_sound = nil
        }
    },

    cold_zone = {
        type = "hazard_barrier",
        required_ability = "cold_resistance",
        visual = {
            sprite = "ice_mist",
            color = vmath.vector4(0.6, 0.8, 1.0, 0.6),
            particle = "frost_particles",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Freezing cold!\nYou'll need Cold Resistance.",
            proximity_distance = 96,
            pass_through = true,
            destroy_on_unlock = false,
            damage_per_second = 1
        },
        audio = {
            locked_sound = "cold_wind",
            unlock_sound = nil
        }
    },

    -----------------------------------------------------------
    -- SPECIAL/ADVANCED GATES
    -----------------------------------------------------------

    -- Any-order progress uses one-way flags from switches, plates or events.
    staged_gate = {
        type = "staged", -- Count saved flags rather than ordered switch signals.
        stage_flags = {}, -- Comma-separated Stage flags on the placed Gate override this list.
        stages_required = 0, -- 0 = all listed flags; a positive value needs that many.
        visual = {
            sprite = "rune_gate", -- Optional configured sprite; painted art remains creator-owned.
            color = vmath.vector4(0.6, 0.3, 1.0, 1.0), -- Gate tint.
            scale = 1.0, -- Relative visual scale.
        },
        interaction = {
            proximity_hint = "The gate is sealed.", -- Runtime appends current/required progress.
            pass_through = false, -- Block until enough flags are set.
        },
    },

    timed_gate_60s = {
        type = "timed",
        timer_duration = 60,  -- 60 seconds countdown
        visual = {
            sprite = "timed_gate",
            color = vmath.vector4(1.0, 0.5, 0.0, 0.9),
            particle = "countdown_sparks",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Timed Gate\nWill open after 60 seconds!",
            proximity_distance = TILE_PX,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "timer_tick",
            unlock_sound = "timer_success"
        }
    },

    timed_gate_30s = {
        type = "timed",
        timer_duration = 30,  -- 30 seconds countdown
        visual = {
            sprite = "timed_gate_fast",
            color = vmath.vector4(1.0, 0.7, 0.0, 0.9),
            particle = "countdown_sparks",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Timed Gate\nWill open after 30 seconds!",
            proximity_distance = TILE_PX,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            locked_sound = "timer_tick",
            unlock_sound = "timer_success"
        }
    },

    one_way_gate = {
        type = "one_way",
        required_ability = nil,  -- Directional gate; unlock flow is bypassed by runtime.
        visual = {
            sprite = "one_way_arrows",
            color = vmath.vector4(0.5, 0.5, 0.5, 0.7),
            particle = "arrow_pulse",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "One-Way Passage",
            proximity_distance = 64,
            pass_through = true,
            destroy_on_unlock = false,
            damage_per_second = 0,
            direction = "right"  -- Only passable going right
        },
        audio = {
            locked_sound = "barrier_bump",
            unlock_sound = nil
        }
    },

    -- Opens from a lever, plate or other switch on the gate_id channel.
    -- Gate > Stays open saves the opening; off follows the channel temporarily.
    switch_gate = {
        type = "switch", -- Requirements never auto-unlock a switch gate.
        interaction = {
            proximity_hint = "Activate the linked switch to open this gate.",
            proximity_distance = TILE_PX, -- Hint within one authored tile.
            pass_through = false, -- Solid while the channel is off.
            destroy_on_unlock = false, -- Keep the instance for reversible openings.
        },
        audio = {
            unlock_sound = "gate_unlock", -- sound_bank.lua id, or nil for silence.
            locked_sound = "gate_locked", -- Contact/closing sound_bank.lua id.
        },
    },

    sequence_gate_3step = {
        type = "sequence",
        reset_on_wrong = true, -- Wrong steps restart this room-local puzzle.
        required_sequence = {"switch_1", "switch_2", "switch_3"},  -- Must activate in this order
        visual = {
            sprite = "rune_gate",
            color = vmath.vector4(0.6, 0.3, 1.0, 1.0),
            particle = "rune_glow",
            scale = 1.0
        },
        interaction = {
            proximity_hint = "Ancient Rune Gate\nActivate the nearby switches in the correct order.",
            proximity_distance = TILE_PX,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            step_sound = "lever_on", -- Accepted step; ids come from sound_bank.lua.
            fail_sound = "gate_locked", -- Wrong step.
            locked_sound = "gate_locked", -- Contact while locked.
            unlock_sound = "gate_unlock" -- Completed order.
        }
    },

    sequence_gate_5step = {
        type = "sequence",
        reset_on_wrong = true, -- Partial progress resets when the room reloads.
        required_sequence = {"rune_north", "rune_east", "rune_south", "rune_west", "rune_center"},
        visual = {
            sprite = "complex_rune_gate",
            color = vmath.vector4(0.7, 0.2, 0.9, 1.0),
            particle = "complex_rune_glow",
            scale = 1.2
        },
        interaction = {
            proximity_hint = "Complex Rune Gate\nActivate all 5 runes in the ancient pattern.",
            proximity_distance = TILE_PX,
            pass_through = false,
            destroy_on_unlock = false,
            damage_per_second = 0
        },
        audio = {
            step_sound = "lever_on", -- Accepted step.
            fail_sound = "gate_locked", -- Wrong step.
            locked_sound = "gate_locked", -- Contact while locked.
            unlock_sound = "gate_unlock" -- Completed order.
        }
    }
}
