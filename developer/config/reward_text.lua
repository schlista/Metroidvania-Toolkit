-- Reward wording shared by grant previews and delivered notices.
return {
    xp_format = "{amount} XP", -- Whole XP amount in reward previews; translated by the displaying GUI.
    separator = ", ", -- Joins visible entries in a combined notice.
    count_format = "{name} x{count}", -- Item or collectible stacks; keeps input tokens in names intact.
    fast_travel_format = "{name} unlocked", -- {name} is the authored station name when known.
    notice_duration = 2.0, -- Seconds shown by the toast delivery boundary.
    hidden_kinds = { flag = true }, -- Bookkeeping flags have no player-facing notice text.
}
