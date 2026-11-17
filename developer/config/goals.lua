-- Optional ordered goals: the player's current main objective.
-- Game Settings > Progression > Goals controls the two switches below.
-- Goals work with Quests off. Read a quest's progress through its mirror flag,
-- for example flags = {quest_completed_desert_hermit_find_relic = true}.
-- Progress only moves forward: once a goal is announced, earlier goals stay
-- finished, even if the player later spends an item a goal needed.
-- Stable goal ids are saved in flags (goal_announced_<id>, and
-- goal_finished_<id> of the last goal once all are done); keep them when
-- changing display text. Ids use letters, digits and underscores only.
return {
    enabled = false, -- Track goals; ships off. Off means no announcements, flags or goal_changed events.
    hint_reveals_target = true, -- A Hint Stone with Reveal goal target marks the current goal's target on the map.
    goals = { -- Ordered list: the current goal is the first one not yet done.
        -- Each goal is a table with:
        --   id: stable text id (letters, digits, underscores).
        --   title: creator source text, at most 120 bytes; collected for translation.
        --   text: optional longer source text for the Journal; collected for translation.
        --   hint: optional source text a Hint Stone in goal mode shows, at most 1024 bytes.
        --     The Hint Stone's own Goal hint cost is the only price; goals have no cost.
        --   done_when: requirements that finish the goal; never empty. Forms (combine freely):
        --     abilities = {dash = true}                 every listed ability is unlocked
        --     items = {old_key = 1}                     at least this many of each item
        --     flags = {met_hermit = true}               flag values (true means set)
        --     resources = {currency = 100}              at least this much currency
        --     counts = {{flags = {"a", "b", "c"}, need = 2}}  need of the listed flags are set
        --     any = {{abilities = {dash = true}}, {items = {old_key = 1}}}  any one alternative
        --   target: optional {objective = "<progression_objective id>"} or {marker = "<marker id>"}.
        --
        -- {id = "find_dash", title = "Find a way across the gap",
        --     text = "The ruins to the east hide something that helps you cross.",
        --     hint = "Look beyond the broken bridge.",
        --     done_when = {abilities = {dash = true}}, target = {objective = "dash_shrine"}},
        -- {id = "open_gate", title = "Open the old gate",
        --     done_when = {any = {{items = {old_key = 1}}, {flags = {gate_lever_pulled = true}}}}},
    },
}
