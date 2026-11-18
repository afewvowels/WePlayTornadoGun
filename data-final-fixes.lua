-- Airborne twins: a copy of every unit (biters, spitters, modded units) with
-- its shadow layers and water reflection removed, drawn in the air layer so
-- it passes in front of trees and buildings. While an enemy is caught in
-- a tornado, control.lua swaps it for its twin so the only shadow you see is
-- the one the mod draws on the ground beneath it. Runs in data-final-fixes so
-- units added by other mods get twins too.

local PREFIX = "wp-airborne-"

local function strip_shadows(anim)
  if type(anim) ~= "table" then return anim end
  if anim.draw_as_shadow then return nil end
  if anim.layers then
    local kept = {}
    for _, layer in ipairs(anim.layers) do
      local s = strip_shadows(layer)
      if s then kept[#kept + 1] = s end
    end
    anim.layers = kept
  end
  return anim
end

local twins = {}
for name, unit in pairs(data.raw["unit"]) do
  if name:sub(1, #PREFIX) ~= PREFIX then
    local twin = table.deepcopy(unit)
    twin.name = PREFIX .. name
    twin.localised_name = unit.localised_name or {"entity-name." .. name}
    twin.localised_description = unit.localised_description or {"entity-description." .. name}
    twin.hidden = true
    twin.hidden_in_factoriopedia = true
    twin.autoplace = nil
    twin.water_reflection = nil
    twin.render_layer = "air-object"   -- drawn above trees and buildings while airborne
    -- No collisions while airborne. Lifting works by teleporting every tick,
    -- and teleport checks collisions, so big biters (big collision boxes)
    -- kept getting blocked by trees, rocks and each other and stayed low.
    twin.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
    twin.collision_mask = {layers = {}}
    twin.run_animation = strip_shadows(twin.run_animation)
    if twin.attack_parameters and twin.attack_parameters.animation then
      twin.attack_parameters.animation = strip_shadows(twin.attack_parameters.animation)
    end
    twins[#twins + 1] = twin
  end
end
data:extend(twins)


-- Research: every technology that boosts bullet damage (Physical projectile
-- damage, including the infinite levels and modded versions) gives the
-- tornado charge the same bonus. control.lua applies it to the tornado's
-- scripted swirl and fall damage.
for _, tech in pairs(data.raw["technology"]) do
  local added = {}
  for _, effect in pairs(tech.effects or {}) do
    if effect.type == "ammo-damage" and effect.ammo_category == "bullet" then
      added[#added + 1] = {type = "ammo-damage", ammo_category = "wp-tornado", modifier = effect.modifier}
    end
  end
  for _, effect in ipairs(added) do
    table.insert(tech.effects, effect)
  end
end
