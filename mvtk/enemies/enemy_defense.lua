-- Enemy hit rules. Resolve is pure; feedback stays at the runtime boundary.
local M = {}

local function inherits(value)
    return value == nil or value == "" or value == "type_default" or value == -1
end

-- Pure merge; defaults are supplied by the event-time runtime boundary.
function M.profile(type_cfg, instance, defaults)
    local result = {}
    for key, value in pairs(defaults or {}) do result[key] = value end
    for key, value in pairs((type_cfg or {}).defense or {}) do
        if not inherits(value) then result[key] = value end
    end
    local authored = (instance or {}).defense or instance or {}
    -- Only these seven fields are instance authoring. Actor state may share
    -- names with other defaults (sounds, margins and Shield timing).
    for _, key in ipairs({"guard", "guard_break", "guard_hits", "guard_open_time",
        "armor_hits", "armor_requires", "rear_damage_mult"}) do
        local value = authored[key]
        if not inherits(value) then result[key] = value end
    end
    return result
end

local function contains(list, tag)
    if not tag then return false end
    if type(list) == "table" then
        for _, value in ipairs(list) do if value == tag then return true end end
    else
        for value in tostring(list or ""):gmatch("[^,%s]+") do
            if value == tag then return true end
        end
    end
    return false
end

local function empty(list)
    return list == nil or list == "" or (type(list) == "table" and next(list) == nil)
end

local function side(state, payload, ctx)
    local pos = ctx.pos or state.pos or {x = 0, y = 0}
    local attacker = ctx.attacker_pos
    if attacker then return attacker.x >= pos.x and 1 or -1 end
    local kx = tonumber(payload.kx) or 0
    return kx > 0 and -1 or (kx < 0 and 1 or 0)
end

function M.resolve(state, payload, ctx)
    ctx = ctx or {}
    local required = state.required_action
    if required and required ~= "" and required ~= "none" and payload.attack_type ~= required then
        return "blocked", "required_action"
    end
    local profile = state._defense or state.defense or {}
    local parry = payload.source_attack == "parry_stun" and (payload.amount or 0) == 0
    local tag = parry and "parry" or payload.attack_type
    local guard = profile.guard or "none"
    local open = (state._guard_open_t or 0) > 0
    -- Keep the Shield-only all-side gate. Explicit guards defer its direction
    -- and breaking tags to the guard rule immediately below.
    if state.shielded and guard == "none" and payload.damage_over_time ~= true
        and not parry and not open and not contains(profile.guard_break, tag) then
        return "blocked", "shield"
    end
    if payload.damage_over_time == true then return "hit", nil, 1 end
    local source_side = side(state, payload, ctx)
    local facing = (tonumber(ctx.facing or state.facing) or 1) < 0 and -1 or 1
    local behind = source_side ~= 0 and source_side ~= facing
    local multiplier = behind and (profile.rear_damage_mult or 1) or 1
    local active = not open and (state.shielded or (guard ~= "none" and not state._guard_pattern))
    if state.shielded and guard == "none" then guard = "all" end
    local pos = ctx.pos or state.pos or {x = 0, y = 0}
    local covered = guard == "all" or (guard == "front" and source_side == facing)
        or (guard == "top" and (tag == "down_strike" or tag == "ground_pound"
            or (ctx.attacker_pos and ctx.attacker_pos.y > pos.y + (profile.guard_top_margin_px or 0))))
    local verdict, reason = "hit", nil
    if active and (covered or parry) then
        if contains(profile.guard_break, tag) then
            state._guard_hits = (state._guard_hits or 0) + 1
            if state._guard_hits >= (profile.guard_hits or 1) then
                state._guard_hits = 0
                state._guard_open_t = profile.guard_open_time or 0
                state.stunned_t = math.max(state.stunned_t or 0, state._guard_open_t)
                verdict, reason = "guard_broken", "guard"
            elseif not parry then return "blocked", "guard", 1 end
        elseif not parry then return "blocked", "guard", 1 end
    end
    if state._armor_remaining == nil then state._armor_remaining = profile.armor_hits or 0 end
    -- A parry stun remains a stun, never an armor hit unless explicitly listed.
    if state._armor_remaining > 0 and (not parry or contains(profile.armor_requires, "parry")) then
        if empty(profile.armor_requires) or contains(profile.armor_requires, tag) then
            state._armor_remaining = state._armor_remaining - 1
            if state._armor_remaining == 0 then verdict, reason = "armor_broken", "armor"
            elseif not parry then return "armored", "armor", 1 end
        elseif not parry then return "armored", "armor", 1 end
    end
    return verdict, reason, multiplier
