-- developer/config/biomes.lua
-- Named regions: their names, map colours, title cards, music and ambience.
-- Each entry is one region. A room joins a region through its Tiled `biome`
-- map property (or the world's default_biome when it says inherit).
-- Entries here become the Tiled biomes and reveal_areas dropdowns after
-- Project > Prepare & Check; the key (for example `forest`) is the id.
--
-- Fields of each entry:
--   name       = text players see for the region. Leave it "" for an unnamed
--                region: it then shows no title card and no pause line. The
--                id is never shown in its place.
--   color      = map tint for the region's rooms (vmath.vector4 r, g, b, a).
--                A room's Tiled biome_color still wins.
--   subtitle   = optional second line under the region name ("" or absent:
--                none).
--   title_card = optional: when this region's title card shows. One of
--                "first_visit", "every_entry" or "never". Leave it out to use
--                the Game Settings choice.
--   music      = optional track id from developer/config/music_tracks_generated.lua
--                (an audio file in developer/assets/music that Prepare & Check
--                imports). Every room in the region that has no music of its
--                own plays it; rooms with their own music keep theirs, and a
--                room set to none is silent. Leave it out to use the world default.
--   ambience   = optional ambient sound id from developer/config/ambient_sounds.lua
--                for rooms in the region without their own ambient sound.
--
-- Example:
--   ruins = {
--     name = "Gilded Approach", subtitle = "Where the journey starts",
--     color = v4(0.89, 0.63, 0.29, 1.00),
--     title_card = "first_visit", music = "ruins_theme", ambience = "wind",
--   },

-- Map colours use vmath.vector4; the fallback lets plain Lua tools read this file.
local v4 = vmath and vmath.vector4 or function(r,g,b,a) return {x=r,y=g,z=b,w=a} end

local M = {
  cavern = {
    name = "Crystal Cavern", -- Shared biome for the twenty-room 16px demo.
    color = v4(0.58, 0.54, 0.71, 1.00), -- Slate map tint; wet rooms use their Tiled teal tint.
  },
  ice = {
    name = "Ice Cavern", -- Biome shared by the ten-room 32px sample.
    color = v4(0.46, 0.80, 0.91, 1.00), -- Cyan map tint; Tiled room colors take precedence.
  },
  default = {
    name  = "", -- Unnamed: rooms without a region show no title card or pause line.
    color = v4(0.80, 0.93, 0.99, 1.00), -- minimap outline tint
  },
  factory = {
    name  = "Factory",
    color = v4(0.95, 0.80, 0.20, 1.00),
  },
  forest = {
    name  = "Duskwood Cliffs", -- Lanternfall's twilight cliffs and hanging pines.
    color = v4(0.36, 0.53, 0.85, 1.00),
  },
  graveyard = {
    name  = "Graveyard",
    color = v4(0.70, 0.70, 0.80, 1.00),
  },
  catacombs = {
    name  = "Moonlit Sanctuary", -- Aureole's violet final vaults and star halls.
    color = v4(0.55, 0.52, 0.68, 1.00),
  },
  ruins = {
    name  = "Gilded Approach", -- Lanternfall's sunset palace, where the journey starts.
    color = v4(0.89, 0.63, 0.29, 1.00),
  },
  foundry = {
    name  = "Molten Capital", -- Lanternfall's lava sea and foundry spires.
    color = v4(0.88, 0.35, 0.16, 1.00),
  },
  sanctum = {
    name  = "Amethyst Hollow", -- Lanternfall's crystal caves and the Rite of Dawn.
    color = v4(0.75, 0.38, 0.82, 1.00),
  },
}

return M
