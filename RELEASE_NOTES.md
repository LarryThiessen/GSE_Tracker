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
