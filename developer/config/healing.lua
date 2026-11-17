-- Quick Use healing. Game Settings publishes overrides without rewriting this baseline.
return {
    model = "flask", -- flask: rechargeable built-in heal; items: owned potions only; channel: hold to spend energy healing.
    heal_name = "Healing Flask", -- Built-in quick-item display name.
    flask = {
        max_charges = 2, -- Starting capacity; 0 removes the built-in flask.
        heal_amount = 2, -- Health restored per completed drink.
        use_time = 0.5, -- Seconds before healing and spending; 0 is instant.
        refill_at_save_points = true, -- Rest refills only when the save point heals.
        refill_on_respawn = true, -- Refill on respawn and checkpoint load.
        upgrade_charges = 1, -- Capacity added by upgrades that omit their value.
    },
    channel = {
        heal_amount = 1, -- Health restored per completed channel.
        cost = 1, -- Shared energy spent only on completion; Max energy 0 prevents channel healing.
        channel_time = 0.8, -- Seconds per heal, after the Quick Use hold threshold.
        repeat_while_held = true, -- Start another heal while held, hurt and able to pay.
        hint_event = "channel_heal_hint", -- Tutorial event on the first health drop with usable channel healing.
    },
    use = {
        move_mult = 0.3, -- Walking multiplier during a drink or channel; minimum 0.25 (speed floor).
        allow_in_air = true, -- Permit drinks and channels while airborne.
        allow_in_water = false, -- Permit drinks and channels while swimming.
        interrupt_on_damage = true, -- A health drop cancels without spending.
        cancel_on_action = true, -- Jump, dash, attacks, parry or grapple cancel.
        use_animation = "", -- Optional authored animation; blank keeps movement animation.
        sound_use = "collectible_pick", -- Audio controller sound ID on completion; blank is silent.
        sound_refuse = "ui_back", -- Audio controller sound ID on refusal; blank is silent.
        fx = "unlock", -- fx_types.lua effect on completion; blank disables it.
    },
    quick = {
        order = { "heal", "potion_small", "potion_large" }, -- Unlisted quick items sort by ID afterward.
        auto_fallback = true, -- Empty selection uses the next available heal.
        step_repeat_seconds = 0.45, -- Selection repeat while held; Game Settings > Controls overrides this and the initial hold.
    },
    hint_event = "heal_hint", -- Tutorial event on the first health drop with usable healing.
    energy = {
        enabled = false, -- Gain energy from combat in every healing model; off preserves pickup/rest-only gains.
        gain_on_hit = 0.25, -- Energy per accepted player hit; damage-over-time ticks give no hit gain.
        gain_on_parry = 0.5, -- Energy per successful regular parry.
        gain_on_perfect_parry = 1, -- Energy per perfect parry, replacing the regular parry gain.
        gain_on_kill = 0.25, -- Extra energy on a lethal player hit; hazards and ownerless ticks give none.
    }, -- Gains use Max energy units and clamp to that pool; maximum 0 disables gains. Energy is not saved.
}
