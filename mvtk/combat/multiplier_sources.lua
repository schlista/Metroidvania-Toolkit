-- Static source owners must be literal requires for the resource bundler.
-- Scoped runtime sources register with the service instead.
return {
    require "mvtk.core.difficulty",
    require "mvtk.player.player_stats",
    require "mvtk.game.new_game_plus",
    require "mvtk.player.assist",
}
