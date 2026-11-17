-- The main ending and optional other endings. Disabled in the empty toolkit.
-- Use Project > Game Settings... > Ending for conditions, credits, lines and art.
return {
    enabled = false, -- No ending checks or screen while false.
    id = "ending", -- Stable save identity; end_game regions reference this ID.
    condition = "region", -- region, flag, or boss (boss preset/persistent identity).
    flag = "", -- Required existing flag when condition="flag".
    boss_id = "", -- boss_defeated_<boss_id> flag, after defeat cleanup finishes.
    continue_policy = "completed", -- completed shows ending again; explore resumes.
    return_room = "", -- Explore return point: published room ID, world coordinates.
    return_x = 0, -- Blank room uses the last valid saved checkpoint instead.
    return_y = 0, -- Validate placement against the published room before saving.
    title = "Journey complete", -- Completion heading.
    body = "Thank you for playing.", -- Completion body text; newlines supported.
    credits = "Created by you", -- Newline-separated credit entries, paged by the UI.
    music = "", -- Existing music track ID; blank keeps current music.
    artwork = "", -- Animation in completion.gui's creator-owned artwork atlas.
    reward_flag = "", -- Optional permanent flag committed in the completion save.
    reward = "", -- Optional grant text, once per slot with once key ending:<id>.
    -- Complete other endings are checked in list order before the main ending.
    -- Each has its own id, enabled, condition, flag, boss_id, continue_policy,
    -- return_room/x/y, title, body, credits, music, artwork, reward_flag and reward.
    -- requires = {flags={"story_flag"}, bosses={"boss_id"},
    --     completion_percent=100, max_minutes=30} uses ALL requirements.
    -- Percent requires completion tracking; max_minutes=0 means no time limit.
    -- The main ending has no requires and is the fallback when its trigger is met.
    -- A Game Settings endings override replaces this whole list, never merges indices.
    endings = {}, -- Reset Project to Empty clears creator-authored other endings.
    font = "default", -- Font ID declared in the completion GUI resource.
    text_scale = 0.8, -- Text scale for completion and credits screens.
    credits_per_page = 8, -- Controller/keyboard navigable credit lines per page.
}
