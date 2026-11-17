-- Carryable kinds and shared handling. Distances are world pixels unless noted.
return {
    hold_above_ratio = 1.0, -- Object bottom above player centre, in player collider half heights.
    throw_angle = 30, -- Degrees above the facing direction for Attack.
    up_throw_angle = 80, -- Degrees above facing for Up + Attack.
    return_delay = 0.6, -- Unpaused seconds hidden before a lost/broken object returns home.
    -- Kind keys populate Tiled's Kind dropdown. Impact tags reach walls and switches.
    kinds = {
        orb = { hit_tag = "throw", impact_damage = 0, hit_enemy = false }, -- Puzzle hit only.
        crate = { hit_tag = "throw", impact_damage = 1, hit_enemy = true }, -- Scaled player damage.
        bomb = { explodes = true, hit_tag = "bomb", radius_tiles = 1.5, damage = 3 }, -- Fuse starts on pickup; uses the player bomb attack, no ability cost.
    },
    animations = { idle = "", move = "" }, -- Blank keeps ordinary player animations.
    -- Per-object Move speed mult is [0.25,1], through PlayerStats source carry.
    -- Other speed sources multiply; the final speed multiplier has floor 0.25.
}
