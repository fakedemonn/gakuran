# AutoParry

Game-agnostic animation-driven auto parry for Roblox, with an animation
visualizer, an info logger, a hitbox previewer, an unknown-effect logger for
attacks that never touch an `Animator`, directional dashing, and a per-place
timing database served from this repo.

Written as feature modules under `src/`, with a one-file build for convenience.

---

## Loading

Single file — nothing to configure:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fakedemonn/gakuran/main/roblox-autoparry/AutoParry.lua"))()
```

Or the modular build, which pulls each module out of `src/` at runtime:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fakedemonn/gakuran/main/roblox-autoparry/init.lua"))()
```

Both run the same code. If you move this folder to the repo root or rename the
repo, edit `BRANCH` / `REPO` / `BASE` at the top of `init.lua` — `BASE` is what
carries the `roblox-autoparry/` subfolder segment.

Menu keybind is `End`.

### Repo layout

```
init.lua                    module loader - fetches src/ in dependency order
build.js                    node build.js -> regenerates AutoParry.lua
AutoParry.lua               generated single-file build, do not edit
timings/<PlaceId>/          timing databases served to the script
effects/<PlaceId>/          effect profiles served to the script
src/
  core/
    Config.lua              version, folder paths, repo urls, services
    FS.lua                  executor filesystem shims + nested folder walker
    Util.lua                round, shortId, distance, facing, alive, root, groundY
    Input.lua               VirtualInputManager / keypress backends
    Latency.lua             round trip time
    State.lua               counters and the single "may we parry" gate
    Notify.lua              one notification entry point
  features/
    Dodge.lua               directional dashing and the parry-busy fallback
    Store.lua               the timing database
    Log.lua                 info logger data + speed-curve recorder
    Entities.lua            where combat characters live, and who is a target
    Engine.lua              scheduling, hitbox geometry + gate, the parry itself
    Effects.lua             unknown effect logger and the profiles built from it
    Hitbox.lua              draws the hitboxes and the distance ring in the world
    Hooks.lua               Animator.AnimationPlayed listeners
  ui/
    Library.lua             LinoriaLib, window, tabs
    MainTab.lua             tab 1, parry + dodging
    BuilderTab.lua          tab 2, logger + hitbox + timing builder
    EffectsTab.lua          tab 3, effect logger + effect builder
    LoggerWindow.lua        Info Logger window
    VisualizerWindow.lua    Animation Visualizer & Editor window
    EffectWindow.lua        Unknown Effect Logger window, with a 3D preview
    Wiring.lua              connects the tab controls to the stores and windows
    Settings.lua            tab 4, themes and UI configs
  Runtime.lua               watermark, render loop, stats loop, unload
  Boot.lua                  settings restore, database load, first animator sweep
README.md
```

Every module is `return function(ctx) ... end`. The loader builds one shared
context table, runs each module against it in dependency order, and each module
publishes what it exports onto `ctx` (`ctx.Store`, `ctx.Engine`, ...). No
globals, no shared upvalues — you can read any one file on its own.

Modules that load before `ui/Library.lua` read `ctx.Toggles` / `ctx.Options`
**inside** their functions rather than capturing them at load time, because the
UI does not exist yet when they run.

`src/` is the source of truth. `AutoParry.lua` is generated — after editing a
module, run `node build.js` to regenerate it.

### Requirements

- `VirtualInputManager`, or the `keypress` / `keyrelease` globals
- An executor with `writefile` / `readfile` / `isfile` / `isfolder` / `makefolder` / `listfiles`.
  Timings are saved locally the moment they change; without a filesystem the
  script still runs off the repo copy, but nothing you tune survives the session
  and it says so on load
- `setclipboard`, for the **Copy Database** export path

No input backend means parry cannot fire, and the script says so on load.

---

## How it works

Every `Animator` inside the configured container gets its `AnimationPlayed`
signal hooked. When a track starts:

1. The `AnimationId` is looked up in the timing database for this `PlaceId`.
2. Unknown IDs get a disabled stub created from the track length.
3. Known and enabled IDs schedule a parry keypress.

The scheduling maths is the part that matters:

```
wait = (delay / 1000) - RTT - offset + jitter
```

The attacker's animation started roughly one one-way-delay ago, and your
keypress needs another one-way-delay to reach the server. Subtracting the full
round trip time puts the input on the server at the moment the hit lands — which
is why the whole RTT goes, not a fraction of it. That used to be a Ping
Compensation percentage slider; it had exactly one correct value, so it is a
constant in `src/core/Config.lua` now and **Timing Offset** (0–150 ms) is the
knob you actually turn.

