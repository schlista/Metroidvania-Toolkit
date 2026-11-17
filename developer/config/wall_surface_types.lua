-- Wall material presets. Keys populate Tiled's Surface type dropdown.
-- Objects can restrict these permissions further, but cannot enable a mechanic
-- the player has not unlocked. Optional allow_slide, allow_jump and allow_climb
-- booleans forbid those mechanics when false; omitted permissions inherit.
-- slide_mult multiplies the player's wall-slide fall cap; 0 holds still.
-- Optional jump_force_x/y replace wall-jump speeds in base player pixels/second
-- (0 is valid); omitted or -1 inherits. Player Size scales authored speeds when
-- Scale movement is on. Optional require_ability names an additional unlock.
return {
    stone = { slide_mult = 1 }, -- Neutral material: inherit player movement.
    ice = {
        slide_mult = 1.8, -- Faster descent while holding toward the wall.
        allow_climb = false, -- No cling, climb or ledge hang on ice.
    },
    wood = { slide_mult = 0.9 }, -- Slightly slower descent.
    metal = { slide_mult = 1.2 }, -- Slightly faster descent.
}
