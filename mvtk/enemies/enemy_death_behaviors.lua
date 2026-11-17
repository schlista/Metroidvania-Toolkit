-- Combat-death effects run synchronously before the actor enters its death clip.
-- Spawned actors own their lifetime; no callback retains the dying enemy.
local M = {}

function M.run(self, ctx)
    if not ctx or ctx.cause ~= "damage" then return end
    local cfg = self._death_effects or {}
    local behavior = cfg.death_behavior
    if behavior == "burst" then
        local count = math.max(0, math.floor(tonumber(cfg.death_burst_count) or 0))
        for i = 1, count do
            local angle = (i - 1) * math.pi * 2 / count
            self.spawn_projectile(self, {x=math.cos(angle), y=math.sin(angle)}, cfg.death_burst_speed)
        end
        -- Each shot selects attack; begin_enemy_death immediately selects death.
    elseif behavior == "split" then
        local depth = self._split_depth or 0
        if depth >= (tonumber(cfg.split_max_depth) or 0) then return end
        local Service = require "mvtk.enemies.enemy_spawn_service"
        local owner = self._spawn_owner
        if type(owner) ~= "string" or owner == "" then
            if not self.spawn_id then return end
            owner = Service.OWNER_PREFIXES.split .. self.spawn_id
        end
        local count = math.max(0, math.floor(tonumber(cfg.split_count) or 0))
        for i = 1, count do
            Service.spawn({owner=owner, room_id=self._room_id or self.room_id,
                enemy_type=cfg.split_type, archetype=cfg.split_archetype,
                position=vmath.vector3(ctx.x + (i - (count + 1) / 2) * cfg.split_spacing_px,
                    ctx.y, self.pos and self.pos.z or 0),
                size=(self._body_scale or 1) * cfg.split_size, settle_to_ground=true,
                overrides={drops="none", split_depth=depth + 1}})
        end
    elseif behavior == "hazard" and (tonumber(cfg.death_hazard_time) or 0) > 0 then
        local C = require "mvtk.core.constants"
        local width, height = cfg.death_hazard_width, cfg.death_hazard_height
        local pos = vmath.vector3(ctx.x, ctx.y, self.pos and self.pos.z or 0)
        local ok, id = pcall(factory.create, C.URL.FACTORY.hazard, pos, nil, {
            hazard_type=cfg.death_hazard_type, room_id=self._room_id or self.room_id or "",
            on_contact="damage", lifetime=cfg.death_hazard_time,
            zone_width=width, zone_height=height,
        }, 1)
        if ok and id then
            -- Size the prefab's "zone" box directly. Box2D scales a shape by
            -- min(scale.x, scale.y) only (1.14.0 box2d_physics.cpp
            -- GetUniformScale2D), so a non-uniform go.set_scale shrinks it.
            pcall(physics.set_shape, msg.url(nil, id, "collision"), "zone",
                {type=physics.SHAPE_TYPE_BOX, dimensions=vmath.vector3(width, height, 20)})
        end
    end
end

return M
