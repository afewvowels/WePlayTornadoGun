-- Tornado sounds:
--   wp-tornado-start  swell as it leaves the gun; ends by blending into the loop
--   wp-tornado-loop   seamless roar, played by an invisible helper entity that
--                     rides along with the tornado (the game loops it for us)
--   wp-tornado-end    blends out of the loop into the dying wind

local VOLUME = 0.7
local path = "__WePlayTornadoGun__/sound/"

data:extend{
  {type = "sound", name = "wp-tornado-start", filename = path .. "tornado-start.ogg", volume = VOLUME},
  {type = "sound", name = "wp-tornado-end", filename = path .. "tornado-end.ogg", volume = VOLUME},
  {
    type = "simple-entity-with-owner",
    name = "wp-tornado-sound",
    hidden = true,
    flags = {"not-on-map", "placeable-off-grid", "not-blueprintable", "not-deconstructable",
             "not-selectable-in-game", "no-copy-paste", "not-in-kill-statistics"},
    selectable_in_game = false,
    collision_mask = {layers = {}},
    is_military_target = false,
    picture = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    working_sound = {
      sound = {filename = path .. "tornado-loop.ogg", volume = VOLUME},
      use_doppler_shift = false,
      max_sounds_per_prototype = 4,
      fade_out_ticks = 30,   -- used if the game treats the paused helper as "not working"
    },
  },
}
