components {
  id: "fx_manager"
  component: "/mvtk/fx/fx_manager.script"
}
embedded_components {
  id: "glow_sprite"
  type: "sprite"
  data: "tile_set: \"/developer/assets/atlas/gameplay_visuals.atlas\"\n"
  "default_animation: \"prop_base\"\n"
  "material: \"/developer/materials/glow_sprite.material\"\n"
  "blend_mode: BLEND_MODE_ALPHA\n"
  ""
}
components {
  id: "crit_hit"
  component: "/developer/assets/fx/hit_impact.particlefx"
}
components {
  id: "dash_puff"
  component: "/developer/assets/fx/dash_trail_once.particlefx"
}
components {
  id: "land_puff"
  component: "/developer/assets/fx/jump_dust.particlefx"
}
components {
  id: "unlock_sparkle"
  component: "/developer/assets/fx/collectible_sparkle_once.particlefx"
}
components {
  id: "sparkle"
  component: "/developer/assets/fx/collectible_sparkle_once.particlefx"
}
components {
  id: "ambient_sparkle"
  component: "/developer/assets/fx/ambient_sparkle_once.particlefx"
}
components {
  id: "marker_ping"
  component: "/developer/assets/fx/collectible_sparkle_once.particlefx"
}
components {
  id: "ping"
  component: "/developer/assets/fx/collectible_sparkle_once.particlefx"
}
components {
  id: "wall_break"
  component: "/developer/assets/fx/hit_impact.particlefx"
}
components {
  id: "dust_cloud"
  component: "/developer/assets/fx/jump_dust.particlefx"
}
components {
  id: "secret_reveal"
  component: "/developer/assets/fx/collectible_sparkle_once.particlefx"
}
components {
  id: "death_explosion"
  component: "/developer/assets/fx/death_explosion.particlefx"
}
components {
  id: "boss_phase_transition"
  component: "/developer/assets/fx/boss_phase_transition.particlefx"
}
components {
  id: "rock_crumble"
  component: "/developer/assets/fx/rock_crumble.particlefx"
}