Everything is revalidated at fire time — target still alive, animation still
playing, still in range — because a lot can change during a wind-up.

---

## Building timings

The intended loop is build-as-you-play:

1. **Builder** tab, turn on **Show Logger Window**.
2. Fight something. Every animation lands in the logger as
   `Time | Animation | ID | Enemy | Dist | Status`.
3. Click any row. That opens the visualizer, loads the rig, and fills the
   **Quick Edit Timing** panel.
4. Tune the numbers, hit **Save & Apply**, then **Add To Parry List**.

### Info Logger

| Status | Meaning |
|---|---|
| `NEW` | never seen, no timing saved |
| `KNOWN` | timing saved but not enabled |
| `IN AP` | timing saved **and** live on the parry list |

Status is read from the database every refresh, not cached on the row — so a
row logged as `NEW` flips to `IN AP` the moment you save a timing for it,
without having to re-trigger the animation. The whole row is tinted to match,
so a screen full of entries reads at a glance.

**One Row Per Animation** is on by default: an animation id occupies exactly one
row for the life of the log, and a replay refreshes that row's time, distance and
ping in place instead of pushing a new one. A boss with a four-hit combo used to
bury the list in twelve copies of the same four ids inside a single fight. Turn
it off to see every individual play.

**Clear** empties the list *and* the dedupe memory — clearing one without the
other is what would otherwise leave a cleared logger permanently empty, because
every id was still marked as already shown.

**Auto Create Timings** on the Builder tab makes a stub for each new animation at
60% of the animation length. Stubs arrive **disabled** so a batch of untuned
guesses does not start parrying at random.

### Animation Visualizer & Editor

The viewport clones the attacking rig and replays the animation at the speed it
was actually played at you, not at 1x — which matters when the attacker has any
kind of speed modifier. If the original rig has despawned it falls back to
another live rig, then to your own character; the skeleton is what matters.

Controls: `Play` / `Pause`, `<<` and `>>` step one hundredth of a second, the
scrub bar is draggable, and **From Log** reloads the selected row. The red
vertical line on the scrub bar marks your current delay, so you can line it up
against the frame the hit actually connects. Readout is
`position / length (delay ms)`.

**Quick Edit Timing** writes straight into the database:

| Field | Meaning |
|---|---|
| Delay (s) | When the hit lands, from animation start. Stored as ms |
| Hitbox X / Y / Z | Box measured in the **attacker's** local space — X is their right, Z is forward |
| HSO | Hitbox size offset: studs added to every axis before the check |
| Shape | `Block` / `Sphere` / `Cylinder`. All three are real gates, not drawings |
| Face Fwd | `On` puts the volume in front of the attacker instead of centred on them |
| Shift Ofs | Extra studs along their look vector. Negative pulls back |
| Ground | `On` sits the volume on their feet instead of their root |
| Max Dist | Hard distance cut-off, checked before the hitbox |
| Repeat | How many parries to fire, for multi-hit attacks |
| Rep Delay | Seconds between those repeats |
| Dodge Dir | Movement key held across the parry (`None` / Left / Right / Back / Forward) |

The hitbox is why there are three numbers instead of one radius: a wide
horizontal sweep and a narrow forward thrust have very different shapes, and
one distance value cannot describe both without false-firing on the other.

### Hitbox Preview

Builder tab, its own groupbox. **Show Hitbox** draws the gate as a real box in
the world, and the sliders under it redraw on the frame you move them — there is
no apply step to see a change.

| Control | What it does |
|---|---|
| Show Hitbox | Draws the box. Green while you are inside the gate, red while you are not |
| Draw On | `Nearest Enemy` or `Self`. Falls back to your own rig when nothing is alive nearby |
| Hitbox Shape | `Block`, `Sphere` or `Cylinder` |
| Hitbox X / Y / Z | Box dimensions in studs |
| HSO | Studs added to every side |
| Face Forward | Push the volume out in front of the attacker instead of centring it on them |
| Shift Offset | Extra studs along their look vector, negative to positive |
| Ground Align | Sit the volume on the rig's feet rather than its root |
| Show Enemy Hitboxes | Draw each attacker's gate across its damage window, then hide it the frame the window closes |
| Measure Real Hitboxes | Draw the game's own hitbox part at its true size when it spawns one, and save that over an untuned box |
| Show Max Distance | Flat ring at the distance cut-off |
| Max Distance | Radius of that ring |

