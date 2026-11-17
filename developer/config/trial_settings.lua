-- Combat trial defaults. Place a trial pedestal and a linked repeatable
-- Encounter to use these settings. No trial starts without its baked host.
return {
    countdown = 3, -- Seconds before the linked Encounter receives its start signal.
    restore_health = true, -- Restore starting health after success; failure always restores it.
    autosave_on_clear = true, -- Save the result and first-clear reward in one batch.
    return_fade_out = 0.4, -- Seconds fading out for a safe return after failure.
    return_fade_in = 0.4, -- Seconds fading in after the arrival service returns the player.
    ranks = { -- Best rank first. Names are creator text, collected for translation.
        {name="Gold"}, -- First threshold: highest rank.
        {name="Silver"}, -- Second threshold.
        {name="Bronze"}, -- Third threshold.
    },
    start_sfx = "", -- Optional sound_bank.lua id when the countdown starts; blank is silent.
    success_sfx = "", -- Optional sound_bank.lua id on success.
    fail_sfx = "", -- Optional sound_bank.lua id on failure.
    result_duration = 4, -- Seconds the trial result HUD and failure toast remain visible.
}
