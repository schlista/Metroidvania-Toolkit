-- Dark rooms use the Tiled map's darkness property (0 = clear, 1 = fully dark).
-- Screen Effect Zones and boss arenas can override it while active.
-- Game Settings > Display > Lighting saves overrides for the look and colours.
return {
    -- "mask" reveals room art near lights; "glow" keeps the dark tint and additive glow.
    mode = "mask",
    -- 0-1: darkest a room gets in mask mode. 1 permits full black outside lights;
    -- 0.9 keeps a faint view. Glow only retains the light manager's 0.9 ceiling.
    max_darkness = 1.0,
    -- RGB 0-1: unlit areas fade toward this colour; black matches the old tint.
    shadow_color = { r = 0, g = 0, b = 0 },
    -- RGB 0-1: light colour, matching the existing warm overlay tint by default.
    light_color = { r = 1.0, g = 0.92, b = 0.70 },
    -- 0.25-4: fade exponent; below 1 spreads light, above 1 tightens its soft edge.
    falloff = 0.6,
    -- 0.25-1: light target size relative to the picture; smaller uses fewer pixels.
    mask_scale = 0.5,
    -- 0-1: share of the old additive GUI glow retained while the mask is on.
    glow_with_mask = 0,
    -- Non-empty animation id in gameplay_visuals.atlas used for each light's shape.
    light_shape = "light_glow_soft",
    -- Integer 1-64: maximum mask lights in view; the brightest lights win.
    max_lights = 24,
}