The box is drawn on the **attacker's** root CFrame, not yours, because that is
the frame the check is measured in — X is their right, Z is their forward. Draw
it on yourself and the numbers stop meaning what the parry thinks they mean.

Both the colour and the geometry come from `Engine.inHitbox` /
`Engine.hitboxCFrame` themselves, not a copy of the maths, so the box cannot
drift out of agreement with the actual gate. The three shapes are real gates:
`Sphere` takes the largest axis as its radius, `Cylinder` uses X/Z as its radius
and Y as its height. The label underneath reads
`<rig> | <distance> | INSIDE/outside | <shape> | max <n>m`.

**Face Forward** exists because the default volume straddles the attacker: half
of a 30-stud Z reaches behind them, which is why an untuned box gates hits from
behind. On, the back face lands on their root and the whole depth extends
forward. **Shift Offset** nudges it further either way, and **Ground Align**
drops it so its underside sits on their feet rather than at chest height. All
three are per-timing fields, so they save.

The redraw runs on `BindToRenderStep` just after `Enum.RenderPriority.Camera`,
not on `RenderStepped`. `RenderStepped` fires *before* the camera is updated for
the frame, so a part positioned from it is one camera frame stale relative to
what you are looking at — that lag is the wiggle. Properties are only written
when they actually change, so the wireframe is not rebuilt every frame.

### Enemy hitboxes

**Show Enemy Hitboxes** draws the gate of every attack currently swinging at
you, in orange, on the rig throwing it — and turns it red the moment you are
inside. It fires for every animation that has a **known** timing, enabled or
not, because the whole point is watching an untuned box fail to line up with the
swing before you turn it on.

**Only across the damage window.** An attack animation is mostly wind-up and
recovery; the part that can actually hurt you is a fraction of it. The box
appears `HITBOX_WINDOW_LEAD` ms before the hit lands, stays up until the parry
hold has expired plus `HITBOX_WINDOW_TAIL` ms, and is hidden the frame that
closes — not on a fade or a timer. Both constants live in `src/core/Config.lua`.
The window is scaled by the track's playback speed, so an attack played at 1.5x
lights up proportionally sooner. A swing that gets interrupted during its
wind-up never draws at all, because the hit is never coming.

**Measure Real Hitboxes** is the accurate-sizing path. While a window is open,
the script watches for a newly spawned `BasePart` that is non-colliding and
named like a hitbox — `Hitbox`, `HitPart`, `HurtBox`, `DamagePart` and friends —
either parented inside the attacker's rig or spawned within reach of them. When
it finds one it draws **that part**, at its real size, shape and CFrame, instead
of the tuned box. If the timing was still sitting on the template's 11 × 10 ×
30.5 default, the measurement is written into it and saved, so the guess is
replaced by the real number permanently. A box you have tuned by hand is never
overwritten.

The listener only exists while at least one window is open. A permanent
`DescendantAdded` on the workspace is the most expensive thing this script could
do; one that lives for 200 ms per swing is not.

**This only works if the game makes a client-visible hitbox part.** Plenty run
their hits as a server-side raycast or an `OverlapParams` query with nothing on
your client to look at, and in those games nothing spawns, nothing is measured,
and the tuned box is drawn exactly as before. There is no way to read a size
that was never replicated to you.

The ring is the ground-plane projection of a 3D root-to-root radius, so it is
exact on level ground and slightly generous when the attacker is above or below
you.

These sliders are deliberately separate from the timing database. Nothing is
written until you press **Apply To Selected**, so you can drag them around
mid-fight without touching a tuned entry. **Load From Selected** pulls the other
way. Both act on the logger row you last clicked, falling back to the **Timing**
dropdown. Clicking a logger row also pushes that timing into these sliders, so
the box on screen matches the animation in the visualizer.

Parts are parented to `Workspace.CurrentCamera`, which renders but never
replicates.

**Save & Apply** writes the fields and keeps the enabled flag as-is.
**Add To Parry List** / **Remove From Parry List** flips it. The label bottom-left
tells you which state you are in.

---

## Unknown effects

Some attacks never touch an `Animator` at all. Projectiles, ground slams,
telegraph decals and cast sounds arrive as new instances in the workspace
instead, which the animation hooks are structurally blind to. The **Effects** tab
watches for those.

