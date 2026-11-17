-- developer/config/narrative/dialogues.lua
-- ============================================================================
-- Dialogue Definitions
-- ============================================================================
-- Each key is a dialogue sequence ID. Each sequence is an array of lines.
--
-- LINE FIELDS:
--   speaker   (string)  Speaker name displayed above the text.
--   text      (string)  Dialogue text content.
--   condition (table)   Optional. Skip this line unless the condition passes.
--                        { flag = "key" }            -- requires flag to be set
--                        { flag = "key", invert = true } -- requires flag NOT set
--                        { ability = "double_jump" } -- requires ability unlocked
--                        { quest = "id", state = "completed" } -- exact quest state
--                        { quest_step = "id.return" } -- current named step
--                        Quest state defaults to active; invert also works on quest checks.
--                        Quest checks need Quests on and a known quest id. A step check
--                        matches active or completed (pending turn-in), never failed/turned_in.
--   quest_start   (string) Optional quest id to start when this line is displayed.
--   quest_advance (string) Optional "id" (current step) or "id.step" (matching step only).
--   quest_turn_in (string) Optional quest id; rewards pay once through the quest service.
--   quest_fail    (string) Optional quest id to fail. All quest actions are inert while off.
--                        Choices accept these same four fields; they run on selection.
--                        Actions run after set_flag, in start/advance/turn-in/fail order.
--   set_flag  (string)  Optional. Sets a game flag when this line is displayed.
--   flag_value (any)    Optional. Value for set_flag (nil and false both write true).
--   choices   (array)   Optional. Presents player choices (up to 4). Each choice:
--                        { text = "Label", ["goto"] = "sequence_id" }
--                        { text = "Label", set_flag = "key" }  -- can also set flags
--                        { text = "Cancel" }  -- no goto = closes dialogue
--                        goto is a Lua keyword: write it as ["goto"], or the build stops.
--   next      (string)  Optional. After this line, jump to another sequence ID.
--
-- QUEST EXAMPLE (after enabling Quests in Game Settings > Progression):
--   Add quest_turn_in = "desert_hermit_find_relic" to a line in
--   desert_hermit_complete to pay the shipped quest reward on return.
--   If a Quest Trigger advances the find step without setting the relic flag,
--   change the first desert_hermit_talk line's condition to
--   { quest = "desert_hermit_find_relic", state = "completed" } for that test.
--   For a custom dialogue-start quest, set start.mode = "dialogue" in quests.lua
--   and put quest_start = "your_quest" on its accept choice.
--   Quest actions need no additional NPC fields. Conditions filter lines only.
--
-- EXAMPLE:
--   npc_guard = {
--     { speaker = "Guard", text = "Halt! State your business.",
--       choices = {
--         { text = "I'm just passing through.", ["goto"] = "guard_pass" },
--         { text = "I have the king's seal.",   ["goto"] = "guard_seal", set_flag = "showed_seal" },
--       }},
--   },
--   guard_pass = {
--     { speaker = "Guard", text = "Very well. Move along." },
--   },
--   guard_seal = {
--     { speaker = "Guard", text = "My apologies! Right this way.", condition = { flag = "has_kings_seal" } },
--     { speaker = "Guard", text = "That's a forgery! Guards!",     condition = { flag = "has_kings_seal", invert = true } },
--   },
-- ============================================================================

