-- Require-free at load time, like every Inventory provider.
local M = {}
function M.new(deps)
    deps = deps or {}
    local provider = {}
    local function crafting() return deps.crafting or require "mvtk.game.crafting" end
    local function grants() return deps.grants or require "mvtk.game.grants" end
    function provider.title() return {key="inventory.crafting"} end
    function provider.enabled()
        local service = crafting()
        if not service.enabled() then return false end
        for _, recipe in ipairs(service.settings().recipes or {}) do if service.visible(recipe) then return true end end
        return false
    end
    function provider.header_right() return {currency=(deps.inventory or require "mvtk.core.inventory").get_currency()} end
    local function detail(recipe)
        local parts = {{text=recipe.description or ""}}
        local spec = deps.spec or require "mvtk.game.grant_spec"
        local inventory = deps.inventory or require "mvtk.core.inventory"
        local env = grants().runtime_env()
        local entries = spec.parse(recipe.costs)
        for _, cost in ipairs(entries) do
            if cost.kind == "currency" then
                parts[#parts+1] = {key="crafting.have_money",params={have={currency=inventory.get_currency()},need={currency=cost.amount}}}
            elseif cost.kind == "item" then
                local name = spec.item_name(cost.id,env)
                parts[#parts+1] = {key="crafting.have_item",params={name=type(name)=="table" and name or {text=name},
                    have=inventory.count(cost.id),need=cost.count}}
            end
        end
        return {parts=parts,separator="\n"}
    end
    function provider.rows()
        local service, out = crafting(), {}
        if not service.enabled() then return out end
        for _, recipe in ipairs(service.settings().recipes or {}) do
            if service.visible(recipe) then
                local status, reason = service.status(recipe)
                out[#out+1] = {id=recipe.id,label={text=recipe.name},value=grants().describe(recipe.costs),
                    detail=detail(recipe),enabled=status=="craftable",state=status,disabled_reason=reason,
                    confirm={key="crafting.confirm",params={name={text=recipe.name}}}}
            end
        end
        return out
    end
    function provider.on_confirm(ctx,row)
        if not row then return {} end
        local service = crafting()
        local recipe = service.recipe(row.id)
        local ok, result = service.craft(recipe)
        if ok then return {refresh=true,status={key="crafting.done",params={name={text=recipe.name}}}} end
        return {refresh=true,status=type(result.message)=="table" and result.message or {key="crafting.unavailable"}}
    end
    return provider
end
local default = M.new()
default.new = M.new
return default
