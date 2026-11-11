-- Dust-ball effects: tan smoke puffs and grit particles that swirl around a
-- new tornado before the funnel grows out of it. Both are copies of base-game
-- prototypes (tinted / retimed), so they need no new graphics. If a base
-- prototype can't be found, that effect is simply skipped at runtime.

local function first_of(kind, preferred, pattern)
  local all = data.raw[kind] or {}
  for _, name in ipairs(preferred) do
    if all[name] then return all[name] end
  end
  if pattern then
    for name, proto in pairs(all) do
      if name:find(pattern) then return proto end
    end
  end
  return nil
end

-- Tan smoke puff
local smoke = first_of("trivial-smoke", {"smoke", "smoke-fast", "light-smoke"}, "smoke")
if smoke then
  local dust = table.deepcopy(smoke)
  dust.name = "wp-tornado-dust"
  dust.color = {0.56, 0.44, 0.30, 0.75}
  dust.duration = 26
  dust.fade_in_duration = 4
  dust.fade_away_duration = 16
  dust.spread_duration = 14
  dust.start_scale = 0.15
  dust.end_scale = 0.45
  dust.affected_by_wind = false
  dust.show_when_smoke_off = true
  data:extend{dust}

  -- Base haze: bigger, softer puffs that churn around the foot of the funnel.
  -- They thin out as they spread (the fade-away runs through the growth), and
  -- sit on a ground layer under the debris ring so its streaks and rocks stay
  -- crisp on top.
  local base = table.deepcopy(smoke)
  base.name = "wp-tornado-dust-base"
  base.color = {0.52, 0.41, 0.28, 0.45}
  base.duration = 72
  base.fade_in_duration = 8
  base.fade_away_duration = 60
  base.spread_duration = 72
  base.start_scale = 0.5
  base.end_scale = 2.2
  base.affected_by_wind = false
  base.show_when_smoke_off = true
  base.render_layer = "lower-object"
  data:extend{base}
end

-- Grit: small rock bits flung around the swirl
local grit = first_of("optimized-particle", {"stone-particle", "stone-particle-small"}, "stone")
if grit then
  local g = table.deepcopy(grit)
  g.name = "wp-tornado-grit"
  data:extend{g}
end
