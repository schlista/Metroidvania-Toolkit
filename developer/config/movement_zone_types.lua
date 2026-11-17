-- Movement Zone presets. Keys populate the Tiled Preset dropdown.
-- Each field is optional: omitted multipliers use 1, sink_speed uses 0 and
-- escape_jumps uses false. Tiled overrides of -1 inherit these values.
-- Multipliers use PlayerStats: gravity_mult [0.1, 3], max_fall_mult [0.01, 3],
-- speed_mult [0.25, 3], jump_mult [0.25, 3]. Values below 1 weaken the stat;
-- above 1 strengthen it. Jump scales velocity AFTER High Jump (height scales
-- by jump_mult squared / gravity_mult). Wall/ladder jumps and grapple launches
-- stay unscaled. Glide and swim fall caps keep their own settings.
-- Overlapping zones keep the strongest distance from 1 PER KEY, not a product;
-- other temporary sources such as Compact Form and healing still multiply.
-- sink_speed is a finite nonnegative downward bias in world pixels/second.
-- escape_jumps keeps a short coyote window alive for repeated floorless jumps.
-- Sinking pools need a floor or Hazard below; these zones do not deal damage.
return {
    low_gravity = {
        gravity_mult = 0.35, -- Gravity floor 0.1: floaty ascent/descent.
        max_fall_mult = 0.3, -- Terminal multiplier floor 0.01.
        jump_mult = 0.75, -- Jump velocity floor 0.25; allow ample headroom.
    },
    heavy = {
        gravity_mult = 1.6, -- Gravity floor 0.1: faster pull downward.
        jump_mult = 0.8, -- Jump velocity floor 0.25.
        speed_mult = 0.85, -- Run/walk multiplier floor 0.25.
    },
    sticky = {
        speed_mult = 0.45, -- Run/walk multiplier floor 0.25.
        jump_mult = 0.6, -- Jump velocity floor 0.25.
    },
    sinking = {
        max_fall_mult = 0.015, -- Terminal multiplier floor 0.01.
        jump_mult = 0.45, -- Jump velocity floor 0.25: weak escape jumps.
        speed_mult = 0.4, -- Run/walk multiplier floor 0.25.
        sink_speed = 40, -- Downward bias in world pixels/second, minimum 0.
        escape_jumps = true, -- Repeated Jump presses work without a floor.
    },
}
