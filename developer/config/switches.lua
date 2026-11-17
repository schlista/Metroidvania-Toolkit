-- Switch channels connect a lever/plate target_id to a receiver's authored id.
-- Tick persist_state on a toggle lever or plate to restore its saved state and
-- replay its channel when the receiving room loads, including unloaded rooms.
-- Flags stores two key families in the existing save data:
--   switch_state_<persist_key>: the switch's own boolean state;
--   switch_channel_<target_id>: the last on/off state and message for a channel.
-- Keep these authored ids stable after releasing a game. Momentary and elevator
-- call levers ignore persist_state. Sequence puzzles keep it off; their partial
-- progress resets. A switch gate with Stays open also saves gate_<gate_id>.
return {
    -- sound_bank.lua SFX id played when a one-sided wall refuses an otherwise
    -- accepted hit. Set to "" for silence. Explosion messages bypass the side rule.
    blocked_hit_sound = "parry_miss",
    -- Accepted attack_type tags for the Strike Switch's one Accepts dropdown.
    -- "any" bypasses this table (enemy/boss filtering still applies).
    accept_groups = {
        -- Ordinary weapon hits; a downward strike also counts as melee.
        melee = {"light_attack", "heavy_attack", "charge_attack", "parry_counter", "down_strike"},
        -- Player ranged shots use ranged_attack, not their damage_type.
        projectile = {"ranged_attack"},
        -- These narrow choices let creators require the particular ability.
        down_strike = {"down_strike"},
        ground_pound = {"ground_pound"},
        -- Super Jump is a movement contact too. Backdash needs its contact enabled.
        movement = {"dash", "slide", "backdash", "super_jump"},
        -- Player bomb blast hitboxes emit this action tag.
        bomb = {"bomb"},
        -- Carryable crate and orb impacts emit the throw action tag.
        thrown = {"throw"},
    },
    -- sound_bank.lua SFX id for an unaccepted hit; "" silences default rejection.
    reject_sound = "parry_miss",
    -- Seconds between the momentary on and off signals (off waits out menu pause).
    momentary_pulse = 0.2,
    -- Seconds between hits when a switch's Cooldown is -1; 0 allows every hit.
    default_cooldown = 0.25,
    -- Optional sound_bank.lua SFX id at each remaining whole second; "" is silent.
    timed_tick_sound = "",
}
