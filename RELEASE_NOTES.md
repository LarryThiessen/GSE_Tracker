## 1.5.4

### Fixed
- **Fixed a recurring "integer overflow" Lua error** when adopting an action bar's icon mask (it could fire on login / in Edit Mode). The mask's file id came back as an out-of-range value the game can't store; it's now rejected (the icon just renders square) instead of erroring, with a safety net so it can't throw again.

## 1.5.3

### New
- **Shorter DPS/HPS numbers.** Big numbers now abbreviate (e.g. `242.3K`, `1.23M`) using Blizzard's number formatter — works live in combat on Retail; uses Details! data on Classic.
- **AH Match % is now configurable and fun:**
  - **Colour gradient** — the readout shades red → yellow → green by your match rate.
  - **Pulse** — it pulses at 50%+, faster the higher it climbs.
  - **AH Animated** toggle (Assisted Highlight tab, under AH Match %): turn the colour + pulse on/off (off = plain white).
  - **Add it to the Meters Layout Control** — place "AH %" on the grid and it moves into the Meters HUD (and stops showing under the Action Tracker).
- **Custom Match-Audible sounds.** A pack of bundled sounds (Bloop, Clap, Drum, Kick, Snare, Swoosh, Success, and more) is selectable for the AH Match audible cue; the sound list is now sorted A→Z.

### Changed
- **AH Match % stays put** — it no longer drifts when you reposition the MODKEYS element, and it shows an example in Edit Mode so you can see where it sits.
- **Readout fade-outs are snappier** — the name/keybind and meter readouts now fade on combat-end as fast as the action icons.

### Fixed
- **`/gsetracker` no longer errors in combat** — the meters debug dump was tripping on a taint-protected value.

## 1.5.2

### Fixed
- **Fixed a Lua error on login** ("integer overflow attempting to store…") that came from adopting an action bar's icon mask. The error aborted the UI rebuild partway through.
- **Pressed Indicator no longer resets to centre after a reload/relog.** That was a side effect of the error above — the aborted rebuild never re-applied the indicator's saved position. Your saved position is now restored correctly.

## 1.5.1

### Fixed
- **Disabled elements no longer show in Edit Mode.** Turning off **Meters**, **Action Tracker**, **Assisted Highlight**, or the **Pressed Indicator** in the Enable list now removes its example *and* its selection box, and greys out that row's **Edit Mode** button. The **Center Marker** (part of Meters) hides with Meters too.
- **Pressed Indicator is fully independent of the Action Tracker** — enabling it shows it (in Edit Mode and in play) even when the Action Tracker is disabled.
- **Minimap button:** right-click no longer hides it (a one-misclick footgun — use Options → **Show Minimap Button** to toggle), and it now sits tighter on the ring edge.

## 1.5.0

### ⚠ Heads up
- **Your GSE_Tracker settings reset once with this update.** This release ships a fresh, curated default layout and resets saved settings a single time on first login; after that everything saves normally. Re-apply any personal tweaks.

### New
- **Names now fade out after you stop casting — even out of combat** (previously only when combat ended).
- **Vertical layout polish:** per-icon **Spell Names** beside each icon, **GSE Sequence Name** centred on top, and **MODKEYS** below.

### Changed
- **GSE Sequence Name & Spell Names now use your class colour.**
- **Login welcome popup removed** (the one-line "loaded" chat message stays); the "Hide Login Message" option is gone.
- **~58% smaller download** — removed unused artwork and backups, recompressed images.

### Fixed
- **Meters:** DPS / HPS now show in combat on a fresh profile (they could stay hidden).
- **Edit Mode:** arrow-key nudging now moves the **selected** element (Action Tracker / Meters / Assisted Highlight / Pressed Indicator) instead of always the Pressed Indicator; example names appear as soon as Edit Mode opens, mirror your name toggles, follow the Name font/size, and no longer clip or get buried under the selection box.
- **Breakdown window** reopens where you left it (was jumping to the other side of the screen), and no longer errors when you click the Shop while it's open.
- **Vertical:** icons render *behind* the GSE Sequence Name, and the name stays put as icons populate.

## 1.4.1

### Fixed
- Smooth post-combat fade-outs for the name / keybind readouts.

## 1.4.0

### New
- **Meters / Details overhaul**, dual GSE + Spell name system, full-tracker scaling, and a restructured options GUI.

## 1.3.3

