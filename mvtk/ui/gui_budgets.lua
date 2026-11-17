-- Per-scene allocations, including disabled templates and live clones.
-- runtime_max excludes authored nodes. Owners update this when adding nodes.
-- Generated-text hosts reserve deferred measurement probes (up to one per new
-- runtime node); completion/extras also reserve their previous draw. No engine
-- cap increase is needed. Other hosts keep their existing live-node bounds.
-- Dynamic world scenes have no demand bound yet and name their responsible owner.
return {
    ["developer/ui/game/startup_cover.gui"] = { runtime_max = 0, cap = 4, owner = "S9-0af (2 static)" },
    ["mvtk/ui/view_mask.gui"] = { runtime_max = 4, cap = 16, owner = "G7-03" },
    ["developer/ui/game/feature_hud.gui"] = { runtime_max = 18, cap = 128, owner = "U-C3-03 / C5-HEAL / G3-F05 / G5-F9 / G5-F1 / G5-F7 / G5-F4 / CMB-12 / G8-05b / G8-13 / WM09 (28 static)" },
    ["developer/ui/shared/mode_hud.gui"] = { runtime_max = 8, cap = 256, owner = "core HUD / G7-09" },
    ["developer/ui/menus/list_menu.gui"] = { runtime_max = 68, cap = 128, owner = "U-C3-02 / C7-U4 (29 static)" },
    ["developer/ui/menus/pause_menu.gui"] = { runtime_max = 0, cap = 256, owner = "U-C3-04" },
    -- Four existing runtime nodes; owners add three per Controls row lacking
    -- authored nodes. The census checks this against the shipped action rows.
    -- Optional player rows count too: 4 + 10 * 3 + 3 focus-preference labels + Wide screens + Brightness + Language.
    -- Accessibility pools eight cloned triples: 40 + 8 * 3 = 64 runtime nodes.
    ["developer/ui/menus/settings_menu.gui"] = { runtime_max = 128, cap = 256, owner = "Settings row owners / G8-01 / C5-HEAL / G7-02 / G7-04b / G7-05e / G7-10b" },
    ["developer/ui/menus/lore_popup.gui"] = { runtime_max = 0, cap = 64, owner = "reader" },
    ["developer/ui/menus/death_menu.gui"] = { runtime_max = 0, cap = 64, owner = "death menu" },
    ["developer/ui/menus/boot_start_screen.gui"] = { runtime_max = 0, cap = 64, owner = "boot menu / WM15 (10 static)" },
    -- The Extras host reuses the completion screen for credits replay (WM15).
    ["developer/ui/menus/extras_viewer.gui"] = { runtime_max = 15, cap = 32, owner = "WM15" },
    ["developer/ui/menus/boot_save_slot_select.gui"] = { runtime_max = 0, cap = 128, owner = "boot saves / G8-11 slot cards, copy and delete confirmation (53 static) / G2-F11 / New Game+" },
    ["developer/ui/game/toast.gui"] = { runtime_max = 1, cap = 16, owner = "toast" },
    ["developer/ui/game/dialogue.gui"] = { runtime_max = 0, cap = 64, owner = "dialogue" },
    ["developer/ui/game/fade.gui"] = { runtime_max = 0, cap = 16, owner = "fade" },
    ["developer/ui/game/boss_hp.gui"] = { runtime_max = 8, cap = 64, owner = "boss frame" },
    ["developer/ui/game/boss_health_bar.gui"] = { runtime_max = 42, cap = 64, owner = "boss group: three slots, five health nodes and two lazy stagger boxes each" },
    -- Original 4 - band removed in G7-13a + caption box + caption text = 5.
    ["developer/ui/game/cutscene_test.gui"] = { runtime_max = 10, cap = 16, owner = "cutscene card / G7-13b" },
    ["developer/ui/game/completion.gui"] = { runtime_max = 15, cap = 64, owner = "completion screen" },
    ["developer/ui/screen_effect_overlay.gui"] = { runtime_max = 0, cap = 16, owner = "screen effects" },
    ["developer/ui/underwater_overlay.gui"] = { runtime_max = 0, cap = 16, owner = "underwater overlay" },
    ["developer/tools/preview/controls.gui"] = { runtime_max = 1, cap = 16, owner = "preview controls" },
    ["mvtk/ui/letterbox_bars.gui"] = { runtime_max = 0, cap = 4, owner = "viewport" },
    -- Shipped max_slots is three: two headings plus three nodes per slot.
    ["mvtk/boot/gui/save_slots.gui"] = { runtime_max = 11, cap = 64, owner = "legacy save slots" },
    -- Twelve shared-list rows (every Dev Menu page, Saves included), plus 24
    -- pooled actor labels and one multiline DPS panel. Headings, template and
    -- the save banner/plate remain authored; none consume runtime allocations.
    ["mvtk/debug/debug_overlay.gui"] = { runtime_max = 37, cap = 128, owner = "G7-14 / G7-15 / G7-16 / G7-17" },
    -- One disabled text template is authored. mvtk/map/map_view.lua POOLS bounds live nodes:
    -- 10 static + 100 G8-06 (24 pages, pages root, detail fog, 32 region labels,
    -- 8 info, 2 cursor, 32 legend = 100) + 200 screenshot markers + 384 POI + 64
    -- travel + 72 G8-07 stamps + 193 G8-08 items = 1023. Reserve up to 1023
    -- pending probes as well: 2046 runtime + 1 template <= max_nodes 2048.
    -- Pools are reused; map-image deletion happens only on finalization.
    ["developer/ui/menus/world_map.gui"] = { dynamic = true, runtime_max = 2046, cap = 2048, owner = "G8-06 / G8-07 / G8-08" },
    ["developer/ui/game/minimap.gui"] = { dynamic = true, cap = 4096, owner = "G8-06" },
    ["developer/ui/darkness_overlay.gui"] = { dynamic = true, cap = 512, owner = "lighting" },
    ["mvtk/editor_host/gui/layout_editor.gui"] = { dynamic = true, cap = 4096, owner = "Layout Editor" },
}
