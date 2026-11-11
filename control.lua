-- WePlay: Tornado Gun — tornado behavior
--
-- Life of a tornado:
--   moving     spawns on the shooter as a small dust cloud; the dust swells and
--              the funnel grows up and out of it, reaching full size at
--              grow-distance
--   stopping   brakes smoothly when it nears max distance OR is full of enemies
--   holding    sits in place spinning its victims for hold-seconds
--   collapsing shrinks, lets victims fall, then drops them with one last hit
--
-- The dust cloud is the grab zone. Grabbed enemies are dragged in, swirl
-- around the funnel's edge taking damage over time, and cast a shadow on the
-- ground so you can see they're airborne.
--
-- Spawned by a "script" trigger effect with effect_id "wp-tornado-spawn"
-- (see prototypes/weapon.lua).

-- Set to false once the funnel/debris animations exist in graphics/tornado/.
local USE_PLACEHOLDER = false

-- Funnel opacity per half (0 = invisible, 1 = as rendered). The back half is
-- dense and drawn under airborne enemies; the front half is wispy and drawn
-- over them, so you can watch them swirl inside.
local FUNNEL_BACK_OPACITY = 1.0
local FUNNEL_FRONT_OPACITY = 0.8
local SHADOW_OPACITY = 0.6

-- Render layers: back half above trees and buildings but under airborne
-- enemies (which use "air-object"); front half above them.
local BACK_LAYER = "smoke"
local FRONT_LAYER = "air-entity-info-icon"
local SHADOW_LAYER = "lower-object"   -- on the ground, with other entities' shadows
-- Debris sits on the ground under enemies.
local DEBRIS_LAYER = "lower-object-above-shadow"

-- Premultiplied-alpha tint: opacity o, brightness b (b scales colour only).
-- Every value is kept at or below 1: Factorio reads a colour with any value
-- above 1 as 0-255, which made a tinted layer nearly invisible.
local function opacity_tint(o, b)
  o = math.min(1, o)
  local c = math.min(o, o * (b or 1))
  return {c, c, c, o}
end