### New
- **Press Detection** for the Center Marker (at the bottom of the **Meters** tab). Tick it and your chosen Center Marker monitors your input and blinks like the **Pressed Indicator** — always shown, pulsing on each key/macro press. White shapes flash **green on press / red when idle** (or your Class/Custom colour if set); full-colour art keeps its own colours. The separate Pressed Indicator is unaffected.
- New marker images: **Crosshair 9**, **Crosshair 10**, and **YingYang**.

### Changed
- **"Player Tracker" is now called "Center Marker"** throughout the options.
- A **white** marker/shape with no colour selected now falls back to **red** (instead of white) so it stays visible. Full-colour art and Class/Spec icons keep their own colours.

### Fixed
- Some marker images showed as a **green block** in-game (Dot, Crosshair 9/10) — they were saved as indexed-palette PNGs, which WoW can't load. Re-saved as standard images.

## 1.3.2

### Fixed
- The Action Tracker **Scale** slider now scales the **whole tracker** (icons + text), not just the text. (At Scale 1.00 the icons still match your action bar.)

## 1.3.1

### Fixed
- **Element positions now save.** Dragged elements — the **Pressed Indicator**, the **Sequence/Macro/Spell name**, and the **Modifier text** — were snapping back to default after relocking/reloading; a saved-variable key collision was wiping the stored offsets on every save. They persist correctly now.
- The **Pressed Indicator** stays above the Action Tracker icons (no longer drops behind them when the options panel is open).

## 1.3.0

### New
- **Now works on Classic!** Loads on **Classic Era**, **Burning Crusade Classic** (Anniversary), and **Mists of Pandaria Classic**.
- Features that need Retail-only APIs — **Assisted Highlight** and the **Meters** readouts (DPS / HPS / GCD / SBA% / Details) — are **greyed out** on Classic; the **Center Marker** still works there.
- The "loaded" chat line now shows your interface version, with a note on Classic that greyed-out options aren't available on that version.

### Fixed
- **Classic Shaman** class color was Paladin-pink (a Blizzard data quirk) — now the correct blue.
- **Classic** Action Tracker icons no longer have a gap to the border; modifier-label spacing tidied.
- The **Center Marker** and **Pressed Indicator** now sit below the options panel while it's open (they no longer grab its sliders or cover it).
- Fixed a **phantom modifier** ("LCtrl") sometimes shown right after logging in.
- Removed a false **"compatibility mode / below minimum tested"** warning on Classic.

## 1.2.1

### New
- **First-login welcome walkthrough.** A 5-page visual guide (General, Meters, Assisted Highlight, Action Tracker, Quality of Life) shows once each login. Page through it with the arrows; tick **Hide Login Message** to stop showing it (also under General settings).
- **GitHub & bug-report links** added to the options social bar.

### Changed
- Added a **Visibility** heading above the show-when dropdowns on the General tab.

### Fixed
- Opening the options window **in combat** no longer errors — it's deferred with a notice until combat ends.
- Removed the false **"compatibility mode"** warning on the current client (interface target updated to 120007).

## 1.2.0

### New
- **Details meter — combat-session paging.** Step through your last 10 combat sessions with the chevron arrows in the title bar (left = older, right = newer / live).
- **Assisted Highlight — "Show Keybind/Stacks".** A single toggle now controls both the keybind text and the stack/charge count on the highlight.

### Changed
- **Assisted Highlight (Target Portrait):** the keybind and stack count are hidden in Target Portrait mode (no room on the round emblem), and the "Show Keybind/Stacks" option greys out there.
- **Pressed Indicator** is now enabled by default; pick the **None** shape to hide it. It pulses in sync with the inputs it is monitoring.
- The tracker's on-icon **keybind text now defaults off** (enable it per element if you want it); existing setups are migrated automatically.
- **Only `/gsetracker` remains** as a slash command (removed `/rl`, `/details`, `/meters`, `/mm`).

### Fixed
- **The Pressed Indicator could be permanently invisible** — it had shipped disabled by default.
- **Closing the options panel with ESC no longer closes the Details window.**
- Minimap icon now renders correctly.
- Modifier labels and the Details combat timer are nudged into better alignment.

### Under the hood
- Removed the unused debug subsystem and its per-call API instrumentation.
- Slimmed the GSE bridge down to sequence-name resolution (GSE provides its own keybind tooling).
- General dead-code cleanup and constant consolidation.