local M = {
  -- Vendor greetings use the same source-text translation path as other dialogue.
  merchant_greeting = {
    { speaker = "Merchant", text = "Welcome. Take a look at my supplies." },
  },
  alchemist_greeting = {
    { speaker = "Alchemist", text = "Fresh potions, ready for your next journey." },
  },
  intro = {
    { speaker = "Hero", text = "Where am I? This place... feels different." },
    { speaker = "Guide", text = "Welcome, traveler. Ahead lies the Factory biome." },
    { speaker = "Hero", text = "Then I should move. There's no turning back." },
  },

  ---------------------------------------------------------------------------
  -- Desert Hermit relic dialogue
  ---------------------------------------------------------------------------
  -- Main NPC dialogue (branches on saved story flags via conditions)
  desert_hermit_talk = {
    -- Branch 1: Relic found — jump to the reward conversation
    { speaker = "Desert Hermit",
      text = "You found it! My relic... I can feel its warmth again.",
      condition = { flag = "desert_hermit_relic_found" },
      next = "desert_hermit_complete" },

    -- Branch 2: Relic search underway — simple reminder
    { speaker = "Desert Hermit",
      text = "Still searching? The relic rests deep in the ruins to the east. Watch for the spike traps.",
      condition = { flag = "desert_hermit_quest_given" } },

    -- Branch 3: First meeting (conversation not yet started)
    { speaker = "Desert Hermit",
      text = "Halt, traveler! I am glad to see another soul brave these scorching wastes.",
      condition = { flag = "desert_hermit_quest_given", invert = true } },
    { speaker = "Desert Hermit",
      text = "I once kept a sacred relic in the ruins to the east, but I have grown too old and frail to retrieve it.",
      condition = { flag = "desert_hermit_quest_given", invert = true } },
    { speaker = "Desert Hermit",
      text = "Would you bring it back to me?",
      condition = { flag = "desert_hermit_quest_given", invert = true },
      choices = {
        { text = "I'll find your relic.", ["goto"] = "desert_hermit_accept" },
        { text = "Not right now." },
      } },
  },

  -- Player agrees to search for the relic
  desert_hermit_accept = {
    { speaker = "Desert Hermit",
      text = "Wonderful! Head east through the ruins. The relic glows with a faint blue light — you will know it when you see it.",
      set_flag = "desert_hermit_quest_given" },
    { speaker = "Desert Hermit",
      text = "Be careful of the hazards along the way. I will wait right here." },
  },

  -- Relic recovery follow-up
  desert_hermit_complete = {
    { speaker = "Desert Hermit",
      text = "You have my eternal gratitude, traveler. The desert remembers those who show kindness to strangers." },
    { speaker = "Desert Hermit",
      text = "You have done an old soul a kindness. May the road ahead remember you kindly." },
  },

  ---------------------------------------------------------------------------
  -- Desert Coyote relic dialogue
  ---------------------------------------------------------------------------
  desert_coyote_talk = {
    { speaker = "Desert Coyote",
      text = "Easy now. I do not bite unless the dunes demand it.",
      condition = { flag = "desert_coyote_quest_given", invert = true } },
    { speaker = "Desert Coyote",
      text = "I lost the charm I call my heart in the broken ruins nearby. Without it, every night feels colder.",
      condition = { flag = "desert_coyote_quest_given", invert = true } },
    { speaker = "Desert Coyote",
      text = "Will you track it down for me?",
      condition = { flag = "desert_coyote_quest_given", invert = true },
      choices = {
        { text = "I'll help you.", ["goto"] = "desert_coyote_accept" },
        { text = "Not yet." },
      } },
  },

  desert_coyote_accept = {
    { speaker = "Desert Coyote",
      text = "Follow the scent of old stone and dry wind. Bring my heart back, and I will remember your kindness.",
      set_flag = "desert_coyote_quest_given" },
  },

  ---------------------------------------------------------------------------
  -- Living NPC sample: what an NPC says changes with a story flag, so the
  -- new-dialogue marker shows again after the flag is set. Give an NPC
  -- dialogue_id = "living_guide_sample" and tick Behavior > Show new dialogue
  -- marker. tt_state_flag is the test room's lever flag; use a flag your game
  -- sets (a lever, a boss defeat, another dialogue's set_flag).
  ---------------------------------------------------------------------------
  living_guide_sample = {
    { speaker = "Guide",
      text = "Something has changed nearby. Go and take a look!",
      condition = { flag = "tt_state_flag" } },
    { speaker = "Guide",
      text = "Welcome! Come back when something has changed.",
      condition = { flag = "tt_state_flag", invert = true } },
  },

}

return M
