-- Inventory crafting shares the grant grammar and durable exchange transaction.
local M = {}
function M.settings()
    return require("developer.config.runtime_settings").section("crafting", require "developer.config.crafting")
end
function M.enabled() return M.settings().enabled == true end
function M.visible(recipe)
    return not recipe.requires_flag or recipe.requires_flag == "" or require("mvtk.core.flags").has(recipe.requires_flag)
end
function M.recipe(id)
    for _, recipe in ipairs(M.settings().recipes or {}) do if recipe.id == id then return recipe end end
end
function M.status(recipe)
    if not M.enabled() or not recipe or not M.visible(recipe) then return "disabled", {key="crafting.unavailable"} end
    local grants = require "mvtk.game.grants"
    local spec = require "mvtk.game.grant_spec"
    local env = grants.runtime_env()
    if #spec.validate_crafting({enabled=true,recipes={recipe}},env) > 0 then return "disabled", {key="crafting.unavailable"} end
    if grants.is_exhausted(recipe.gives) then return "owned", {key="crafting.owned"} end
    local _, _, entries = spec.validate(recipe.gives, env)
    for _, give in ipairs(entries) do
        if give.kind == "weapon_tier" then
            local state = require "mvtk.combat.weapon_state"
            if not state.enabled() or not state.owns(give.weapon) then
                return "requires", {key="crafting.requires_weapon",params={name={text=env.weapons[give.weapon].name}}}
            end
            if state.tier(give.weapon) ~= give.tier - 1 then
                return "requires", {key="crafting.requires_tier",params={tier=give.tier-1}}
            end
        end
    end
    local affordable, reason = grants.can_afford(recipe.costs)
    if not affordable then return "missing", reason end
    return "craftable"
end
function M.craft(recipe)
    -- Resolve the current catalog entry, never an echoed or stale UI recipe.
    recipe = recipe and M.recipe(type(recipe)=="table" and recipe.id or recipe)
    local status, reason = M.status(recipe)
    if status ~= "craftable" then return false, {code=status,message=reason} end
    return require("mvtk.game.grants").exchange(recipe.costs,recipe.gives,
        {source="crafted",reason="crafted",refuse_if_exhausted=true})
end
return M
