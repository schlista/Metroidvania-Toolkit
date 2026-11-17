-- Hint Stone goal mode (G8-13b). mvtk/prefabs/hint_stone.script calls it; it
-- holds no engine calls so tests can drive it directly.
--
-- A stone with Show current goal shows the current goal's hint from
-- developer/config/goals.lua instead of its own body. With Reveal goal target
-- (and goals.hint_reveals_target) it also sets goal_revealed_<id>, which the
-- world map reads through MapTracking.goal_target(). Goal hint cost is the only
-- price: it is charged once per goal (goal_hint_paid_<id>), rereading is free,
-- and no current goal means no charge. Producers send source text or ui_text
-- keys with {currency=} params; only the displaying GUI formats the price.
local Flags = require "mvtk.core.flags"
local M = {}

local function text(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

local function goals()
    -- Call time: goals.lua loads developer config through RuntimeSettings.
    return require "mvtk.game.goals"
end

-- What the stone offers for the current goal, or nil when it shows its body:
-- goal mode off, goals off, no current goal, or neither a hint nor a target to
-- reveal. props: show_current_goal, reveal_goal_target, goal_hint_cost.
function M.offer(props)
    props = props or {}
    if props.show_current_goal ~= true then return nil end
    local Goals = goals()
    local goal = Goals.current()
    if not goal or text(goal.id) == nil then return nil end
    local hint = text(goal.hint)
    local reveal = props.reveal_goal_target == true and Goals.settings().hint_reveals_target ~= false
        and type(goal.target) == "table"
    if not hint and not reveal then return nil end
    local cost = math.floor(tonumber(props.goal_hint_cost) or 0)
    if cost < 0 then cost = 0 end
    return { goal = goal, hint = hint, reveal = reveal, cost = cost,
        due = cost > 0 and not Flags.has("goal_hint_paid_" .. goal.id) }
end

-- The interaction label: the stone's own label, with the price while it is due.
function M.label(base, offer)
    if offer and offer.due then
        return { key = "goal.hint_label_cost", params = { label = base, price = { currency = offer.cost } } }
    end
    return base
end

-- Uses the offer. Returns the popup text and true, or the refusal text and
-- false when the price is due and the player cannot pay; a refusal charges
-- and sets nothing. body: the stone's own text, shown when the goal has no hint.
function M.use(offer, body)
    if not offer then return body, true end
    if offer.due then
        local Wallet = require "mvtk.core.wallet"
        if not Wallet.can_afford(offer.cost) then
            return { key = "goal.hint_refused", params = { price = { currency = offer.cost } } }, false
        end
        local ok = Wallet.spend(offer.cost, "goal_hint")
        if not ok then
            return { key = "goal.hint_refused", params = { price = { currency = offer.cost } } }, false
        end
        Flags.set("goal_hint_paid_" .. offer.goal.id, true)
    end
    if offer.reveal then Flags.set("goal_revealed_" .. offer.goal.id, true) end
    return offer.hint or body, true
end

-- Two numbers that change whenever the offer may change (current goal or any
-- flag), so the script refreshes its label only then, without allocating.
function M.revision()
    return goals().revision(), Flags.revision()
end

return M
