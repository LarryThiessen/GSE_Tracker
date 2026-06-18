# Changelog

All notable changes to GSE: Tracker will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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
