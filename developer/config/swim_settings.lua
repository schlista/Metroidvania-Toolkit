-- developer/config/swim_settings.lua
-- Default swimming movement and oxygen tuning.

return {
    -- Full stroke speed, in pixels per second. Use a positive speed.
    swim_speed = 200,
    -- Initial acceleration toward full stroke speed, in pixels per second squared. Use zero or more.
    swim_acceleration = 800,
    -- Fraction of speed kept each 60 Hz step on an axis without input. Use 0 to 1.
    swim_friction = 0.85,
    -- Let swimmers burst with Dash. Set true to enable it or false to disable it.
    swim_dash_enabled = true,
    -- Burst speed, in pixels per second. Use a positive speed above swim_speed for a faster burst.
    swim_dash_speed = 400,
    -- Time at burst speed, in seconds. Use at least one 60 Hz step (about 0.017 seconds).
    swim_dash_duration = 0.3,
    -- Time between the burst ending and the next Dash, in seconds. Use zero or more.
    swim_dash_cooldown = 0.5,
    -- Sound ID from sound_bank.lua when the burst starts. Use a registered ID or "" for silence.
    swim_dash_sound = "air_dash",

    -- Time between bubbles, in seconds. Use at least one 60 Hz step (about 0.017 seconds).
    bubble_interval = 0.5,
    -- Full meter, in oxygen units. Use a positive amount.
    oxygen_max = 10.0,
    -- Oxygen used per second below the surface. Use zero or more.
    oxygen_drain_rate = 1.0,
    -- Oxygen restored per second at the surface or in a default air pocket. Use zero or more.
    oxygen_refill_rate = 2.0,
    -- Exit speed required for a splash event, in pixels per second. Use zero or more.
    surface_splash_threshold = 50,
}
