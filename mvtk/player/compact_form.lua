-- Crawl body and entry burst. All mutable state belongs to the player's host.
-- Not a literal require: player_state requires this module, and Bob refuses require cycles.
local PLAYER_STATE_MODULE = "mvtk.player.player_state"
local Timers = require "mvtk.player.timers"
local M = {}

local function state(self)
    return self._host and self._host.features.compact_form
end

local function config(self)
    return self._cfg.compact_form or {}
end

local function swap(self, compact)
    local Util = require "mvtk.core.util"
    if not Util.component_exists("#co_compact", "mass") then return end
    Util.post_component_enabled("#co", not compact)
    Util.post_component_enabled("#co_compact", compact)
end

local function apply_body(self, saved)
    self.collider_half_width = saved.width
    self.collider_half_height = saved.height - saved.reduction
    self.foot_floor_adjust = saved.foot - saved.reduction
    self._wall_half_width = saved.width
    local ctx = self._bone_physics
    if ctx then
        ctx.foot_floor_adjust = saved.ctx_foot - saved.reduction
        ctx.head_offset = saved.head and (saved.head - saved.reduction) or nil
    end
end

function M.init(self)
    -- Spine prototypes deliberately have no compact component.
    if require("mvtk.core.util").component_exists("#co_compact", "mass") then
        require("mvtk.core.util").post_component_enabled("#co_compact", false)
    end
end

function M.enter(self)
    local s = state(self)
    if not s or self._compact_active or not self.grounded
        or require("mvtk.core.pause").get() or self._is_dead or (self._stun_t or 0) > 0
        or self._in_water or self._in_climb or self._grapple_active or self._pound_active
        or self._ledge_kinematic or self._ledge_hanging or self._room_arrival
        or self._attack or (self._combat and self._combat.current) or self._block_grab
        or not self._ability_can_use or not self._ability_can_use("compact_form") then return false end
    if self._spine_physics_active or not require("mvtk.core.util").component_exists("#co_compact", "mass") then
        if not s.warned then
            print("[COMPACT_FORM] Requires a compact collider and collider-only player physics")
            s.warned = true
        end
        return false
    end
    local cfg, ctx = config(self), self._bone_physics or {}
    s.body = { width = self.collider_half_width, height = self.collider_half_height,
        foot = self.foot_floor_adjust or 0, ctx_foot = ctx.foot_floor_adjust or 0, head = ctx.head_offset }
    s.body.reduction = s.body.height * math.max(0, math.min(0.9, cfg.height_reduction_ratio or 0.45))
    require(PLAYER_STATE_MODULE).end_dash_slide(self)
    self._super_jump_ready = false
    local charge = self._host.features.super_jump
    if charge then charge.charge, charge.grace = 0, 0 end
    Timers.clear_window(self, "_jump_buffer_t")
    Timers.clear_window(self, "_coyote_t")
    self._teleport_request, self._teleport_chain_t = nil, 0
    self._compact_active = true
    self._compact_mode_text = "Compact"
    Timers.start_window(s, "roll", math.max(0, cfg.roll_time or 0.25), true)
    s.direction = self.facing == -1 and -1 or 1
    apply_body(self, s.body)
    swap(self, true)
    require("mvtk.player.player_stats").set_source("ability:compact_form",
        { speed_mult = math.max(0.25, math.min(3, cfg.move_speed_mult or 0.6)) }, { layer = "temporary" })
    if cfg.roll_iframes and s.roll > 0 then
        require("mvtk.player.player_stats").set_source("ability:compact_form_roll",
            { invulnerable = true }, { layer = "temporary", duration = s.roll, reference_window = true })
    end
    if self._ability_use then self._ability_use("compact_form") end
    return true
end

