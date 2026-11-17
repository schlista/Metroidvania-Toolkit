-- developer/config/boss_arenas.lua
-- Boss arena configurations with hazards, destructibles, and boss phase behaviors

local M = {}

-- Arena definitions
M.arenas = {
    -- Forest Guardian Arena
    forest_arena = {
        id = "forest_arena",
        center_x = 500,
        center_y = 300,
        bounds = {
            min_x = 100,
            max_x = 900,
            min_y = 100,
            max_y = 500
        },

        -- Per-phase arena hazards are Tiled objects, not config: place
        -- environment/hazard.tx in the Boss Arena, link arena_ref and set
        -- arena.active_phases (for example "2,3"). See "Phase-gated arena
        -- hazards" in docs/CREATOR_WORKFLOW.md. A phase_hazards table here
        -- spawns nothing, and Prepare & Check warns when one lists a hazard.

        -- Destructible cover objects
        destructibles = {
            {
                id = "tree_1",
                type = "cover",
                position = vmath.vector3(300, 300, 0),
                health = 100
            },
            {
                id = "tree_2",
                type = "cover",
                position = vmath.vector3(700, 300, 0),
                health = 100
            }
        },

        -- Boss phase transition configs
        phase_transitions = {
            [1] = {
                type = "standard"
            },
            [2] = {
                type = "rage",
                effect = "spawn_adds",
                effect_params = {
                    count = 2,
                    enemy_type = "vine_minion",
                    spawn_radius = 150
                }
            },
            [3] = {
                type = "environmental",
                effect = "hazard_pulse"
            }
        }
    },

    -- Flame Lord Arena
    flame_arena = {
        id = "flame_arena",
        center_x = 600,
        center_y = 350,
        bounds = {
            min_x = 200,
            max_x = 1000,
            min_y = 150,
            max_y = 550
        },

        -- Per-phase arena hazards are Tiled objects, not config: place
        -- environment/hazard.tx in the Boss Arena, link arena_ref and set
        -- arena.active_phases (for example "2,3"). See "Phase-gated arena
        -- hazards" in docs/CREATOR_WORKFLOW.md. A phase_hazards table here
        -- spawns nothing, and Prepare & Check warns when one lists a hazard.

        destructibles = {},

        phase_transitions = {
            [1] = {
                type = "standard"
            },
            [2] = {
                type = "rage",
                new_music = "boss_theme_intense"
            },
            [3] = {
                type = "environmental",
                effect = "hazard_pulse"
            }
        }
    },

    -- Shadow Knight Arena
    shadow_arena = {
        id = "shadow_arena",
        center_x = 500,
        center_y = 300,
        bounds = {
            min_x = 100,
            max_x = 900,
            min_y = 100,
            max_y = 500
        },

        -- Per-phase arena hazards are Tiled objects, not config: place
        -- environment/hazard.tx in the Boss Arena, link arena_ref and set
        -- arena.active_phases (for example "2,3"). See "Phase-gated arena
        -- hazards" in docs/CREATOR_WORKFLOW.md. A phase_hazards table here
        -- spawns nothing, and Prepare & Check warns when one lists a hazard.

        destructibles = {
            {
                id = "pillar_1",
                type = "cover",
                position = vmath.vector3(300, 300, 0),
                health = 150
            },
            {
                id = "pillar_2",
                type = "cover",
                position = vmath.vector3(700, 300, 0),
                health = 150
            },
            {
                id = "pillar_3",
                type = "cover",
                position = vmath.vector3(500, 450, 0),
                health = 150
            }
        },

        phase_transitions = {
            [1] = {
                type = "standard"
            },
            [2] = {
                type = "teleport",
                teleport_destination = function()
                    -- Teleport to random position in arena
                    return vmath.vector3(
                        math.random(200, 800),
                        math.random(200, 400),
                        0
                    )
                end
            },
            [3] = {
                type = "summon",
                effect = "spawn_adds",
                effect_params = {
                    count = 4,
                    enemy_type = "shadow_clone",
                    spawn_radius = 180
                }
            }
        }
    },

    -- Generic arena template
    generic_arena = {
        id = "generic_arena",
        center_x = 500,
        center_y = 300,
        bounds = {
            min_x = 100,
            max_x = 900,
            min_y = 100,
            max_y = 500
        },

        -- Per-phase arena hazards are Tiled objects, not config: place
        -- environment/hazard.tx in the Boss Arena, link arena_ref and set
        -- arena.active_phases (for example "2,3"). See "Phase-gated arena
        -- hazards" in docs/CREATOR_WORKFLOW.md. A phase_hazards table here
        -- spawns nothing, and Prepare & Check warns when one lists a hazard.

        destructibles = {},

        phase_transitions = {
            [1] = { type = "standard" },
            [2] = { type = "rage" },
            [3] = { type = "environmental" }
        }
    }
}

-- Helper function to get arena config
function M.get_arena(arena_id)
    return M.arenas[arena_id]
end

return M
