-- Tornado animations, built from the sheets made by
-- art-source/pack_tornado_sheets.py. Loaded from data.lua once those exist.
--
--   wp-tornado-funnel-back   dense far half, drawn under airborne enemies
--   wp-tornado-funnel-front  wispy near half + additive streaks, drawn over them
--   wp-tornado-debris        dust ring and chunks at ground level
--   wp-tornado-shadow        cast shadow on the ground, fading toward the top

local S = require("prototypes.tornado-sheets")

local function sheet(layer, blend)
  local s = S[layer]
  return {
    filename = "__WePlayTornadoGun__/graphics/tornado/" .. layer .. ".png",
    width = s.width, height = s.height,
    frame_count = s.frame_count, line_length = s.line_length,
    animation_speed = 0.5,       -- 32-frame loop ~ once a second
    scale = s.scale,             -- 0.5 for 64 px per tile, 1 for the half-res shadow
    shift = s.shift,             -- puts the tornado's base on the target point
    blend_mode = blend,
  }
end

local front_layers = {sheet("funnel_front")}
if S.streaks then
  front_layers[#front_layers + 1] = sheet("streaks", "additive")
end

data:extend{
  {type = "animation", name = "wp-tornado-funnel-back", layers = {sheet("funnel_back")}},
  {type = "animation", name = "wp-tornado-funnel-front", layers = front_layers},
  {type = "animation", name = "wp-tornado-debris", layers = {sheet("debris")}},
}
if S.shadow then
  data:extend{{type = "animation", name = "wp-tornado-shadow", layers = {sheet("shadow")}}}
end
