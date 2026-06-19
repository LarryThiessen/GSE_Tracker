# Changelog

All notable changes to GSE: Tracker will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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