-- Per-tornado variation, so a volley doesn't look copy-pasted.
local VARY_SIZE = 0.10        -- +/- fraction of funnel size (art, orbit and lift)
local VARY_SPEED = 0.12       -- +/- fraction of spin speed
local VARY_SHADE = 0.06       -- tornadoes darken by up to twice this (never brighten)
local ANIM_SPEED = 1.0        -- animation frames per tick (the speed you've been testing with)
local ANIM_FRAMES = 32        -- frames in the tornado loops

local function vary(amount) return 1 + amount * (2 * math.random() - 1) end

-- The rendered funnel spins the opposite way to the script's orbit angle
-- (Blender's Y axis points away from the camera; Factorio's points toward it),
-- so the orbit runs backwards to ride with the wind.
local SPIN_DIR = -1

local function new_variation()
  return {
    mirror = math.random() < 0.5 and -1 or 1,          -- half spin the other way
    size = vary(VARY_SIZE),
    speed = ANIM_SPEED * vary(VARY_SPEED),
    shade = 1 - 2 * VARY_SHADE * math.random(),        -- darken only (0.88 - 1.0)
    offset = math.random(0, ANIM_FRAMES - 1),         -- funnel, streaks and shadow stay in sync
    debris_offset = math.random(0, ANIM_FRAMES - 1),  -- the dust ring churns on its own
  }
end

local function cfg(name) return settings.global[name].value end

local CATCH_EVERY = 6         -- ticks between catch scans
local START_SOUND_TICKS = 192 -- length of tornado-start.ogg (3.2 s); the loop takes over here
local MUZZLE_OFFSET = 1.0     -- tiles in front of the shooter where the tornado starts
local DAMAGE_EVERY = 10       -- ticks between swirl damage hits (staggered per victim)
local BRAKE = 0.93            -- speed multiplier per tick while stopping
local COLLAPSE_TICKS = 20     -- how long the fall takes

-- Growth timing, as fractions of grow-distance:
local DUST_FULL_AT = 0.5      -- dust cloud reaches full size here
local FUNNEL_START_AT = 0.2   -- funnel begins to rise out of the dust here

local ORBIT_AT = 0.9          -- the highest victims circle at this fraction of the funnel radius
local TIP = 0.25              -- orbit radius at ground level, as a fraction of the top (matches the art)
local TAPER = 1.4             -- >1 keeps the bottom skinny and flares near the top (matches the art)
local LIFT_MULT_MAX = 1.3     -- highest random lift multiplier (see catch)
local SWIRL_SPEED = 0.25      -- tiles per tick at the funnel edge (~15 tiles/s)
local MAX_SPIN = 0.25          -- radians per tick (~2.4 turns per second)

local catch   -- defined below; spawn() calls it

local function smooth(a, b, x)
  local s = math.min(1, math.max(0, (x - a) / (b - a)))
  return s * s * (3 - 2 * s)
end

local function lerp(a, b, s) return a + (b - a) * s end

-- Sizes in tiles.
local function funnel_radius(t)
  return lerp(cfg("wp-tornado-funnel-radius-start"), cfg("wp-tornado-funnel-radius"), t.fg)
         * t.fade * t.var.size
end
local function dust_radius(t)
  return lerp(cfg("wp-tornado-dust-radius-start"), cfg("wp-tornado-dust-radius"), t.dg) * t.fade
end

-- Freeze/unfreeze a unit's AI. Tries the property names used across API
-- versions so one missing name doesn't crash the mod.
local function set_frozen(e, frozen)
  if pcall(function() e.active = not frozen end) then return end
  pcall(function() e.disabled_by_script = frozen end)
end

-- Swap a unit for its shadowless airborne twin (or back). Keeps health,
-- force and quality. Returns the new entity, or the original if no twin
-- exists or creation fails.
local AIRBORNE = "wp-airborne-"
local function swap(e, to_airborne, position)
  local name = e.name
  local new_name
  if to_airborne then
    if name:sub(1, #AIRBORNE) == AIRBORNE then return e end
    new_name = AIRBORNE .. name
  else
    if name:sub(1, #AIRBORNE) ~= AIRBORNE then return e end
    new_name = name:sub(#AIRBORNE + 1)
  end
  if not prototypes.entity[new_name] then return e end
  local ok, n = pcall(function()
    return e.surface.create_entity{
      name = new_name, position = position or e.position,
      force = e.force, quality = e.quality, create_build_effect_smoke = false,
    }
  end)
  if not (ok and n and n.valid) then return e end
  n.health = e.health
  e.destroy()
  return n
end

local function init()
  storage.tornadoes = storage.tornadoes or {}
  storage.caught = storage.caught or {}   -- unit_number -> true, so two tornadoes never share a biter
  storage.next_id = storage.next_id or 1
end
script.on_init(init)

-- On a mod update, clear any tornado still in flight (its saved data may be
-- from an older layout) and unfreeze its victims where they stand.
script.on_configuration_changed(function()
  init()
  for _, t in pairs(storage.tornadoes) do
    for _, v in pairs(t.victims or {}) do
      if v.entity and v.entity.valid then set_frozen(swap(v.entity, false), false) end
      if v.shadow and v.shadow.valid then v.shadow.destroy() end
    end
    for _, obj in pairs{t.funnel, t.funnel_front, t.shadow, t.debris} do
      if obj and obj.valid then obj.destroy() end
    end
    if t.sound and t.sound.valid then t.sound.destroy() end
  end
  for _, f in pairs(storage.fading_sounds or {}) do
    if f.entity and f.entity.valid then f.entity.destroy() end
  end
  storage.fading_sounds = {}
  storage.tornadoes = {}
  storage.caught = {}
end)

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------

-- Funnel size: it shoots up first (height) and widens a beat later, so it
-- reads as a column rising out of the dust and then flaring out.
-- Art timing: nothing but the dust ball until the tornado clears the gun
-- barrel, then the funnel grows out of it quickly.
local ART_DELAY_TICKS = 5     -- the funnel starts growing almost straight away
local ART_GROW_TICKS = 90     -- ...and reaches full size 1.5 s after that, at a steady rate
local ART_TOP_R = 5.0         -- funnel top radius the art was rendered at (FUNNEL_TOP_R in the rig)

-- Art size multiplier: follows the funnel radius setting, so shrinking that
-- setting shrinks the art and the enemy orbit together.
local function art_size(t)
  return t.vg * cfg("wp-tornado-funnel-radius") / ART_TOP_R * t.fade * t.var.size
end

-- Funnel shape while growing: it shoots up first (height) and widens a beat
-- later, so it reads as a column rising out of the dust and then flaring out.
local function funnel_xy(t)
  local g, size = t.vg, art_size(t)
  return size * (0.35 + 0.65 * g), size
end

-- Dust ball: tan puffs and grit swirling around the centre, strongest as it
-- leaves the barrel and thinning out as the funnel takes over.
local DUST_BALL_R = 0.45      -- tiles
local BASE_HAZE_R = 2.0       -- haze ring radius around the funnel's foot at full size (art scale 1)
local function emit_dust(t, tick)
  local dir = t.var.mirror * SPIN_DIR
  -- Base haze around the foot of the funnel, fading in as the funnel grows.
  if math.random() < t.vg then
    local a = tick * 0.35 * dir + math.random() * math.pi * 2
    local r = BASE_HAZE_R * math.max(art_size(t), 0.2) * (0.6 + 0.6 * math.random())
    pcall(t.surface.create_trivial_smoke, {
      name = "wp-tornado-dust-base",
      position = {x = t.pos.x + math.cos(a) * r, y = t.pos.y + math.sin(a) * r * 0.5},
    })
  end
  -- The launch ball: small, dense puffs that give way to the haze.
  local strength = 1 - t.vg
  if math.random() > strength then return end
  for k = 0, 0 do   -- one puff per tick
    local a = tick * 0.55 * t.var.mirror * SPIN_DIR + k * math.pi + math.random() * 0.4
    local r = DUST_BALL_R * (0.4 + 0.6 * math.random())
    local p = {x = t.pos.x + math.cos(a) * r, y = t.pos.y + math.sin(a) * r * 0.5 - 0.3}
    pcall(t.surface.create_trivial_smoke, {name = "wp-tornado-dust", position = p})
  end
  if tick % 2 == 0 then
    local a = tick * 0.55 * t.var.mirror * SPIN_DIR + math.random() * math.pi * 2
    local r = DUST_BALL_R * (0.6 + 0.6 * math.random())
    local spin = (0.12 + 0.06 * math.random()) * t.var.mirror * SPIN_DIR
    pcall(t.surface.create_particle, {
      name = "wp-tornado-grit",
      position = {x = t.pos.x + math.cos(a) * r, y = t.pos.y + math.sin(a) * r * 0.5},
      movement = {-math.sin(a) * spin + t.dir.x * t.speed, math.cos(a) * spin * 0.5 + t.dir.y * t.speed},
      height = 0.2 + math.random() * 0.8,
      vertical_speed = 0.04 + math.random() * 0.06,
      frame_speed = 1,
    })
  end
end

local function draw(t)
  local pos = {x = t.pos.x, y = t.pos.y}
  if USE_PLACEHOLDER then
    -- tan = dust cloud (grab zone), blue = funnel (orbit ring)
    t.debris = rendering.draw_circle{
      color = {0.55, 0.4, 0.25, 0.5}, radius = 0.1, filled = true,
      target = pos, surface = t.surface, draw_on_ground = true,
    }
    t.funnel = rendering.draw_circle{
      color = {0.6, 0.7, 0.9, 0.8}, radius = 0.1, width = 4, filled = false,
      target = pos, surface = t.surface,
    }
    return
  end
  -- Debris at ground level, funnel above everything. Each animation's
  -- prototype `shift` should put its base on the target point so scaling
  -- grows it upward (verify that scale applies to shift on 2.1).
  local v = t.var
  -- The debris can't be mirrored with a negative scale (the game skips
  -- drawing it), so mirrored tornadoes play it backwards instead: a dust ring
  -- spinning in reverse looks the same as a mirrored one. If reverse playback
  -- is refused, fall back to normal playback.
  local function draw_debris(speed)
    return pcall(rendering.draw_animation, {
      animation = "wp-tornado-debris", target = pos,
      surface = t.surface, render_layer = DEBRIS_LAYER,
      x_scale = 1, y_scale = 1, visible = false, tint = opacity_tint(1, v.shade),
      animation_speed = speed, animation_offset = v.debris_offset,
    })
  end
  local ok_d, debris = draw_debris(v.speed * v.mirror)
  if not ok_d then ok_d, debris = draw_debris(v.speed) end
  t.debris = ok_d and debris or nil
  -- The shadow sheet is optional; skip it quietly if it wasn't packed.
  local ok, shadow = pcall(rendering.draw_animation, {
    animation = "wp-tornado-shadow", target = pos,
    surface = t.surface, render_layer = SHADOW_LAYER,
    x_scale = 1, y_scale = 1, visible = false, tint = opacity_tint(SHADOW_OPACITY),
    animation_speed = v.speed, animation_offset = v.offset,
  })
  t.shadow = ok and shadow or nil
  t.funnel = rendering.draw_animation{
    animation = "wp-tornado-funnel-back", target = pos,
    surface = t.surface, render_layer = BACK_LAYER,
    x_scale = 1, y_scale = 1, visible = false, tint = opacity_tint(FUNNEL_BACK_OPACITY, v.shade),
    animation_speed = v.speed, animation_offset = v.offset,
  }
  t.funnel_front = rendering.draw_animation{
    animation = "wp-tornado-funnel-front", target = pos,
    surface = t.surface, render_layer = FRONT_LAYER,
    x_scale = 1, y_scale = 1, visible = false, tint = opacity_tint(FUNNEL_FRONT_OPACITY, v.shade),
    animation_speed = v.speed, animation_offset = v.offset,
  }
end

local function redraw(t)
  local pos = {x = t.pos.x, y = t.pos.y}
  if USE_PLACEHOLDER then
    -- circles show the real gameplay radii (grab zone and orbit ring)
    if t.debris and t.debris.valid then
      t.debris.target = pos
      t.debris.radius = math.max(0.1, dust_radius(t))
    end
    if t.funnel and t.funnel.valid then
      t.funnel.target = pos
      t.funnel.radius = math.max(0.1, funnel_radius(t))
    end
    return
  end
  -- The art is deliberately smaller than the grab zone and follows its own
  -- growth (art_size), so it looks like it came out of the gun.
  local fx, fy = funnel_xy(t)
  local m = t.var.mirror
  local shown = art_size(t) > 0.001
  -- the shadow never mirrors: it must keep falling to the right
  for obj, flip in pairs{[t.funnel or 0] = m, [t.funnel_front or 0] = m, [t.shadow or 0] = 1} do
    if obj ~= 0 and obj.valid then
      obj.target = pos
      obj.x_scale, obj.y_scale = fx * flip, fy
      obj.visible = shown
    end
  end
  if t.debris and t.debris.valid then
    local s = art_size(t)
    t.debris.target = pos
    t.debris.x_scale, t.debris.y_scale = s, s   -- never mirrored; reversed playback instead
    t.debris.visible = shown
  end
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------

local function play(t, path)
  pcall(t.surface.play_sound, {path = path, position = {x = t.pos.x, y = t.pos.y}})
end

-- The looping roar comes from an invisible helper entity that rides along
-- with the tornado; the game loops its working sound seamlessly.
local function update_sound(t, tick)
  local h = t.sound
  if h and h.valid then
    h.teleport{x = t.pos.x, y = t.pos.y}
  elseif not t.sound_done and tick >= t.sound_at then
    local ok, ent = pcall(t.surface.create_entity, {
      name = "wp-tornado-sound", position = {x = t.pos.x, y = t.pos.y}, force = "neutral",
    })
    if ok and ent then
      ent.destructible = false
      t.sound = ent
    end
    t.sound_done = true   -- only ever create it once
  end
end

-- The game can't fade a sound's volume, but it does fade sounds with
-- distance. So instead of deleting the helper (which cuts the loop off with a
-- click), send it gliding away along the tornado's path and delete it once
-- it's out of earshot. The end clip fades in over the same half second.
local SOUND_FADE_TICKS = 30
local SOUND_FADE_STEP = 1.0     -- tiles per tick

local function stop_sound(t)
  local h = t.sound
  if h and h.valid then
    pcall(function() h.active = false end)   -- lets fade_out_ticks kick in, if the game honours it
    storage.fading_sounds = storage.fading_sounds or {}
    storage.fading_sounds[#storage.fading_sounds + 1] = {
      entity = h, dir = {x = t.dir.x, y = t.dir.y}, ticks = SOUND_FADE_TICKS,
    }
  end
  t.sound = nil
  t.sound_done = true
  play(t, "wp-tornado-end")
end

local function update_fading_sounds()
  local list = storage.fading_sounds
  if not list or #list == 0 then return end
  for i = #list, 1, -1 do
    local f = list[i]
    local e = f.entity
    f.ticks = f.ticks - 1
    if not (e and e.valid) then
      table.remove(list, i)
    elseif f.ticks <= 0 then
      e.destroy()
      table.remove(list, i)
    else
      local p = e.position
      e.teleport{x = p.x + f.dir.x * SOUND_FADE_STEP, y = p.y + f.dir.y * SOUND_FADE_STEP}
    end
  end
end

local function undraw(t)
  for _, obj in pairs{t.funnel, t.funnel_front, t.shadow, t.debris} do
    if obj and obj.valid then obj.destroy() end
  end
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------

local function spawn(surface, force, from, to)
  local dx, dy = to.x - from.x, to.y - from.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.01 then dx, dy, len = 0, -1, 1 end

  local t = {
    surface = surface,
    force = force,
    -- just out of the gun barrel; the starting grab zone still covers the
    -- shooter, so biters chasing you get scooped up
    pos = {x = from.x + dx / len * MUZZLE_OFFSET, y = from.y + dy / len * MUZZLE_OFFSET},
    dir = {x = dx / len, y = dy / len},
    speed = cfg("wp-tornado-speed") / 60,          -- tiles per tick
    traveled = 0,
    max_distance = cfg("wp-tornado-max-distance"),
    capacity = cfg("wp-tornado-capacity"),
    state = "moving",
    timer = 0,
    dg = 0,      -- dust growth 0..1
    fg = 0,      -- funnel growth 0..1; also drives lift
    fade = 1,    -- shrinks everything during the collapse
    vg = 0,      -- art growth 0..1 (starts after the barrel, time-based)
    age = 0,
    var = new_variation(),
    victims = {},
  }
  t.sound_at = game.tick + START_SOUND_TICKS
  draw(t)
  play(t, "wp-tornado-start")
  catch(t)   -- grab anything already on top of the player
  storage.tornadoes[storage.next_id] = t
  storage.next_id = storage.next_id + 1
end

script.on_event(defines.events.on_script_trigger_effect, function(e)
  if e.effect_id ~= "wp-tornado-spawn" then return end
  local surface = game.surfaces[e.surface_index]
  local src = e.source_entity
  local from = e.source_position or (src and src.valid and src.position)
  local to = e.target_position or (e.target_entity and e.target_entity.valid and e.target_entity.position)
  if not (surface and from and to) then return end
  local force = (src and src.valid and src.force) or game.forces.player
  spawn(surface, force, from, to)
end)

---------------------------------------------------------------------------
-- Catching and swirling
---------------------------------------------------------------------------

function catch(t)   -- assigns the local declared above
  local free = t.capacity - #t.victims
  if free <= 0 then return end
  local found = t.surface.find_entities_filtered{
    position = t.pos, radius = dust_radius(t), type = "unit",
  }
  for _, e in pairs(found) do
    if free <= 0 then break end
    if e.valid and t.force.is_enemy(e.force) and not storage.caught[e.unit_number] then
      e = swap(e, true)
      storage.caught[e.unit_number] = true
      set_frozen(e, true)
      local ox, oy = e.position.x - t.pos.x, e.position.y - t.pos.y
      t.victims[#t.victims + 1] = {
        entity = e, unit_number = e.unit_number,
        angle = math.atan2(oy * 2, ox),   -- *2 undoes the squashed orbit below
        radius = math.max(1, math.sqrt(ox * ox + oy * oy)),
        lift = 0,
        lift_mult = 0.35 + (LIFT_MULT_MAX - 0.35) * math.random(),   -- 0.35x to 1.3x the lift setting
        dmg_mult = 0.5 + math.random(),   -- 0.5x to 1.5x, so they die at different times
        phase = math.random(0, DAMAGE_EVERY - 1),
        shadow = rendering.draw_circle{
          color = {0, 0, 0, 0.45}, radius = 0.6, filled = true,
          target = e.position, surface = t.surface, draw_on_ground = true,
        },
      }
      free = free - 1
    end
  end
end

local function release(v)
  storage.caught[v.unit_number] = nil
  if v.shadow and v.shadow.valid then v.shadow.destroy() end
end

-- Orbit is an ellipse (half as tall as wide), which reads as a flat ring in
-- Factorio's 3/4 view. Pulling the y position north fakes being lifted, and
-- the shadow stays on the ground beneath to sell the height.
local function swirl(t, tick, collapsing)
  local top = math.max(0.5, ORBIT_AT * funnel_radius(t))   -- orbit radius at the top, in tiles
  local max_lift = cfg("wp-tornado-lift") * t.fg * t.var.size
  local top_lift = math.max(0.01, cfg("wp-tornado-lift") * LIFT_MULT_MAX * t.var.size)
  local dps = cfg("wp-tornado-swirl-dps")
  for i = #t.victims, 1, -1 do
    local v = t.victims[i]
    local e = v.entity
    if e.valid then
      -- Tapered orbit: the radius follows the funnel's shape, so low victims
      -- whip around the skinny tip and high ones circle the wide top.
      local h = math.min(1, v.lift / top_lift)
      local core = math.max(0.4, top * (TIP + (1 - TIP) * h ^ TAPER))
      if collapsing then
        v.lift = v.lift * 0.8                     -- falling
        v.radius = v.radius + 0.05                -- flung outward a little
      else
        v.radius = v.radius + (core - v.radius) * 0.03
        v.lift = v.lift + (max_lift * v.lift_mult - v.lift) * 0.02
      end
      -- full speed at the funnel edge, slower out in the dust
      local r = math.max(v.radius, 0.5)
      -- (capped so the skinny tip spins fast but doesn't jitter)
      v.angle = v.angle + t.var.mirror * SPIN_DIR *
                math.min(MAX_SPIN, SWIRL_SPEED / r * math.sqrt(core / math.max(r, core)))
      local gx = t.pos.x + math.cos(v.angle) * v.radius
      local gy = t.pos.y + math.sin(v.angle) * v.radius * 0.5
      e.teleport{x = gx, y = gy - v.lift}
      if v.shadow and v.shadow.valid then
        v.shadow.target = {x = gx, y = gy}
        -- smaller and fainter the higher it is
        v.shadow.radius = math.max(0.2, 0.6 - 0.04 * v.lift)
        v.shadow.color = {0, 0, 0, math.max(0.15, 0.45 - 0.025 * v.lift)}
      end
      if not collapsing and dps > 0 and (tick + v.phase) % DAMAGE_EVERY == 0 then
        e.damage(dps * v.dmg_mult * DAMAGE_EVERY / 60, t.force, "impact")
      end
    end
    if not e.valid then   -- died to swirl damage or anything else
      release(v)
      table.remove(t.victims, i)
    end
  end
end

local function drop_all(t)
  local dmg = cfg("wp-tornado-fall-damage")
  for _, v in pairs(t.victims) do
    release(v)
    local e = v.entity
    if e.valid then
      local ground = {x = e.position.x, y = e.position.y + v.lift}
      local real_name = e.name:gsub("^" .. AIRBORNE:gsub("%-", "%%-"), "")
      ground = t.surface.find_non_colliding_position(real_name, ground, 4, 0.25) or ground
      e = swap(e, false, ground)
      e.teleport(ground)
      set_frozen(e, false)
      if dmg > 0 then e.damage(dmg, t.force, "impact") end
    end
  end
  t.victims = {}
end

---------------------------------------------------------------------------
-- Per-tick update
---------------------------------------------------------------------------

-- Returns true when the tornado is finished.
local function update(t, tick)
  -- Art growth is time-based, so a tornado that stops early still grows fully.
  t.age = (t.age or 0) + 1
  if not t.art_start and t.age >= ART_DELAY_TICKS then
    t.art_start = tick
  end
  if t.art_start then
    -- linear growth: constant rate from the first tick, no slow start
    t.vg = math.min(1, (tick - t.art_start) / ART_GROW_TICKS)
  end
  t.fg = t.vg   -- enemy orbit and lift grow with the art

  if t.state == "moving" or t.state == "stopping" then
    if t.state == "moving" then
      local stop_distance = t.speed / (1 - BRAKE)   -- how far braking will carry it
      if #t.victims >= t.capacity or t.max_distance - t.traveled <= stop_distance then
        t.state = "stopping"
      end
    else
      t.speed = t.speed * BRAKE
    end
    t.pos.x = t.pos.x + t.dir.x * t.speed
    t.pos.y = t.pos.y + t.dir.y * t.speed
    t.traveled = t.traveled + t.speed
    if t.speed < 0.005 or t.traveled >= t.max_distance then
      t.state, t.speed, t.timer = "holding", 0, 0
    end
    local g = t.traveled / math.max(0.1, cfg("wp-tornado-grow-distance"))
    t.dg = smooth(0, DUST_FULL_AT, g)

  elseif t.state == "holding" then
    t.timer = t.timer + 1
    if t.timer >= cfg("wp-tornado-hold-seconds") * 60 then
      t.state, t.timer = "collapsing", 0
      stop_sound(t)
    end

  elseif t.state == "collapsing" then
    t.timer = t.timer + 1
    t.fade = t.fade * 0.92
    swirl(t, tick, true)
    redraw(t)
    if t.timer >= COLLAPSE_TICKS then
      drop_all(t)
      undraw(t)
      return true
    end
    return false
  end

  if tick % CATCH_EVERY == 0 then catch(t) end
  if not USE_PLACEHOLDER then emit_dust(t, tick) end
  update_sound(t, tick)
  swirl(t, tick, false)
  redraw(t)
  return false
end

script.on_event(defines.events.on_tick, function(e)
  update_fading_sounds()
  local list = storage.tornadoes
  if not next(list) then return end
  for id, t in pairs(list) do
    if not t.surface.valid then
      list[id] = nil
    elseif update(t, e.tick) then
      list[id] = nil
    end
  end
end)
