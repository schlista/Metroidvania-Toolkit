-- Attack choice weights for boss phases that list individual attacks.
-- Select a behaviour in a boss phase to use its weights. Higher weights make
-- matching attacks more likely when several are ready and within reach.
-- Between two usable entries, a weight of 6 is twice as likely to be picked as 3.
-- charge is a dash, melee is a close-up strike or combo, grab catches the
-- player, aoe covers an area, projectile fires shots, beam fires a continuous
-- shot, summon calls helpers, and special covers the remaining attack kinds.
-- max_repeat is how many times the boss can choose an attack in a row before
-- preferring a different usable attack. A sole usable attack can repeat once
-- ready. A named moveset supplies its own weights and repeat preferences.
-- Omitted behaviours or weights inherit the shipped defaults.

return {
    -- Favours charges and close-up strikes.
    aggressive = {
        charge = 7, melee = 6, grab = 2, aoe = 5,
        projectile = 4, beam = 3, summon = 1, special = 2, max_repeat = 2,
    },
    -- Favours charges and strikes, with more special moves.
    berserk = {
        charge = 7, melee = 6, grab = 4, aoe = 5,
        projectile = 3, beam = 2, summon = 1, special = 4, max_repeat = 2,
    },
    -- Favours shots, beams, and attacks that cover an area.
    cautious = {
        charge = 3, melee = 2, grab = 1, aoe = 5,
        projectile = 7, beam = 6, summon = 4, special = 1, max_repeat = 1,
    },
    -- Favours ranged attacks and calling for help.
    defensive = {
        charge = 3, melee = 2, grab = 1, aoe = 4,
        projectile = 7, beam = 6, summon = 5, special = 1, max_repeat = 1,
    },
    -- Favours special moves and attacks that cover an area.
    desperate = {
        charge = 5, melee = 2, grab = 7, aoe = 6,
        projectile = 3, beam = 4, summon = 1, special = 7, max_repeat = 2,
    },
    -- Favours special moves and calling for help.
    erratic = {
        charge = 3, melee = 2, grab = 7, aoe = 5,
        projectile = 4, beam = 1, summon = 6, special = 7, max_repeat = 2,
    },
    -- Favours shots and beams while patrolling.
    patrol = {
        charge = 3, melee = 2, grab = 1, aoe = 4,
        projectile = 7, beam = 6, summon = 5, special = 1, max_repeat = 1,
    },
    -- Gives every attack kind the same chance.
    random = {
        charge = 1, melee = 1, grab = 1, aoe = 1,
        projectile = 1, beam = 1, summon = 1, special = 1, max_repeat = 2,
    },
    -- Favours charging, close-up strikes, and follow-up shots.
    relentless = {
        charge = 7, melee = 6, grab = 2, aoe = 4,
        projectile = 5, beam = 3, summon = 1, special = 2, max_repeat = 1,
    },
    -- Favours charges, shots, and beams.
    skilled = {
        charge = 7, melee = 4, grab = 1, aoe = 3,
        projectile = 6, beam = 5, summon = 2, special = 1, max_repeat = 1,
    },
    -- Favours easy-to-spot ranged attacks and summons.
    testing = {
        charge = 2, melee = 3, grab = 1, aoe = 4,
        projectile = 7, beam = 6, summon = 5, special = 1, max_repeat = 1,
    },
}
