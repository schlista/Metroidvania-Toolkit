-- Event-time cues shared by enemy windups, shots and boss telegraphs.
local M = {}

-- These executors use common.build_payload's ~= false rule (projectiles
-- also use it on factory shots). Melee differs between its factory and
-- fallback; compound/non-hit patterns have no single inferred classification.
function M.boss_parryable(pattern)
    if pattern.parryable ~= nil then return pattern.parryable == true end
    local kind = pattern.type
    if kind == "projectile" or kind == "aoe" or kind == "beam"
        or kind == "charge" or kind == "grab" or kind == "mine" or kind == "wave" then
        return true
    end
    return nil
end

-- CombatConfig caches creator overrides per revision; never copy runtime
-- sections on the frame path. Missing optional features remain off.
function M.cue(parryable)
    local Config = require "mvtk.combat.config"
    if not Config.feature_enabled or not Config.feature_enabled("parry_tells", false) then return nil end
    local feedback = Config.get().feedback or {}
    local cue
    if parryable then cue = feedback.parry_tell else cue = feedback.unblockable_tell end
    if not cue or (not parryable and cue.enabled ~= true) then return nil end
    local color = cue.color
    if not color then return nil end
    return {color = vmath.vector4(color[1], color[2], color[3], color[4] or 1),
        duration = cue.duration or 0.15, sfx = cue.sfx}
end

function M.windup(self, parryable, cue)
    cue = cue or M.cue(parryable == true)
    if not cue then return end
    msg.post((self and self.anim_url) or "#anim", "anim.flash", {
        color = cue.color, duration = cue.duration,
    })
    if cue.sfx and cue.sfx ~= "" then require("mvtk.audio.audio").sfx(cue.sfx) end
end

function M.projectile(self)
    -- Player and returned shots retain their own art. Only parryable enemy
    -- shots opt into a per-instance material constant (which breaks batching).
    if self.parryable ~= true then return end
    local cue = M.cue(true)
    if not cue then return end
    if self.source_actor == require("mvtk.core.constants").URL.PLAYER then return end
    go.set("#sprite", "tint", cue.color)
end

return M