end

-- Runtime boundary: settings copy only on a hit, never in the timer callback.
function M.context(self, payload)
    local defaults = require("developer.config.runtime_settings").section(
        "enemy_defaults", require "developer.config.enemy_defaults").defense or {}
    if self._defense_life ~= self.patterns or not self._defense then
        self._defense_life = self.patterns
        self._armor_remaining, self._guard_hits, self._guard_open_t = nil, 0, 0
        self._guard_open_timer = nil
    end
    self._defense = M.profile(self.enemy_type_config, self, defaults)
    -- Both coordinates are previous-frame WORLD positions (acceptable for guards).
    local pos = go.get_world_position()
    local attacker
    if payload.source_actor then
        local ok, value = pcall(go.get_world_position, payload.source_actor)
        if ok then attacker = value end
    end
    return {pos = pos, attacker_pos = attacker, facing = self.facing}
end

function M.open_window(self)
    if self._guard_open_timer or (self._guard_open_t or 0) <= 0 then return end
    local Timers = require "mvtk.player.timers"
    Timers.start_window(self, "_guard_open_t", self._guard_open_t, false)
    local life = self.patterns
    self._guard_open_timer = timer.delay(0, true, function(actor, handle, elapsed)
        if actor.patterns ~= life then timer.cancel(handle); return end
        if not require("mvtk.core.pause").get() and Timers.tick_deadline(actor, "_guard_open_t", elapsed) then
            actor._guard_open_timer = nil
            timer.cancel(handle)
        end
    end)
end

function M.feedback(self, verdict, reason, payload, ctx)
    if verdict ~= "blocked" and verdict ~= "armored" and verdict ~= "guard_broken" then return end
    local profile = self._defense or {}
    local sound = verdict == "armored" and profile.armor_sfx
        or (verdict == "guard_broken" and profile.guard_break_sfx or profile.blocked_sfx)
    require("mvtk.audio.audio").sfx(sound or "parry_miss")
    msg.post("#anim", "anim.flash", {color = vmath.vector4(1, 1, 1, 1), duration = 0.1})
    local pos = ctx and ctx.pos or self.pos
    if verdict ~= "guard_broken" then
        require("mvtk.core.gamefeel").damage_number(0, pos, {
            label_key = verdict == "armored" and "combat.armored" or "combat.blocked", target = "enemy"})
    end
    -- Preserve existing Shield-only and Required action feedback; directional
    -- guards and armor add the configured spark through the FX service.
    if reason == "guard" or reason == "armor" then
        require("mvtk.fx.fx").play(profile.guard_spark, pos)
    end
    if verdict == "blocked" and reason ~= "required_action" and payload
        and not payload.damage_over_time and payload.source_attack ~= "parry_stun"
        and payload.attack_type ~= "ranged_attack" and payload.attack_type ~= "bomb"
        and payload.attack_type ~= "throw"
        and require("mvtk.combat.damage_payload").source_is(payload, require("mvtk.core.constants").URL.PLAYER) then
        local direction = side(self, payload, ctx or {})
        if direction ~= 0 then
            msg.post(require("mvtk.core.constants").URL.PLAYER, "mvtk_guard_recoil", {
                vx = direction * (profile.guard_recoil_px_s or 0)})
        end
    end
end

return M