1. Turn on **Log Effects** and **Show Effect Window**.
2. Fight something. Parts, sounds and particle emitters spawning within **Log
   Range** land in the window as `Time | Effect | Type | Creator | Dist | N`.
3. Click a row. The right-hand viewport clones and spins the instance so you can
   see what it actually is, and the builder fields fill in with its name.
4. Set **Trigger Distance**, tick **Dodge Instead Of Parry** if a parry does
   nothing about it, hit **Save Effect**, tick **Enabled**.
5. Turn on **React To Effects**.

Two things keep the log readable rather than a wall of noise. The workspace
churns constantly, so only instances that appear near you and are plausibly
combat effects get through the filter — anything inside a rig is that rig's body
or gear, not a spawned effect. And it is one row per **name**, with a counter: a
boss firing forty identical projectiles is one entry that says `40`, not forty
rows.

Profiles match on name, because that is the only property stable across spawns.

| Field | Meaning |
|---|---|
| Effect Name | Matched against the instance's `Name`, exactly |
| Trigger Distance | How close it has to spawn, 0–150 studs |
| Dodge Instead Of Parry | For projectiles a parry does nothing about |
| Dodge Direction | `Auto` reads whichever movement key you are already holding |
| React Delay | Wait this long after it appears. Telegraph decals land well before their hit |
| Hold Time | How long the parry key is held, when parrying |
| Enabled | Off means the profile is recorded but never fires |

The parry branch goes through `Engine.fire`, the same path an animation timing
uses, so the cooldown, the dead check and the skip-if-key-held guard all still
apply. The preview **clones** the instance rather than reparenting it —
reparenting a live projectile into a `ViewportFrame` removes it from the game.

The listener only exists while **Log Effects** or **React To Effects** is on;
`DescendantAdded` on the whole workspace is a firehose, so it is not left
running for nothing.

---

## Dodging

Main tab, its own groupbox. Two dash styles, because games are split on it:

| Style | What it sends |
|---|---|
| `Key + Direction` | Holds W/A/S/D, taps the dash key, releases. What games with a dedicated dash bind expect |
| `Double Tap` | Taps one movement key twice inside the game's double-tap window. What games with no dash bind expect |

The direction goes down first and comes up last, because the game samples your
movement vector at the instant the dash key registers — release it early and a
side dash becomes a neutral one.

| Option | What it does |
|---|---|
| Dash Key | The dash bind. Ignored in `Double Tap` |
| Manual Direction | Direction for the manual keybind. `Auto` reads the key you are already holding |
| Standing Still | Direction used when `Auto` has nothing to read. Defaults to `Backward` |
| Dash Hold | How long the dash key is held |
| Dash Cooldown | Minimum gap between two dashes |
| Auto Dodge if Parry Cooldown | Lives on the Auto Parry tab. Dash out when an attack fires and the parry cannot |
| Manual Dash | Keybind that fires one dash per press |

**Auto Dodge if Parry Cooldown** only triggers on the refusals worth dashing through —
parry cooldown, your own manually held key, and a Miss Chance drop. `disabled` and `dead` are not:
dashing when the whole feature is off, or when you are a corpse, is noise.

---

## Storage

**Everything is saved locally, automatically.** There is one file per place and
it is written the instant anything changes — a stub created, a slider applied, a
hitbox measured, a timing deleted. There is no Save button, no config name and
no named configs, because every one of them was a way to lose an hour of tuning
by forgetting to press something.

```
AutoParry/
  timings/
    <PlaceId>/
      default.json           <- the timing database
  effects/
    <PlaceId>/
      default.json           <- the effect profiles
  settings/
    <PlaceId>/               <- LinoriaLib UI config (sliders, toggles)
  themes/                    <- LinoriaLib themes
```

Timings, effects and UI settings are deliberately separate trees: a database is
the thing you actually build up over hours of play, and it should not be sat
next to files that a theme change can rewrite.

Load order on launch:

| State | Where it loads from |
|---|---|
| A local file exists | That file. It is the one you have been tuning, and startup must never overwrite it |
| No local file yet | This repo, written straight to disk so the next launch is instant and offline |
| No filesystem at all | This repo, in memory only. You get a notification saying tuning will not persist |

**Download Timings** is the manual escape hatch: it pulls the repo copy over
your local one, which is why it wants a double click.

