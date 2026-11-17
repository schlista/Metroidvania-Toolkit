-- Countdown events: escape sequences after a story event, and optional timed
-- courses with best times. One countdown runs at a time.
--
-- How a countdown behaves:
--   * The clock keeps running through doors and room changes.
--   * It holds while the pause menu, a dialogue or a cutscene is open.
--   * It never survives a load: a death, Restart, Load or Quit to title ends it.
--   * While it runs, the flag countdown_<id>_active is set. Give objects or
--     tile layers appear_when / remove_when = countdown_<id>_active to change
--     the world during the run (alarm art, sealed doors).
--   * Finishing sets finish_flag and, when best_time is on, saves the best time
--     in tenths of a second as the flag countdown_best_<id>.
--
-- Ways to start one:
--   * start_when: set a flag (a boss defeat flag, a lever's set_flag_on, a
--     dialogue or cutscene trigger's set_flag) and name it here. The countdown
--     starts when the condition becomes true.
--   * A Countdown Zone placed in Tiled with role "start" (finish and cancel
--     zones end it).
--
-- Countdown ids are saved in flag names: use letters, digits and underscores,
-- and keep an id when you change its label.
return {
    warning_sfx = "", -- sound_bank.lua id played at each warning time; blank is silent.
    finish_sfx = "", -- sound_bank.lua id played when a countdown is finished; blank is silent.
    fail_sfx = "", -- sound_bank.lua id played when time runs out; blank is silent.
    tenths_below = 10, -- The clock shows tenths of a second below this many seconds (0 to 60).
    autosave_on_finish = true, -- Save the finish flag, best time and reward in one save.
    return_fade_out = 0.4, -- Seconds fading out when a restart timeout moves the player back.
    return_fade_in = 0.4, -- Seconds fading in after that move.
    result_duration = 3, -- Seconds the finish time or failure message stays on screen.
    countdowns = { -- One entry per countdown, keyed by its id.
        -- Each entry may set:
        --   label: creator source text shown above the clock; collected for translation.
        --   duration: seconds on the clock; must be above 0.
        --   start_when: condition that starts it (same text as appear_when, for
        --     example "boss_defeated_guardian" or "met_hermit, !escape_done").
        --     Blank means only a start zone starts it.
        --   on_timeout: what happens at zero:
        --     "death"       the player dies and reloads the last save.
        --     "restart"     the player returns to where it started and the clock restarts.
        --     "return_safe" the player returns to safe ground through hazard returns;
        --                   with hazard returns off (Game Settings) this kills instead.
        --   finish_flag: flag set on finishing; blank means countdown_cleared_<id>.
        --   reward: grant text paid once, on the first finish (for example "currency:50").
        --   repeatable: true lets a finished countdown start again (timed courses).
        --   best_time: true saves the best finish time (default true).
        --   music: music track id played during the run; blank keeps the room music.
        --     Boss and champion music still take priority.
        --   tint: optional screen tint {r = 1, g = 0, b = 0, a = 0.15}, values 0 to 1.
        --   block_saves: true refuses saves during the run (default true). A save
        --     point then reports that it could not save.
        --   block_travel: true refuses fast travel and warp statues during the run (default true).
        --   warnings: seconds left at which warning_sfx plays (default {10, 5}).
        --
        -- A harmless sample: it has no start_when, so it starts only from a
        -- Countdown Zone that names it.
        sample_course = {
            label = "Timed course", -- Shown above the clock.
            duration = 90, -- Ninety seconds to reach the finish zone.
            start_when = "", -- Only a start zone starts this course.
            on_timeout = "restart", -- Back to the start zone with a fresh clock.
            finish_flag = "", -- Uses countdown_cleared_sample_course.
            reward = "", -- No reward.
            repeatable = true, -- Run the course again for a better time.
            best_time = true, -- Keep the best time.
            music = "", -- Keep the room music.
            block_saves = true, -- No saving mid-run.
            block_travel = true, -- No fast travel mid-run.
            warnings = {10, 5}, -- Warning sound at 10 and 5 seconds left.
        },
    },
}
