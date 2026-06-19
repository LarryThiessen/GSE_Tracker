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
