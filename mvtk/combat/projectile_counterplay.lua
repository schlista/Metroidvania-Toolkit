-- Runtime edges for projectile counterplay. Settings are revision-cached by
-- CombatConfig; overlap checks never copy creator overrides each frame.
local Config = require "mvtk.combat.config"
local C = require "mvtk.core.constants"
-- Not a literal require: attack_executor requires this module, and Bob refuses require cycles.
local EXECUTOR_MODULE = "mvtk.combat.attack_executor"
local M = {}

function M.mode(value)
    if not Config.feature_enabled("cut_projectiles", false)
        and not Config.feature_enabled("parry_reflects", false) then return "none" end
    if value == "none" or value == "reflect" then return value end
    return "destroy"
end

function M.damage_mult(value)
    local n = tonumber(value)
    if n and n >= 0 then return n end
    return (Config.get().projectiles or {}).reflect_damage_mult or 1
end

function M.feedback(pos)
    local cfg = Config.get().projectiles or {}
    require("mvtk.fx.fx").play(cfg.cut_fx or "hit_impact", pos)
    require("mvtk.audio.audio").sfx(cfg.cut_sfx or "hit_projectile")
end

function M.direction(source, pos, fallback_x, fallback_y)
    local ok, shooter = pcall(go.get_world_position, source)
    local dx, dy = fallback_x or -1, fallback_y or 0
    if ok and shooter then dx, dy = shooter.x-pos.x, shooter.y-pos.y end
    local len = math.sqrt(dx*dx + dy*dy)
    if len == 0 then return -1, 0 end
    return dx/len, dy/len
end

function M.cut(self, pos)
    if self._spent or not Config.feature_enabled("cut_projectiles", false)
        or self.deflect == nil or self.deflect == "none"
        or require("mvtk.combat.damage_payload").source_is(self.source_actor, C.URL.PLAYER) then return false end
    if not require("mvtk.combat.active_hitboxes").first_overlap(pos.x, pos.y, 0, 0) then return false end
    self._spent = true
    M.feedback(pos)
    if self.deflect == "reflect" then
        require(EXECUTOR_MODULE).reflect_projectile(self, {
            speed=self.speed, visual=self.projectile_visual, damage=self.damage,
            damage_mult=self.reflect_damage_mult, damage_type=self.damage_type,
            source_actor=self.source_actor, fallback_x=-self.vel.x, fallback_y=-self.vel.y,
        })
    end
    go.delete(".")
    return true
end

return M
