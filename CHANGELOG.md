# Changelog

All notable changes to GSE: Tracker will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.5.9] - 2026-06-28

### Added
- Retail: the Cooldowns feature now rides Blizzard's native **Cooldown Manager**. New **Essential Cooldowns** / **Utility Cooldowns** Layout Control elements pin `EssentialCooldownViewer` / `UtilityCooldownViewer` to a grid cell, so charges, stacks and the (secret) cooldown timers render Blizzard's own way — replacing the custom Cooldowns bar on Retail. The custom bar + spell picker remain on Classic (no Cooldown Manager there).
- Native cooldown icons adopt the active action-bar skin (border + icon mask) via the same `uiShared` rules as the rest of the UI; left native under Force Blizzard Native Skin / no skinner.

### Changed
- Cooldown viewer layout: centred on the cell, wrapped at the player's Icon Limit, icon order rotates 90° per side (never a 180° flip), and the block butts the Meters cluster edge.
- Center Marker Press Detection now follows the Meters HUD visibility instead of hiding between presses; it blinks brighter (alpha eases 1.0 → ~0.40) on each press.
- AH % readout flashes for ~2s on each new match instead of a continuous 50%+ pulse.

### Fixed
- Classic: `ns.Caps.cooldownManager` and the spell-discovery scan (`CooldownElements.lua`) now require Mainline, not just API presence — Classic clients exposing empty `C_CooldownViewer` / `C_SpellBook` stubs no longer hide the custom Cooldowns bar or empty its spell list.
- `EDIT_MODE_LAYOUTS_UPDATED` is now registered via `pcall`, so Classic no longer errors on the unknown event.

## [1.5.8] - 2026-06-28

### Fixed
- Breakdown window no longer throws a Lua error when focused on another combatant (it was comparing taint-protected "secret" C_DamageMeter GUIDs directly).

### Changed
- Cooldowns bar lays out **vertically** when placed on the centre row (the DPS/Marker/HPS line) so it doesn't spill across the readouts; other rows stay horizontal.
- The Meters Edit Mode selection box now re-fits the readout cluster continuously while shown (and self-corrects), instead of measuring once.

### Internal
- Removed a large amount of dead code (the old custom-widget options UI, dead debug globals, the unused Action Tracker move-marker, and the retired SBA% machinery) and de-duplicated the shared cursor-position helper. No user-facing behaviour change.
- Dev-only diagnostic slash commands are no longer shipped in the packaged build.

## [1.5.7] - 2026-06-28

### Added
- Cooldowns spell list now works on Classic flavors (MoP/Cata/TBC/Vanilla) via the legacy spellbook API — your current spec's 6s+ cooldown spells appear there too, not just on Retail.
- Classic Edit Mode: a fallback selection-box overlay (cyan tint, rounded corners, "Click to Edit" on hover) so HUD elements can be positioned on flavors that lack Blizzard's Edit Mode.

### Changed
- Cooldowns bar now follows the Meters HUD visibility setting (hides/shows with the rest of the HUD).
- Cooldowns follow spell upgrades/overrides: a tracked spell that transforms mid-fight (e.g. Bestial Wrath → Wailing Arrow) now swaps its icon and keeps counting down instead of vanishing.
- PRD and AH % elements (and the Assisted Highlight Edit Mode button) are hidden/greyed on the Classic flavors, where those features don't exist.
- The Meters options panel scales to fit shorter screens (e.g. MoP) instead of running off the top/bottom.

### Fixed
- DPS/HPS no longer print a long raw decimal for near-zero values on Classic — they round to a clean number.
- Cooldown swipe no longer flickers (the cooldown is only re-applied when it actually changes).
- `GSETrackerDetails` (the breakdown window) added to the Classic TOCs (TOC drift fix).

## [1.5.6] - 2026-06-28

### Added
- Cooldowns bar (Meters HUD): place a side-by-side row of tracked cooldowns. Each slot is picked from a menu of your spells and trinkets; duplicates are blocked across both the bar and the standalone grid elements.
- Trinkets (Trinket 1 / Trinket 2 / Healthstone) can be added to the Cooldowns bar alongside spells.
- Cooldown spell discovery: the picker lists your current spec's spells with a 6s+ cooldown, rebuilt automatically on login, spec change, talent swap, and spellbook changes.

### Changed
- Cooldown spell filter: General-tab junk (Mobile Banking, Revive Battle Pets, profession/utility items) is excluded; racials and class/spec defensives are kept; passives are always excluded.
- Cooldowns now count down live in combat. The swipe and number are driven by your cast time + the spell's base cooldown (engine-rendered), so nothing stalls until combat ends.
- Layout Control padding (X / Y) now defaults to 0; any value you set persists in your saved variables.

### Fixed
- Mouse Cursor Assisted Highlight stuttered while the options panel was open; it now follows the pointer every frame whenever it's visible.