function M.has_headroom(self)
    local s = state(self)
    if not self._compact_active or not s or not s.body then return true end
    local saved = s.body
    local bounds = require "mvtk.player.collider_bounds"
    local compact_head = bounds.top(self, "#co_compact")
    local standing_head = bounds.top(self, "#co")
    local groups = { hash("solid"), hash("world") } -- One-way platforms do not obstruct standing.
    for _, sample in ipairs({ -1, 0, 1 }) do
        local x = self.pos.x + sample * saved.width
        -- Start in the open compact body: a ray starting inside a ceiling ignores it.
        if physics.raycast(vmath.vector3(x, self.pos.y + compact_head - 2, self.pos.z or 0),
            vmath.vector3(x, self.pos.y + standing_head, self.pos.z or 0), groups) then return false end
    end
    return true
end

function M.end_roll(self)
    local s = state(self)
    self._compact_roll_exit = nil
    s.roll_travel = nil
    Timers.clear_window(s, "roll")
    require("mvtk.player.player_stats").clear_source("ability:compact_form_roll")
end

function M.stand(self, force)
    local s = state(self)
    if not self._compact_active then return true end
    if not force and not M.has_headroom(self) then return false end
    local saved = s.body
    self.collider_half_width, self.collider_half_height = saved.width, saved.height
    self.foot_floor_adjust, self._wall_half_width = saved.foot, saved.width
    if self._bone_physics then
        self._bone_physics.foot_floor_adjust, self._bone_physics.head_offset = saved.ctx_foot, saved.head
    end
    self._compact_active, self._compact_mode_text = nil, nil
    self._compact_roll_exit = nil
    s.body, s.roll_travel = nil, nil
    Timers.start_window(s, "roll", 0)
    swap(self, false)
    require("mvtk.player.player_stats").clear_source("ability:compact_form")
    require("mvtk.player.player_stats").clear_source("ability:compact_form_roll")
    return true
end

function M.jump(self)
    -- Jump is a stand request. Optional compact jumping keeps the small body.
    if M.stand(self) then return true end
    if config(self).allow_jump and self.grounded then
        self.vy, self.grounded = self._jump_speed, false
        self._jump_cut_pending = true
        Timers.clear_window(self, "_coyote_t")
        Timers.clear_window(self, "_jump_buffer_t")
        return true
    end
    return false
end

function M.pre_physics(self, dt, input)
    self._compact_roll_exit = nil
    if require("mvtk.core.pause").get() then return end
    if not self._compact_active then return end
    if self._in_water or (input and (input.move_y or 0) > 0.5) then
        if M.stand(self) then return end
    end
    local s = state(self)
    s.roll_travel = nil
    if (s.roll or 0) > 0 then
        local active, travel, offset = Timers.step_window(s, "roll", dt)
        if active then
            s.roll_travel = travel
        elseif offset and not self._is_dead and (self._stun_t or 0) <= 0 then
            self._compact_roll_exit = { offset = offset, dx = travel > 0 and self.vx * travel or nil }
        end
    end
end

function M.owns_motion(self, dt, input)
    local s = state(self)
    if not self._compact_active or not s or (s.roll or 0) <= 0
        or self._in_water or require("mvtk.core.pause").get() then return false end
    -- Run ordinary timers, gravity and HUD once, then impose the burst speed.
    -- The host skips player.script's normal PSTATE update when this returns true.
    require(PLAYER_STATE_MODULE).update(self, dt, input)
    if not self._is_dead and (self._stun_t or 0) <= 0 then
        self.vx = (self._cfg.walk_speed or 1200) * (config(self).roll_speed_mult or 1) * s.direction
        local travel = s.roll_travel or dt
        self._move_dx_correction = travel ~= dt and self.vx * (travel - dt) or nil
        self.facing = s.direction
    end
    return true, true
end

function M.reset(self, reason)
    self._compact_roll_exit = nil
    local s = state(self)
    if reason == "teleport" and self._compact_active and s and s.body then
        -- reset_motion_state has already restored base halves. Never shrink twice.
        apply_body(self, s.body)
        swap(self, true)
        M.end_roll(self)
        return
    end
    M.stand(self, true)
    M.init(self)
end

-- Loading this service at boot exposes the optional binding before a player spawns.
if require("developer.config.abilities").abilities.compact_form then
    require("mvtk.core.input_bindings").show_row("morph")
end

return M
