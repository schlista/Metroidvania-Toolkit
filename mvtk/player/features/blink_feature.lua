local M = { id = "blink", order = 30 }

local function config(self)
    return self._cfg.blink or {}
end

function M.pre_physics(self)
    local state = self._host.features.blink
    state.dashing = state.dashing or (self._dash_t or 0) > 0
    state.sliding = state.sliding or (self._slide_t or 0) > 0
    local req = self._teleport_request
    self._teleport_request = nil
    if not req then return end
    if require("mvtk.core.pause").get() or self._in_water or self._in_climb
        or self._is_dead or (self._stun_t or 0) > 0 or self._ledge_kinematic
        or self._pound_active or self._compact_active or self._block_grab or self._room_arrival then return end
    local age = (self._frame_counter or 0) - (req.frame or -2)
    if age < 0 or age > 1 then return end
    local cfg = config(self)
    local grace = (self._teleport_chain_t or 0) > 0
    local air = cfg.from_air_dash ~= false and ((self._dash_t or 0) > 0 or (grace and state.chain == "dash"))
    local slide = cfg.from_ground_slide ~= false and self.grounded
        and ((self._slide_t or 0) > 0 or (grace and state.chain == "slide"))
    if not (air or slide) or not self._ability_can_use or not self._ability_can_use("blink") then return end
    local dir = require("mvtk.core.direction8").quantize(req.x, req.y, {
        mode = cfg.diagonal_snap == false and "free" or "eight", allow_vertical = cfg.allow_vertical,
    }) or {x = self.facing == -1 and -1 or 1, y = 0}
    local Rooms = require "mvtk.map.streaming.room_manager"
    local room = Rooms.get_current_room()
    if not room then return end
    local tile = require("mvtk.core.util").require_config("developer.config.tile_settings")
    local groups = {}
    for _, name in ipairs(require("mvtk.core.collision_groups").FAMILIES.teleport_destination_checks.raycasts) do
        groups[#groups + 1] = hash(name)
    end
    local from = vmath.vector3(self.pos)
    local count = math.max(2, math.floor(cfg.search_steps or 12))
    local distance = math.max(0, cfg.distance_px or 0)
    local ratio = math.max(0, math.min(1, cfg.min_distance_ratio or 0.25))
    local destination
    for i = 0, count - 1 do
        local length = distance * (1 - (1 - ratio) * i / (count - 1))
        local candidate = vmath.vector3(from.x + dir.x * length, from.y + dir.y * length, from.z)
        if length > 0 and Rooms.get_room_for_position(candidate) == room
            and require("mvtk.player.box_sweep").sweep(self, from, candidate, groups,
                math.min(tile.width, tile.height) * 0.5) then
            destination = candidate
            break
        end
    end
    if not destination then return end
    local PSTATE = require "mvtk.player.player_state"
    -- The keep-rope option applies to an attached rope; travel always cancels.
    if cfg.cancel_grapple ~= false or self._grapple_hook then PSTATE.cancel_grapple(self) end
    local vx = self.vx
    PSTATE.end_dash_slide(self)
    self.pos.x, self.pos.y = destination.x, destination.y
    if self._previous_frame_position then
        self._previous_frame_position.x, self._previous_frame_position.y = destination.x, destination.y
    end
    self.vx, self.vy = cfg.keep_horizontal_speed and vx or 0, cfg.exit_vertical_speed or 0
    self._teleport_chain_t = 0
    state.dashing, state.sliding, state.chain = false, false, nil
    if (cfg.iframes or 0) > 0 then
        require("mvtk.player.player_stats").set_source("ability:blink", {invulnerable = true}, {duration = cfg.iframes})
    end
    self._ability_use("blink")
    local FX = require "mvtk.fx.fx"
    FX.play(cfg.fx_out, from)
    FX.play(cfg.fx_in, destination)
    if cfg.sound and cfg.sound ~= "" then require("mvtk.audio.audio").sfx(cfg.sound) end
end

function M.post_physics(self, dt)
    if require("mvtk.core.pause").get() then return end
    local state, cfg = self._host.features.blink, config(self)
    self._teleport_chain_t = math.max(0, (self._teleport_chain_t or 0) - (dt or 0))
    local dashing, sliding = (self._dash_t or 0) > 0, (self._slide_t or 0) > 0
    if state.dashing and not dashing and cfg.from_air_dash ~= false then
        self._teleport_chain_t, state.chain = cfg.chain_grace or 0.08, "dash"
    elseif state.sliding and not sliding and self.grounded and cfg.from_ground_slide ~= false then
        self._teleport_chain_t, state.chain = cfg.chain_grace or 0.08, "slide"
    end
    state.dashing, state.sliding = dashing, sliding
    if self._teleport_chain_t <= 0 then state.chain = nil end
    local active = (require("mvtk.player.player_stats").remaining("ability:blink") or 0) > 0
    if active or state.hud then
        local text = active and "Blink" or (self._last_mode or "")
        pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_mode"), {
            mode = text,
        })
    end
    state.hud = active
end

function M.reset(self)
    self._teleport_request, self._teleport_chain_t = nil, 0
    self._host.features.blink = {}
    require("mvtk.player.player_stats").clear_source("ability:blink")
    self._last_mode = nil -- The ordinary movement update restores its HUD label.
end

return M
