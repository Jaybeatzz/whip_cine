# whip_cine

A cinematic director for **WHIP** FiveM servers. Fly a free camera, lay keyframes on a timeline,
and stage actors and lights. Drop in ready-made camera moves and scenes, then record the result
with the Rockstar Editor.

> **Unofficial.** whip_cine is a community resource. It is not made, endorsed or supported by the
> WHIP team. It is a fork of **[aty_cinematic](#credits-and-license) by atiysu**, ported to WHIP.
> The camera, timeline, actors, lights, presets and recording are atiysu's work; this fork adds the
> WHIP integration and the WHIP look.

Everything you stage is local to the person filming. Actors and lights are not synced to other
players.

## What the WHIP port adds

- **Permissions.** WHIP permissions you grant in `/whip`: `whip_cine.use` opens the director and
  `whip_cine.manage` lets staff see, open and delete everyone's projects. Full admins hold both
  automatically.
- **Secure server calls.** Every request is a WHIP `SecureCallback`, so WHIP checks the rate limit
  and parameters before the handler runs. Refusals show in `/whip → System → Monitor`.
- **Per-character projects** stored in your database (table `whip_cine_projects`, created
  automatically with `EnsureTable`). Each character sees only their own projects.
- **Settings page** at `/whip → Config → Cinematic Director (whip_cine)`: projects per character,
  autosave, actor and light limits, player hiding and freezing, recording and depth of field.
- **Plays nicely with WHIP.**
  - `HoldPlayerPed` freezes and protects the filming player, so WHIP's anti-tamper doesn't flag it.
  - `HoldCleanScreen` hides WHIP's HUD, prompts and world marks.
  - `SetScreenOpen` and `BlockControls` keep WHIP's prompts, hotbar and wheels out of the way.
  - The director won't open on top of another WHIP screen (such as `/whip` or the inventory).
- **Time and weather.** A WHIP weather layer holds the director's time and weather on the
  filming player's screen only. WHIP's sync doesn't overwrite the shot, and nobody else's weather
  changes.
- **WHIP's look.** The interface loads whip_core's own fonts and design tokens
  (`whip_core/html/css/base.css`) and follows any WHIP theme your server runs.

## Requirements

- [WHIP](https://whipfx.net) (`whip_core`) and `oxmysql`
- Node.js 20.19+ only if you want to rebuild the interface. A built copy ships in `ui/`.

## Installation

1. Put the folder in your resources directory as **`whip_cine`**. Keep the name: the server
   callbacks and permission names are built from it.
2. Add it to `server.cfg` **after** WHIP's lines:

   ```cfg
   ensure whip_cine
   ```

3. Restart the server, or run `refresh` and then `ensure whip_cine`.
4. In `/whip`, grant the `whip_cine.use` permission to whoever should film, or
   `whip_cine.manage` for staff. To let everyone use it, set `Config.Access.Permission = false`
   in `config.lua`.

## Usage

Open the director with `/cinematic` (WHIP uses `/director` for its own mission director). The keys can be rebound in FiveM's key binding settings.

| Key | Action |
| --- | --- |
| Right mouse (hold) | Fly and look around |
| W A S D, Q / E | Move, down / up |
| Mouse wheel | Speed (with Shift: field of view) |
| F | Add a keyframe at the playhead |
| Space | Play / pause |
| G | Cursor / fly |
| H | Clean view (hide the panels) |
| Delete | Delete the selected keyframe |
| Backspace | Close the director |

A first shot in four steps: fly to a start pose and press `F`, fly to the end pose and press `F`
again, press `Space` to play it, then use the record button on the timeline to capture it with
the Rockstar Editor.

The director refuses to open while another menu (such as `/whip`) is open: close it first.


## Configuration

Owner-tunable values are on the settings page in `/whip`. Everything else is in `config.lua`:
access, camera feel, shake presets, the Rockstar Editor lead-in, key bindings and the interface
language (`Config.Locale`, `'en'` or `'tr'`).

Ready-made content lives in plain data files:

| File | Content |
| --- | --- |
| `shared/moves.lua` | Camera moves |
| `shared/scenes.lua` | Scene set-ups |
| `shared/looks.lua` | Atmospheres |
| `lists/anims.json` | Emotes |
| `lists/shared.json` | Two-person emotes |
| `lists/peds.json`, `lists/vehicles.json` | Models offered in the Actors panel |

## Building the interface

```bash
cd web
npm install
npm run build
```

The build writes to `ui/`, which the resource serves. The WHIP theme layer is in
`web/src/main.css` (the token map) and at the end of `web/src/layout.css` (WHIP's house rules).

## Known limits

- Actors are static: they stand where you put them and play an emote. There is no path recording
  for peds or vehicles.
- The game's entity outline is deliberately not used to mark a selected actor. On a ped it
  crashes the game, so selection is drawn with lines instead.
- The distances of the two-person emotes are estimates; the panel has a slider to adjust them.
- The weather layer uses WHIP's weather names. A director look with a weather WHIP doesn't know
  still shows on screen, but WHIP's sync may write over it.
- `/cinerecdiag` checks whether anything on your server stops a Rockstar Editor recording.

## Credits and license

- **Original resource:** aty_cinematic by **atiysu**, released under the MIT License. All of the
  director itself (camera, timeline, shake, actors, lights, presets, recording, interface) is
  their work.
- **WHIP port (whip_cine):** the WHIP integration, database storage, permissions and WHIP styling.

MIT licensed: see [`LICENSE`](LICENSE). atiysu's copyright notice must stay with every copy.

This resource only calls WHIP's exports and loads its helper through `shared_script`. It contains
no WHIP files: WHIP's fonts and stylesheet are loaded from whip_core at run time. WHIP is a
trademark of its authors and is used here only to say what this resource works with.
