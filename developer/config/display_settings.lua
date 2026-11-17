-- Picture framing for every game screen, menu and creator tool.
-- The design size comes from game.project display.width/display.height.
-- The 16:9 design area always stays visible; other shapes may show more world.
return {
    -- Hide the world, HUD and notices while a session loads. The opening scene
    -- takes ownership from this opaque cover before revealing its first frame.
    startup = {
        -- Opaque cover colour: RGB channels from 0 to 1; alpha stays 1 while loading.
        color = { r = 0, g = 0, b = 0 },
        -- Seconds to reveal a ready world on New Game or Continue; 0 is instant.
        -- Death restart and fast travel retain their separate fade settings.
        fade_out_seconds = 0.2,
        -- Safety limit in seconds: if loading has not finished by then, the cover
        -- lifts anyway and the log names what it was still waiting for.
        max_wait_seconds = 12,
    },
    -- Bar colour in RGB, with each component from 0 (none) to 1 (full).
    -- Alpha is always opaque so scenes cannot draw into the bars.
    -- Black is the default; for dark grey, use r = 0.08, g = 0.08, b = 0.08.
    letterbox_color = { r = 0, g = 0, b = 0 },
    -- World picture only: HUD, menus, masks, overlays and bars stay sharp.
    -- Neutral values bypass the target and extra draw entirely.
    post = {
        brightness = 1.0, -- 0.5-1.5; 1 unchanged; multiplies player Brightness.
        gamma = 1.0, -- 0.5-2; above 1 lifts shadows, below 1 deepens them.
        saturation = 1.0, -- 0-2; 0 grey, 1 unchanged, 2 stronger colour.
        tint = {
            r = 1, -- 0-1 red multiplier at full filter strength.
            g = 1, -- 0-1 green multiplier at full filter strength.
            b = 1, -- 0-1 blue multiplier at full filter strength.
            strength = 0, -- 0-1; 0 off, 1 full colour filter.
        },
        scanlines = 0, -- 0-1 darkening of alternating lines; 0 off.
        scanline_count = 270, -- 60-1080 lines across picture height; config-only.
        curvature = 0, -- 0-0.25 screen bulge; 0 flat. Pointer coordinates stay flat.
        vignette = 0, -- 0-1 darker corners; 0 off.
        player_brightness = true, -- Show Settings > Graphics > Brightness (50-150%).
    },
    view = {
        -- "expand" shows more world; "letterbox" keeps the design picture with bars.
        mode = "expand",
        -- Hide the space outside smaller clamped or locked rooms with the bar colour.
        mask_outside_room = true,
        -- "safe" keeps HUD inside 16:9; "picture" places it at the picture edges.
        hud_frame = "safe",
        -- "fit" fills smoothly (default); "integer" makes art pixels whole at
        -- Camera > Zoom. Smaller windows fall back to fit; other zone zooms
        -- are not guaranteed whole-pixel. HUD/menus keep their fitted scale.
        scale_rule = "fit",
        -- Offer Settings > Graphics > Wide screens to players only when true.
        player_choice = false,
        -- Narrowest filled shape (width / height): about 4:3; 16:10 is 1.6.
        -- Must be at least 1 and no greater than the design aspect.
        min_aspect = 1.3333,
        -- Widest filled shape: 21:9 screens are about 2.37-2.39. Beyond the limits,
        -- opaque bars return. Must be between the design aspect and 4.
        max_aspect = 2.4,
    },
}