## [1.3.3] - 2026-06-19

### Added
- Press Detection toggle for the Center Marker: the chosen Center Marker monitors input and blinks like the Pressed Indicator (always shown, pulses on each key/GSE press) via the shared `UI:ComputePressState`. Tintable (white) symbols flash green-on-press / red-when-idle when no colour is chosen, or use the Class/Custom colour; full-colour art and Class/Spec icons keep their own colours. The standalone Pressed Indicator is unaffected.
- Marker images: Crosshairs009, Crosshairs010, YingYang.

### Changed
- Renamed "Player Tracker" to "Center Marker" across the options and code (legacy tab keys preserved for compatibility).
- White/tintable markers with no colour selected now fall back to red instead of white.
- Added a root `CLAUDE.md` documenting the cross-version compatibility rule and sanctioned patterns (excluded from the packaged addon via `.pkgmeta`).

### Fixed
- Marker images saved as indexed-palette PNGs (Dot, Crosshairs009/010) rendered as green blocks in-game; re-encoded to 8-bit RGBA.
- Author field corrected to ScaryLarryGames in all flavor TOCs.

## [1.3.2] - 2026-06-19

### Fixed
- The Action Tracker **Scale** slider now scales the whole tracker (icons + text), not just the text. The icons were being pinned to the action-bar button's on-screen size, which cancelled the Scale slider for them. At Scale 1.00 they still match the action bar exactly.

## [1.3.1] - 2026-06-19

### Fixed
- Element positions now persist. A saved-variable key collision (the legacy "layout" flat key vs the current `layout` element table) wiped the saved offsets on every save, so dragged elements — the Pressed Indicator, the Sequence/Macro/Spell name, and the Modifier text — snapped back to their default positions after relocking or reloading.
- The Pressed Indicator now stays above the Action Tracker icons (it no longer drops behind them when the options panel is open).

## [1.3.0] - 2026-06-18

### Added
- **Classic support.** GSE: Tracker now loads on Classic Era (Vanilla), Burning Crusade Classic (Anniversary), and Mists of Pandaria Classic, each via its own TOC (`_Vanilla` / `_TBC` / `_Mists`).
- Retail-only features (Assisted Highlight, and the Meters readouts: DPS / HPS / GCD / SBA% / Details) are automatically greyed out and disabled on Classic, where their APIs don't exist. The Center Marker still works on Classic.
- The "loaded" chat line now shows the running interface version; on Classic it adds a note that greyed-out features aren't available on that version.

### Fixed
- Classic: Shaman class color showed Paladin pink (a Blizzard `RAID_CLASS_COLORS` data quirk) — now forced to the correct blue.
- Classic: Action Tracker icons no longer show a gap between the icon and the stock button border; the modifier label spacing was tidied.
- The Center Marker and Pressed Indicator now drop below the options panel while it's open (they no longer grab its sliders or draw over it) and return to the top when it closes.
- Fixed a phantom modifier (e.g. "LCtrl") sometimes shown right after logging in — modifier state now reconciles from live key state.
- Removed the false "below minimum tested / compatibility mode" warning on Classic.

## [1.2.1] - 2026-06-18

### Added
- First-login welcome walkthrough: a 5-page visual guide (General, Meters, Assisted Highlight, Action Tracker, Quality of Life) shown once per login. Page through it with the arrows; dismiss with "Hide Login Message" (also a General-tab option).
- GitHub and bug-report links in the options social bar.
- A "Visibility" heading above the General-tab show-when dropdowns.

### Fixed
- Opening the options window while in combat no longer throws an error — it's deferred with a notice until combat ends.
- Removed the false "compatibility mode" warning on the current client (interface target updated to 120007).

## [1.1.5] - 2026-04-12

### Changed
- Minimap button left-click now opens settings; left-click drag moves the button (previously right-drag)
- Right-click now hides the minimap button and persists the hidden state across sessions
- Tooltip updated to reflect new left-drag and right-click-to-hide behavior

### Added
- `/gsetracker minimap` slash command to show the minimap button after it has been hidden

## [1.1.4] - 2026-04-08

### Fixed
- Settings GUI lag eliminated — slider +/- buttons and enable/disable toggles now respond instantly
  - Added state-signature cache to `SetCombatMarkerControlsEnabled` and `SetAssistedHighlightControlsEnabled`: bails early when the enabled/locked/color-enabled state hasn't changed, eliminating ~60 redundant WoW frame API calls per click during normal slider adjustments
  - Added value guard to `syncSliderControl`: only calls `SetValue` when the value actually differs, preventing cascade `OnValueChanged` re-triggers for unchanged values
  - `RefreshCombatMarkerControls` now routes all slider updates through `syncSliderControl` for consistent guarding

## [1.1.3] - 2026-04-05
- Initial public GitHub release
