-- Tornado gun, its ammo, recipes, and the technology that unlocks them (after Military 3).

local spawn_action = {
  type = "direct",
  action_delivery = {
    type = "instant",
    target_effects = {{type = "script", effect_id = "wp-tornado-spawn"}},
  },
}

data:extend{
  {type = "ammo-category", name = "wp-tornado"},

  {
    type = "gun",
    name = "wp-tornado-gun",
    icon = "__WePlayTornadoGun__/graphics/icons/tornado-gun.png",
    icon_size = 64,
    subgroup = "gun",
    order = "z[wp-tornado-gun]",
    stack_size = 5,
    attack_parameters = {
      type = "projectile",
      ammo_category = "wp-tornado",
      cooldown = 60,          -- one tornado per second
      range = 30,
      min_range = 2,
      movement_slow_down_factor = 0.5,
    },
  },

  {
    type = "ammo",
    name = "wp-tornado-charge",
    icon = "__WePlayTornadoGun__/graphics/icons/tornado-charge.png",
    icon_size = 64,
    ammo_category = "wp-tornado",
    ammo_type = {
      target_type = "position",
      clamp_position = true,
      action = spawn_action,
    },
    magazine_size = 1,
    subgroup = "ammo",
    order = "z[wp-tornado-charge]",
    stack_size = 50,
  },

  {
    type = "recipe",
    name = "wp-tornado-gun",
    enabled = false,
    energy_required = 5,
    ingredients = {
      {type = "item", name = "engine-unit", amount = 3},
      {type = "item", name = "copper-plate", amount = 10},
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "barrel", amount = 1},
    },
    results = {{type = "item", name = "wp-tornado-gun", amount = 1}},
  },

  {
    type = "recipe",
    name = "wp-tornado-charge",
    enabled = false,
    categories = {"crafting-with-fluid"},   -- pressurized with steam: assembling machine 2 or 3 (2.1 format)
    energy_required = 2,
    ingredients = {
      {type = "item", name = "copper-plate", amount = 5},
      {type = "item", name = "stone", amount = 2},
      {type = "item", name = "barrel", amount = 1},
      {type = "fluid", name = "steam", amount = 100},
    },
    results = {{type = "item", name = "wp-tornado-charge", amount = 1}},
  },

  {
    type = "technology",
    name = "wp-tornado-gun",
    icon = "__WePlayTornadoGun__/graphics/technology/tornado-gun.png",
    icon_size = 256,
    prerequisites = {"military-3"},
    effects = {
      {type = "unlock-recipe", recipe = "wp-tornado-gun"},
      {type = "unlock-recipe", recipe = "wp-tornado-charge"},
    },
    unit = {
      count = 200,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"military-science-pack", 1},
      },
      time = 30,
    },
    order = "e-a-z[wp-tornado-gun]",
  },
}
