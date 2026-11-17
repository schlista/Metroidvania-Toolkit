-- Optional extra equipment pickups; ownership stays with existing saved services.
local RuntimeSettings = require "developer.config.runtime_settings"
local Baseline = require "developer.config.random_drops"
local Weapons = require "mvtk.combat.weapon_state"
local Charms = require "mvtk.player.charms"
local Upgrades = require "mvtk.economy.upgrades"
local UpgradeCatalog = require "developer.config.upgrades"
local Ability = require "mvtk.abilities.ability_manager"
local RewardDrops = require "mvtk.collectibles.reward_drops"
local Delivery = require "mvtk.game.delivery"
-- Grants requires the collectible manager, which dispatches here. Bob must not
-- follow this reverse edge; Grants has literal requires in other callers.
local GRANTS_MODULE = "mvtk.game.grants"
local M = {}
local cached, settings_revision

function M.settings()
    local revision = RuntimeSettings.revision()
    if not cached or settings_revision ~= revision then
        cached, settings_revision = RuntimeSettings.section("random_drops", Baseline), revision
    end
    return cached
end

-- Optional state supplies pure catalogs/predicates for deterministic tests.
function M.pool(state)
    state = state or {}
    local config = state.settings or M.settings()
    local weapons, charms = state.weapons or Weapons, state.charms or Charms
    local upgrades, ability = state.upgrades or Upgrades, state.ability or Ability
    local out = {}
    for _, family in ipairs({{enabled=config.weapons, owner=weapons, field="weapons", prefix="weapon_"},
        {enabled=config.charms, owner=charms, field="charms", prefix="charm_"}}) do
        if family.enabled and family.owner.enabled() then
            for _, entry in ipairs(family.owner.settings()[family.field] or {}) do
                if entry.random_drop ~= false and not family.owner.owns(entry.id)
                    and (not entry.requires_ability or entry.requires_ability == ""
                        or ability.is_ability_unlocked(entry.requires_ability)) then
                    out[#out + 1] = family.prefix .. entry.id
                end
            end
        end
    end
    if config.upgrades then
        local entries = (state.upgrade_catalog or UpgradeCatalog).upgrades or {}
        local ids = {}
        for id in pairs(entries) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            if entries[id].random_drop ~= false and not upgrades.is_applied(id) and upgrades.requires_met(id) then
                out[#out + 1] = "upgrade_" .. id
            end
        end
    end
    return out
end

function M.roll(chance, random, state)
    local config = state and state.settings or M.settings()
    chance = chance == nil and config.chance or chance
    if not config.enabled or chance <= 0 then return nil end
    random = random or math.random
    if random() >= chance then return nil end
    local pool = M.pool(state)
    if #pool == 0 then return nil end
    return pool[random(#pool)]
end

function M.on_enemy_defeat(self, position)
    if self._summon_owner then return 0 end
    local kind = M.roll((self.enemy_type_config or {}).random_drop_chance)
    if not kind then return 0 end
    local prefix = RewardDrops.enemy_drop_id(self) .. "_"
    local types = require "developer.config.collectible_types"
    return RewardDrops.spawn(RewardDrops.plan({{type=kind, amount=1}}, types, prefix), position)
end

function M.collect_upgrade(config)
    local Grants = require(GRANTS_MODULE)
    local ok, result = Grants.grant("upgrade:" .. config.upgrade_id,
        {source="pickup", reason="upgrade_pickup", refuse_if_exhausted=true, durable=false})
    local name = {text=config.name}
    if ok then
        Delivery.notice({key="gameplay.upgrade_found", params={name=name}})
        return true
    end
    if result.code == "exhausted" then
        local amount = M.settings().duplicate_currency
        local paid = amount == 0 or Grants.grant("currency:" .. amount,
            {source="pickup", reason="duplicate", durable=false})
        if not paid then return false end
        Delivery.notice({key="gameplay.duplicate_gear", params={name=name, amount={currency=amount}}})
        return true
    end
    if result.code == "prerequisite" then
        Delivery.notice({key="gameplay.upgrade_needs", params={name=name}})
    end
    return false
end

return M
