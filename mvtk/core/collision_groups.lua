-- Maintainer registry and future-family reuse plan; no runtime consumer.
-- Group and mask names share 16 slots per collision world. Do not add names.
-- This module requires no engine globals and does not alter any collider.
local M = {}

M.NAMES = {
    attack = "Melee hitboxes and attack receivers' masks.",
    breakable = "Attack triggers on breakable walls, secrets and switches.",
    collectible = "Pickups detected by the player.",
    enemy = "Enemy bodies and their combat interactions.",
    grapple = "Hook attachment targets and painted grapple strips.",
    hazard = "Damage volumes detected by the player.",
    interactable = "Interactive objects and static gate barriers.",
    ladder = "Climbable ladder volumes.",
    platform = "One-way platforms and their terrain queries.",
    player = "Player bodies, hurtboxes and overlap detection.",
    pushable = "Pushable-block tags, including elevator rider detection.",
    sensor = "General overlap volumes and room-lock sensing.",
    solid = "Painted terrain and elevator cabin collision.",
    surface = "Surface-effect strips and player foot probes.",
    water = "Water volumes recognized by player movement.",
    world = "World geometry, blockers and projectile contacts.",
}

-- Mirrors surface_classifier.lua's ACTIVE_RAYCAST_GROUPS. This is the terrain
-- set, not a cap: a planned sweep may query any registered name (see below).
M.RAYCAST_ALLOWED = { "solid", "world", "platform" }

-- Planned reuse only. Each row lists all groups, masks and raycast names it
-- uses; variants and collider types are explained in its description.
M.FAMILIES = {
    carry_sockets = {
        groups = { "sensor" }, masks = { "world" },
        description = "Baked sockets detect carryable world bodies using the existing sensor group.",
    },
    carryables = {
        groups = { "world" }, masks = { "player", "sensor", "solid" },
        raycasts = { "solid", "world", "platform" },
        description = "Baked kinematic carryables use mass zero, with no pushable trigger. Falling sweeps alone include platforms.",
    },
    movement_modifier_zones = {
        groups = { "sensor" }, masks = { "player" },
        description = "Baked movement zones affect player overlaps only, reusing sensor.",
    },
    launch_cannons = {
        groups = { "interactable" }, masks = { "player" },
        description = "Baked launch cannons reuse the interaction trigger to load player parts.",
    },
    path_vehicles = {
        groups = { "solid" }, masks = { "player", "enemy" },
        description = "Baked carts and gondolas reuse solid bodies; the existing surface rider probe remains unchanged.",
    },
    multi_stop_lifts = {
        groups = { "solid" }, masks = { "player", "enemy", "world", "pushable" },
        description = "Cabins with several floors retain the existing solid body and solid rider sensor.",
    },
    wind_current_fields = {
        groups = { "sensor" }, masks = { "player" },
        description = "Wind and current fields affect the player. Add enemy or collectible masks only when a feature pushes them.",
    },
    slippery_surfaces = {
        groups = { "surface" }, masks = { "player" },
        description = "Surface strips reuse sprite and Spine foot-probe masks; painted layers bake strips like the grapple-layer baker.",
    },
    ride_grab_volumes = {
        groups = { "interactable" }, masks = { "player" },
        description = "Grab volumes for lines and rails reuse the existing interaction group.",
    },
    pass_through_walls = {
        groups = { "interactable" }, masks = { "player" },
        description = "G6-D2 plans mvtk/player/intangibility.lua and a baked intangible_barrier gate that disables its own interactable collision component while active and keeps passage open until exit. Terrain stays solid; no raycast filter or host flag.",
    },
    level_volumes = {
        groups = { "water", "hazard" }, masks = { "player", "enemy" },
        description = "Switch-controlled water and rising hazard volumes reuse the existing triggers.",
    },
    moving_hazards = {
        groups = { "hazard" }, masks = { "player" },
        description = "Translating saws, orbiting fire bars and slam crushers use the existing hazard trigger.",
    },
    ticking_zones_swinging_blades = {
        groups = { "hazard" }, masks = { "player" },
        description = "Ticking damage zones and swinging blades reuse hazard. Moving blades stay kinematic, animated with go.animate, without Box2D joints.",
    },
    destructible_spawners = {
        groups = { "enemy" }, masks = { "player", "attack" },
        description = "Destructible spawners reuse enemy bodies and attack detection.",
    },
    stationary_shooting_enemies = {
        groups = { "enemy" }, masks = { "player", "attack", "world", "solid" },
        description = "Stationary shooters use ordinary enemy prefabs.",
    },
    encounter_rooms = {
        groups = { "sensor", "world" }, masks = { "player", "enemy" },
        description = "A sensor masking player activates the encounter. The room lock reuses door_blocker (world STATIC masking player and enemy, plus sensor masking player) and arena_lock.",
    },
    stations_storage = {
        groups = { "interactable" }, masks = { "player" },
        description = "Vendors, stations, trainers, altars and storage reuse interaction volumes. Vendor NPCs instead reuse npc.go's interaction_range without a collider; the historical vendor used sensor.",
    },
    timed_pickups = {
        groups = { "collectible" }, masks = { "player" },
        description = "Timed pickups reuse collectible bodies.",
    },
    breakable_scenery = {
        groups = { "interactable", "breakable" }, masks = { "attack" },
        description = "Breakable scenery combines interaction and attack-trigger components.",
    },
    positional_ambience = {
        groups = {}, masks = {},
        description = "Positional ambience needs no collision component.",
    },
    projectile_line_of_sight = {
        groups = {}, masks = {}, raycasts = { "solid", "world", "platform" },
        description = "Projectiles and line-of-sight queries use the terrain raycast set. Never add breakable to the player projectile mask: gate and secret attack triggers would stop shots.",
    },
    teleport_destination_checks = {
        groups = {}, masks = {}, raycasts = { "solid", "world", "platform", "interactable", "pushable" },
        description = "Blink destination sweeps also catch static interactable gate barriers and pushable blocks; terrain-only sweeps would bypass them.",
    },
    return_point_zones = {
        groups = { "sensor" }, masks = { "player" },
        description = "Return point zones reuse sensor for the planned hazard_return_zone template.",
    },
    hit_activated_switches = {
        groups = { "breakable", "world" }, masks = { "attack", "player", "enemy" },
        description = "Melee uses a breakable TRIGGER masking attack. Floating switches add a world TRIGGER masking attack for shots; raycasts ignore triggers. Solid switches instead add a world STATIC body masking player and enemy.",
    },
    runtime_death_hazards = {
        groups = { "hazard" }, masks = { "player" },
        description = "Runtime death hazards reuse the same group and mask as Tiled hazards.",
    },
}

return M
