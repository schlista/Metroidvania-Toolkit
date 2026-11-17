-- World census counting rules. Prepared membership covers every baked room;
-- runtime totals include only rooms in the published layout.
return {
    -- Non-respawning items in these categories contribute to completion totals.
    count_categories = {charm=true, weapon=true, ability=true, upgrade=true, progression=true, relic=true, lore=true, key=true},
    -- Exclusions win over count_categories. Use the collectible type's optional
    -- count_in_census=false to exclude one type within a counted category.
    exclude_categories = {consumable=true, currency=true, material=true, powerup=true},
    -- How objects with a world-state condition (appear_when / remove_when)
    -- count. 'when_present' counts one only while its condition lets it exist:
    -- it joins the totals once it appears and leaves them once it is removed.
    -- 'always' counts every such object from the start, present or not.
    count_presence_gated = "when_present",
}