**Copy Database** and **Copy Effects** put the whole JSON on your clipboard —
that is how tuning gets from your machine back into this repo.

**Download Timings** and **Download Effects** are the manual re-pull. Both are
double-click, because they discard what is loaded.

### Shipping a database with the script

`timings/<PlaceId>/default.json` and `effects/<PlaceId>/default.json` in this
repo are what every player gets. The `<PlaceId>` folder name is what the script
matches on, so it has to be the real place id — one database per place, so a
build for one game never bleeds into another.

To publish, paste your clipboard export into the matching file and commit it.

The fetch URL is `ctx.DATA_REPO` in `src/core/Config.lua`. It has to point at the
same repo and subfolder the modules load from, or every launch silently finds
nothing.

With writes on, folders are created segment by segment, because plenty of
executors will not create intermediate directories for you.

The JSON is plain and hand-editable:

```json
{
  "version": "1.0.0",
  "placeId": 4111023553,
  "timings": {
    "rbxassetid://12345678": {
      "id": "rbxassetid://12345678",
      "name": "Bounder",
      "delay": 420,
      "length": 0.7,
      "minDistance": 0,
      "maxDistance": 85,
      "holdTime": 120,
      "enabled": true,
      "ignoreEnd": false,
      "note": "",
      "hitbox": { "X": 11, "Y": 10, "Z": 30.5 },
      "hso": 3,
      "shape": "Block",
      "faceForward": false,
      "forwardOffset": 0,
      "groundAlign": false,
      "repeatCount": 1,
      "repeatDelay": 0.35,
      "dodgeDir": "None"
    }
  }
}
```

The effect database is the same shape, keyed on effect name instead of animation
id:

```json
{
  "version": "1.0.0",
  "placeId": 4111023553,
  "effects": {
    "SlamShockwave": {
      "name": "SlamShockwave",
      "triggerDistance": 45,
      "delay": 180,
      "holdTime": 120,
      "dodge": true,
      "dodgeDir": "Auto",
      "enabled": true
    }
  }
}
```

Configs saved by an older build load fine — missing fields get backfilled from
the template on load, so upgrading never means rebuilding a database by hand.

`ignoreEnd` has no UI toggle — set it in the JSON for attacks whose animation
stops before the hit lands, and the fire-time "is it still playing" check gets
skipped for that timing.

---

## Options

**Main tab**

| Option | What it does |
|---|---|
| Parry Key | Key sent to parry. Default `F` |
| Timing Offset | Parry this many ms earlier, 0–150. Raise it if you are getting clipped just before the parry lands |
| Auto Dodge if Parry Cooldown | Dash out when the parry cannot go out — on cooldown, key held, or dropped by Miss Chance |
| Entity Source | `Auto` checks Live, Characters, Enemies, Mobs, NPCs then falls back to workspace |
| Only When Targeted | Requires an `ObjectValue` named `Target` on the entity pointing at you |
| Require Facing | Dot product gate on the attacker's look vector |
| Skip If Key Held | Does not fight your own manual input |
| Randomise Offset | Jitter so every parry is not frame-identical |
| Miss Chance | Chance to intentionally drop a parry |
| Dash Style | `Key + Direction` or `Double Tap` |
| Dash Key | The game's dash bind |
| Manual Direction | Direction the manual dash keybind uses. `Auto` reads your held key |
| Standing Still | Fallback direction when `Auto` has nothing to read |
| Dash Hold | How long the dash key is held |
| Dash Cooldown | Minimum gap between two dashes |
| Notify On Dash | Notification per dash. Useful while tuning, noisy after |
| Manual Dash | Keybind that fires one dash per press |

**Effects tab**

| Option | What it does |
|---|---|
| Show Effect Window | The logger window with the 3D preview |
| Log Effects | Record spawned instances near you |
| Only Log Unknown | Hide anything that already has a profile |
| Log Range | How far out to record, in studs |
| React To Effects | Fire the saved profiles. Works with logging off |

---

## Notes

- `Entity Source` set to `Custom` uses the **Folder Name** input. That input is
  not inside a dependency box on purpose — LinoriaLib's `Depbox:Update` only
  evaluates dependencies whose element type is `Toggle`, so a dropdown
  dependency would never hide anything.
- The parry is a keypress, not a remote call. Remote-level parrying is possible
  but needs per-game reverse engineering of the remote names and argument
  shapes; this script does not guess at them.
- Re-sweeps animators on respawn and whenever you change the entity source.
