-- Player extension dispatch. Instance state belongs only to self._host;
-- requiring this module never loads features or captures engine hashes.
local M = {}

local HOOKS = {
    "init", "reset", "restore", "pre_physics", "owns_motion", "post_physics",
    "anim_state", "actions", "on_message", "apply_abilities", "holds_presses",
}

-- Strings only: callers may install a different hash implementation between
-- calls. Keep these in step with the existing player and collider tables.
local PROXIED = {
    "one_way_contact", "external_force", "apply_external_force", "apply_force",
    "apply_movement_modifier", "remove_movement_modifier", "platform_delta",
    "on_conveyor", "off_conveyor",
}
local BODY = {
    "mvtk_apply_damage", "take_damage", "mvtk_take_damage", "enter_water",
    "exit_water", "enter_climb_zone", "exit_climb_zone", "apply_external_force",
    "apply_movement_modifier", "remove_movement_modifier", "platform_delta",
}
local FEET = {
    "one_way_contact", "apply_force", "platform_delta", "on_conveyor", "off_conveyor",
}

-- Shared immutable dispatch metadata contains functions and plain names only.
-- Mutable feature state is allocated separately for every player in init.
local registry

local function feature_list()
    if registry then return registry end
    local list = {}
    for index, feature in ipairs(require "mvtk.player.player_features") do
        list[#list + 1] = { feature = feature, index = index }
    end
    table.sort(list, function(a, b)
        local left, right = a.feature, b.feature
        if (left.order or 0) ~= (right.order or 0) then
            return (left.order or 0) < (right.order or 0)
        end
        if (left.id or "") ~= (right.id or "") then
            return (left.id or "") < (right.id or "")
        end
        return a.index < b.index
    end)
    local result = { hooks = {}, messages = {}, movement_anims = {}, features = {} }
    for _, name in ipairs(HOOKS) do result.hooks[name] = {} end
    for _, entry in ipairs(list) do
        local feature = entry.feature
        local id = feature.id or entry.index
        assert(result.features[id] == nil, "Duplicate player feature id: " .. tostring(id))
        result.features[id] = true
        for _, name in ipairs(HOOKS) do
            if feature[name] then
                local hook = result.hooks[name]
                hook[#hook + 1] = feature[name]
            end
        end
        for name, scope in pairs(feature.messages or {}) do
            assert(type(name) == "string", "Player feature message names must be strings")
            assert(scope == "body" or scope == "feet" or scope == "any",
                "Invalid player feature relay scope: " .. tostring(scope))
            assert(result.messages[name] == nil, "Duplicate player feature message: " .. name)
            result.messages[name] = { scope = scope, handler = feature.on_message }
        end
        for _, state in ipairs(feature.movement_anims or {}) do
            result.movement_anims[state] = true
        end
    end
    registry = result
    return registry
end

function M.init(self, ctx)
    local definitions = feature_list()
    self._host = { hooks = definitions.hooks, messages = definitions.messages, features = {} }
    for id in pairs(definitions.features) do self._host.features[id] = {} end
    require("mvtk.player.player_stats").on_player_reset("init")
    for _, hook in ipairs(self._host.hooks.init) do hook(self, ctx) end
end

function M.reset(self, reason)
    require("mvtk.player.hold_toggles").clear_all(self)
    if not self._host then return end
    require("mvtk.player.player_stats").on_player_reset(reason)
    for _, hook in ipairs(self._host.hooks.reset) do hook(self, reason) end
end

function M.restore(self, message)
    if not self._host then return end
    for _, hook in ipairs(self._host.hooks.restore) do hook(self, message) end
end

function M.pre_physics(self, dt, input)
    require("mvtk.player.hold_toggles").sync(self)
    if not self._host then return end
    for _, hook in ipairs(self._host.hooks.pre_physics) do hook(self, dt, input) end
end

-- A motion hook can also report that it ran ordinary player physics.
function M.owns_motion(self, dt, input)
    if not self._host then return false end
    for _, hook in ipairs(self._host.hooks.owns_motion) do
        local owned, ordinary_motion = hook(self, dt, input)
        if owned then return true, ordinary_motion end
    end
    return false
end

-- True while a feature that owns motion (zip line ride, loaded cannon) reads
-- Jump and Dash itself, so PSTATE neither spends nor buffers those presses and
-- starts no backdash.
function M.holds_presses(self)
    local hooks = self._host and self._host.hooks
    if not hooks then return false end
    for _, hook in ipairs(hooks.holds_presses or {}) do
        if hook(self) then return true end
    end
    return false
end

function M.post_physics(self, dt, input, collision)
    if not self._host then return end
    for _, hook in ipairs(self._host.hooks.post_physics) do hook(self, dt, input, collision) end
end

function M.anim_state(self, state)
    if not self._host then return nil end
    for _, hook in ipairs(self._host.hooks.anim_state) do
        local replacement = hook(self, state)
        if replacement then return replacement end
    end
end

function M.actions(self, input, stunned)
    if not self._host then return end
    for _, hook in ipairs(self._host.hooks.actions) do hook(self, input, stunned) end
end

function M.on_message(self, message_id, message, sender)
    if not self._host then return false end
    for name, route in pairs(self._host.messages) do
        if message_id == hash(name) then
            return route.handler and route.handler(self, message_id, message, sender) or false
        end
    end
    return false
end

-- Ability mapping has no player instance: it runs before PSTATE.init and on
-- later unlock changes. Feature implementations must only edit overrides.
function M.apply_abilities(overrides, base, is_unlocked, is_defined)
    for _, hook in ipairs(feature_list().hooks.apply_abilities) do
        hook(overrides, base, is_unlocked, is_defined)
    end
end

function M.is_movement_anim(state)
    return feature_list().movement_anims[state] == true
end

function M.proxied_messages()
    local result = {}
    for _, name in ipairs(PROXIED) do result[hash(name)] = true end
    for name in pairs(feature_list().messages) do result[hash(name)] = true end
    return result
end

function M.relay_messages(scope)
    assert(scope == "body" or scope == "feet", "Invalid player collider scope")
    local result = {}
    for _, name in ipairs(scope == "body" and BODY or FEET) do result[hash(name)] = true end
    for name, route in pairs(feature_list().messages) do
        if route.scope == scope or route.scope == "any" then result[hash(name)] = true end
    end
    return result
end

return M
