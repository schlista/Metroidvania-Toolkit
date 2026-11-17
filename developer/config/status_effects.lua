-- Transient combat statuses. Never saved; death, respawn and a new session clear them.
-- Stable effect ids also populate Tiled's Status effect dropdown on Prepare & Check.
-- Labels are translatable creator source text; colours are plain RGB in [0,1].
return {
    enabled = true, -- Master switch; off removes existing statuses on the next active tick.
    defaults = {
        tick_interval = 1, -- Seconds between damage ticks when an effect omits its interval (> 0).
        refresh_interval = 0.1, -- Seconds between refreshing the player's one temporary stat source (> 0).
    },
    -- duration and tick_interval are seconds (> 0); damage_per_tick is health per stack (>= 0).
    -- max_stacks adds damage stacks and refreshes duration; 1 means refresh only.
    -- move multiplies walking speed, never actions, swimming or ladders (range [0.25,1]).
    -- damage_type names damage_types.lua; outgoing factors are applied by the recipient once.
    effects = {
        poison = {label="Poison", color={0.5,0.9,0.2}, duration=4, tick_interval=1,
            damage_per_tick=0.25, max_stacks=3, damage_type="poison"},
        burn = {label="Burn", color={1,0.35,0.1}, duration=2, tick_interval=0.5,
            damage_per_tick=0.25, max_stacks=1, move=0.95, damage_type="fire"},
        freeze = {label="Freeze", color={0.4,0.8,1}, duration=1.5, move=0.4,
            stops_enemies=true}, -- Regular enemies stop; the player retains all actions.
        slow = {label="Slow", color={0.7,0.5,1}, duration=2, move=0.6},
    },
    player = {immune={}}, -- Effect ids the player never receives (array or true-valued set).
    bosses = {
        immune={"freeze"}, -- Bosses ignore Freeze by default; creators may remove it.
        min_move_multiplier=0.25, -- Lower bound for queries; boss movement integration is separate.
    },
    feedback = {
        tint=true, -- Flash the target's anim component on damaging ticks.
        flash_duration=0.1, -- Flash length in seconds (> 0).
    },
}
