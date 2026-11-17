-- Authored quest actions share the quest owner's transitions and feature gate.
local M = {}
local Ctx
function M.configure(ctx) Ctx = ctx or Ctx end
function M.on_trigger(self, trigger)
    assert(Ctx, "mvtk.game.triggers.quest is not configured")
    return Ctx.Quests.apply_trigger(trigger)
end
return M
