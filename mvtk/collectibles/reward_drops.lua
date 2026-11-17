-- mvtk/collectibles/reward_drops.lua
-- Turns reward contents into real pickups.
--
-- CollectibleManager.spawn_collectible records bookkeeping, while this module
-- materialises the pickups. Rewards are runtime drops (not Tiled objects), from
-- the room manager's collectible factory, exactly like enemy drops.
local M = {}
local Settings = require "developer.config.reward_drop_settings"

M.FACTORY_URL = "main:/room_manager#collectible_factory"
M.SPACING = Settings.spacing

--- A new pickup id for an enemy's drop: the id of one drop, or with "_" the
-- prefix of a planned set. Bumps the enemy's self._drop_counter and hashes
-- "enemy_drop:<spawn_id, else the instance id>:<counter>:<os.time()>".
-- Call it from the enemy's own script (go.get_id). Returns the hash as hex.
function M.enemy_drop_id(self)
    self._drop_counter = (self._drop_counter or 0) + 1
    local seed = string.format("enemy_drop:%s:%d:%d", tostring(self.spawn_id or go.get_id()),
        self._drop_counter, os.time())
    local id_hash = hash(seed)
    return hash_to_hex and hash_to_hex(id_hash) or tostring(id_hash)
end

--- Expand { {type=, amount=}, ... } into individual drops with stable ids.
-- Currency types become ONE pickup worth amount x value (so "currency:25" is
-- 25 coins, not 25 objects); other types spawn `amount` separate pickups.
-- @param items             list of { type = string, amount = number }
-- @param collectible_types developer/config/collectible_types.lua table
-- @param id_prefix         stable prefix, e.g. "chest_pt4_7_chest_loot_"
function M.plan(items, collectible_types, id_prefix)
    local drops = {}
    local n = 0
    for _, item in ipairs(items or {}) do
        local kind = item and item.type
        if type(kind) == "string" and kind ~= "" then
            local def = type(collectible_types) == "table" and collectible_types[kind] or nil
            local count = math.max(1, math.floor(tonumber(item.amount) or 1))
            if type(def) == "table" and def.category == "currency" then
                n = n + 1
                drops[#drops + 1] = { type = kind, value = count * (tonumber(def.value) or 1), id = id_prefix .. n }
            else
                for _ = 1, count do
                    n = n + 1
                    drops[#drops + 1] = { type = kind, id = id_prefix .. n }
                end
            end
        end
    end
    return drops
end

--- Horizontal spread offset (px) for drop `index` of `total`.
function M.offset_x(index, total, spacing)
    return (index - ((total or 1) + 1) / 2) * (spacing or M.SPACING)
end

--- Spawn planned drops above `origin` (vector3). Already-collected ids are
-- skipped. opts.config pre-registers owned runtime loot, like enemy drops;
-- active ids also suppress duplicate sets before pickup init runs.
-- Returns the number of pickups created.
function M.spawn(drops, origin, opts)
    opts = opts or {}
    local ok_mgr, CollectibleManager = pcall(require, "mvtk.collectibles.collectible_manager")
    local url = msg.url(opts.factory_url or M.FACTORY_URL)
    local created = 0
    for i, drop in ipairs(drops or {}) do
        local collected = ok_mgr and CollectibleManager and CollectibleManager.is_collected
            and CollectibleManager.is_collected(drop.id)
        local active = opts.config and ok_mgr and CollectibleManager and CollectibleManager.get_collectible
            and CollectibleManager.get_collectible(drop.id)
        if not collected and not active then
            local pos = vmath.vector3(
                origin.x + M.offset_x(i, #drops, opts.spacing),
                origin.y + (opts.lift or Settings.lift),
                origin.z or 0)
            local props = {
                collectible_type = drop.type,
                collectible_id = drop.id,
            }
            if drop.value then props.amount = drop.value end
            local registered = nil
            if opts.config then
                local config = {}
                for key, value in pairs(opts.config) do config[key] = value end
                config.id, config.value = drop.id, drop.value or config.value
                -- These GOs live in main, outside the streamed room roots.
                config.runtime_reward_drop = true
                config.respawns = false
                registered = ok_mgr and CollectibleManager
                    and CollectibleManager.spawn_collectible(drop.type, pos, config)
            end
            local ok, err = false, "collectible registration refused"
            if not opts.config or registered then
                ok, err = pcall(factory.create, url, pos, nil, props, 1)
            end
            if ok then
                created = created + 1
            else
                if registered then CollectibleManager.unregister_collectible(registered) end
                print(string.format("[REWARD_DROPS] Failed to spawn '%s': %s", tostring(drop.type), tostring(err)))
            end
        end
    end
    return created
end

return M
