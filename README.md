# WePlay: Tornado Gun

Fire a tornado that rises out of a dust cloud, sweeps up enemies, spins them through the funnel, and drops them hard.

![A tornado with its dust ring, swirling streaks and cast shadow](docs/tornado-preview.png)

Install it from the Factorio mod portal: search for **WePlay: Tornado Gun** in the in-game mod manager, or see [its page on the mod portal](https://mods.factorio.com/mod/WePlayTornadoGun). Requires Factorio 2.1.

---

## What it does

1. **Fire.** A small swirl of tan dust and grit leaves the muzzle, about a tile in front of you, with a rising whoosh.
2. **It grows.** The funnel grows up out of the dust at a steady rate, reaching full size about 1.6 seconds after firing, while a dusty haze settles around its foot.
3. **It sweeps.** It travels along your aim. Any enemy in the dust cloud is grabbed, dragged in and whipped around the funnel, rising higher as it spins, following the funnel's taper.
4. **It stops.** It brakes when it reaches its maximum distance or when it's holding as many enemies as it can, then spins in place for a few seconds.
5. **It collapses.** The funnel sinks back into the dust and everything it was holding drops to the ground and takes fall damage. The dropped enemies stand around dazed for a moment before their AI picks them back up.

Every tornado is a little different: it starts at a random point in its spin, about half of them spin the other way, and size, spin speed and shade vary slightly.

**Unlocking:** research **Tornado gun** (requires Military 3; 200 × red, green and military science) to unlock the tornado gun and tornado charges.

| Recipe | Ingredients | Made in |
|---|---|---|
| Tornado gun | 3 engine units, 10 steel plate, 10 copper plate, 1 barrel | By hand or any assembler |
| Tornado charge | 5 copper plate, 2 stone, 1 barrel, 100 steam | Assembling machine 2 or 3 (needs a fluid input) |

## Map settings

All of these are runtime settings (Settings → Mod settings → Map), so they can be changed mid-game.

| Setting | Default | What it does |
|---|---|---|
| Tornado max distance | 30 tiles | The tornado slows and stops when it gets this far. |
| Distance to reach full size | 10 tiles | How far it travels before the grab zone is full size. |
| Enemies a tornado can hold | 12 | It also stops once it's holding this many. |
| Travel speed | 8 tiles/s | |
| Spin time after stopping | 4 s | |
| Fall damage when dropped | 150 | Impact damage to each enemy when it lands. |
| Swirl damage per second | 25 | Damage over time while lifted. Each enemy takes a random 0.5x to 1.5x of this, so they don't all die at once. |
| Dust cloud (grab) radius at the gun | 3 tiles | Big enough to catch enemies right on your heels. |
| Dust cloud (grab) radius at full size | 12 tiles | Anything in the dust cloud gets pulled in. |
| Funnel radius at the gun | 1.5 tiles | |
| Funnel radius at full size | 3.5 tiles | Where grabbed enemies orbit. Also sets the size of the tornado graphic. |
| Lift height at full size | 4.5 tiles | How high grabbed enemies rise. |

## Compatibility

* **Modded enemies:** any `unit` can be picked up, including units added by other mods. Each one gets a shadowless "airborne twin" (see below).
* **Space Age** isn't needed.
* **Saves:** updating the mod clears any tornado that's still in flight and puts its enemies back on the ground.

---

## How it works

Everything is in `control.lua`. A tornado is a plain Lua table in `storage.tornadoes`, updated every tick. There's no tornado entity.

### Life of a tornado

| State | What happens |
|---|---|
| `moving` | Travels along the aim line. The grab zone (dust radius) grows with distance; the art and the enemy orbit grow with time. |
| `stopping` | Brakes smoothly (speed × 0.93 per tick), timed so it stops right at max distance, or as soon as it's full. |
| `holding` | Spins in place for the hold time. |
| `collapsing` | Shrinks over 20 ticks, lowers and flings its enemies outward, then drops them with fall damage. |

It's spawned by a `script` trigger effect (`effect_id = "wp-tornado-spawn"`) on the tornado charge's ammo, handled in `on_script_trigger_effect`.

### Grabbing and swirling enemies

* **Catch:** every 6 ticks, finds enemy `unit`s inside the dust radius. Caught enemies have their AI frozen.
* **Airborne twins:** `data-final-fixes.lua` makes a copy of every unit prototype (`wp-airborne-<name>`) with its shadow layers and water reflection removed, drawn in the `air-object` layer so it passes over trees and buildings. A caught enemy is swapped for its twin (same health, force and quality) and swapped back when it lands.
* **Orbit:** each enemy orbits on an ellipse half as tall as it is wide, which reads as a flat ring in Factorio's view. It's pulled in toward the funnel, and its orbit radius follows the funnel's taper by height: skinny at the bottom, flared at the top (`TIP`, `TAPER`). Spin speed is fastest at the funnel edge and capped so the tip doesn't jitter.
* **Lift:** each enemy rises to its own random height (0.35x to 1.3x the lift setting). Height is faked by moving it north on screen; a dark ground shadow stays underneath, smaller and fainter the higher it is.
* **Spin direction** matches the art, including mirrored tornadoes (`SPIN_DIR`, `var.mirror`).

### Drawing layers

The tornado is drawn with `rendering.draw_animation` objects, bottom to top:

| Layer | Render layer | Notes |
|---|---|---|
| Cast shadow | `lower-object` | Never mirrored, so it always falls to the right |
| Base dust haze | `lower-object` | Trivial smoke puffs churning around the foot |
| Debris ring and rocks | `lower-object-above-shadow` | Mirrored tornadoes play it in reverse instead of flipping it |
| Back half of the funnel | `smoke` | Dense, soft; drawn under airborne enemies |
| Airborne enemies | `air-object` | (their twins' own render layer) |
| Front half + additive streaks | `air-entity-info-icon` | Wispy, so you can see enemies inside |

Every layer is created at full size but hidden, then revealed and resized, so the game always knows its on-screen size. (Created at zero size, a layer could vanish after scrolling off-screen.)

**Tints:** brightness variation only ever darkens, and every tint value is capped at 1. Factorio reads a colour with any value above 1 as 0 to 255, which made layers nearly invisible.

### Sound

| Sound | When |
|---|---|
| `tornado-start.ogg` (3.2 s) | Played where it's fired. A rising swell that ends by crossfading into the loop. |
| `tornado-loop.ogg` (12 s) | Starts when the start clip hands off. Played as the working sound of an invisible helper entity (`wp-tornado-sound`) that follows the tornado every tick, so the game loops it seamlessly and it pans as the tornado moves. |
| `tornado-end.ogg` (4.4 s) | Played at collapse. It crossfades out of the loop into dying wind. |

Scripts can't fade a sound, so at collapse the helper glides away along the tornado's path for half a second (fading the loop by distance) before it's removed, while the end clip fades in.

The loop was built from two gust cycles of a longer wind recording with the halves swapped, so the loop point falls where the recording was continuous, plus a crossfade in the middle. A synthesized rumble that follows the gusts adds low end, and gentle saturation matches the loudness of the start and end clips.

### Tuning knobs in `control.lua`

| Constant | Default | What it does |
|---|---|---|
| `ART_DELAY_TICKS` / `ART_GROW_TICKS` | 5 / 90 | When the funnel starts growing, and how long it takes (linear) |
| `MUZZLE_OFFSET` | 1.0 | Tiles in front of the shooter where it starts |
| `FUNNEL_BACK_OPACITY` / `FUNNEL_FRONT_OPACITY` / `SHADOW_OPACITY` | 1.0 / 0.8 / 0.6 | Layer opacity |
| `VARY_SIZE` / `VARY_SPEED` / `VARY_SHADE` | 0.10 / 0.12 / 0.06 | Per-tornado variation |
| `ANIM_SPEED` | 1.0 | Animation frames per tick |
| `DUST_BALL_R` / `BASE_HAZE_R` | 0.45 / 2.0 | Launch dust ball radius / base haze ring radius |
| `TIP` / `TAPER` / `ORBIT_AT` | 0.25 / 1.4 / 0.9 | Orbit shape (kept matching the art) |
| `SWIRL_SPEED` / `MAX_SPIN` | 0.25 / 0.25 | Orbit speed at the funnel edge / spin cap |
| `ART_TOP_R` | 5.0 | Funnel top radius the art was rendered at. Must match `FUNNEL_TOP_R` in the rig. |
| `USE_PLACEHOLDER` | false | `true` draws circles for the grab zone and orbit ring instead of the art |

---

## Art pipeline

The tornado art is fully procedural, built in Blender 4.2+ (tested on 5.2) with geometry nodes, and rendered on a Flamenco render farm. The source lives in `art-source/` (not shipped in the mod zip).

### 1. Build the rig: `art-source/tornado_rig.py`

Save a `.blend`, then run the script from Blender's Scripting tab. Re-running rebuilds everything prefixed `TR_`. It builds:

* **Funnel:** nine helical ribbons in three tiers (tip, middle, top) around a tapered, wobbling spine. Each tier spins a whole number of turns per loop (3, 2, 1), so the 32-frame loop is seamless while the bottom whips faster than the top. Everything is driven by the frame number, so every farm worker renders the same thing.
* **Shading:** toon shading with soft steps, stretched streak noise, soft ribbon edges, and silhouette fading on the back half. Dusty browns to sit in Factorio's palette.
* **Back/front split:** each point knows which side of the funnel it's on, so the far half and near half render separately, cross-fading at the silhouette.
* **Debris:** a low, wide dust ring (the same ribbon group) plus tumbling rocks.
* **Shadow:** copies of the funnel ribbons flattened onto the ground along the sun direction, fading toward the top, with their own wider, half-resolution camera.
* **Camera:** orthographic, 64 px per tile, looking down at 30°, so a ground circle is squashed to half height. This matches the script's orbit ellipse.

Most knobs are in the config block at the top (sizes, taper, palette, densities, streaks, fades, shadow direction).

### 2. Render

The rig makes five scenes, one per layer: `TR_FunnelBack`, `TR_FunnelFront`, `TR_Streaks`, `TR_Debris` and `TR_Shadow`. Each renders 32 frames to `render/<layer>/`. Submit each scene to Flamenco, or render with Ctrl+F12. Flamenco may write to its own output folder; if so, copy each job's frames into the matching layer folder.

### 3. Pack: `art-source/pack_tornado_sheets.py`

```
python pack_tornado_sheets.py --render-dir path/to/render --mod-dir path/to/WePlayTornadoGun
```

Needs Pillow and numpy. Both paths are found automatically if you leave them out. The packer:

* reads any PNGs in each layer folder, ordered by frame number;
* softens edges (back half and shadow only);
* trims every layer to the area its frames actually use, roughly halving video memory;
* renders the back half at half resolution, since it's blurred anyway;
* saves the busy layers (front, streaks, debris) as 256-colour PNGs, about 7x smaller, while the soft back half and shadow stay full colour because they would posterize;
* writes `graphics/tornado/<layer>.png` and `prototypes/tornado-sheets.lua`, with each layer's size, frame layout, anchor shift and scale.

The per-layer treatment is in `LAYER_OPTS` at the top. Use `--no-blur` when repacking frames that are already blurred.

---

## Repository layout

```
WePlayTornadoGun/
  info.json, changelog.txt, thumbnail.png
  data.lua, data-final-fixes.lua, control.lua, settings.lua
  prototypes/   weapon, tornado animations, dust effects, sounds, generated sheet table
  graphics/     icons, tornado sprite sheets
  sound/        tornado start / loop / end
  locale/en/
  art-source/   Blender rig and packer (excluded from the zip)
  docs/         README images (excluded from the zip)
```

## Credits and licence

* **Code:** released under the Unlicense (public domain). See `LICENSE`.
* **Gun and canister art:** AI-generated images.
* **Tornado art:** rendered from the procedural Blender rig in `art-source/`.
* **Sounds:** built from Envato Elements assets ("Elemental - Tornado 1" and Mountain Audio "Synthesized Strong Wind 2"), cut, layered and reworked for the mod. The sound files are covered by their Envato Elements licence, **not** by the Unlicense.
