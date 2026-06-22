# GSE_Tracker — Session Handoff (Classic meters + cleanup)

> Read this first in a fresh session. Self-contained.

## Repo / setup
- **GSE_Tracker** — standalone WoW addon, sibling to GSE-Advanced-Macro-Compiler (separate addons;
  only `tracker/gse_bridge.lua` may touch `_G.GSE`).
- Path (note backticks): `...\ScaryLarryGames\Git\GSE_Tracker`
- Git: branch **main**, remote `github.com/LarryThiessen/GSE_Tracker.git`. Last released tag **v1.3.3**.
- Release flow: push a `v*` tag → `.github/workflows/release.yml` (BigWigs packager) → CurseForge + GitHub.
- Dev: WoW AddOns junctions → live `/reload` (and `/rl`, restored). `luac -p <file>` for syntax checks.
- 4 flavor TOCs: `GSE_Tracker.toc` (120007), `_Vanilla` (11507 / Era), `_TBC` (20505 / "Anny"), `_Mists` (50504 / MoP).
- **Standing rules:** always give a `/reload` go/no-go; root-cause discipline (prove → fix → verify); every change works on all flavors (see root `CLAUDE.md`).

## STATUS: large UNCOMMITTED batch on top of v1.3.3
`git diff --stat`: ~37 files, ~+300 / −4000. **User's plan was "commit only (no release)"** but kept
iterating; nothing committed yet. When ready: `git add -u` + commit (4 deleted files already staged as
deletions by `-u`; strays `SESSION_HANDOFF.md` + `media/GTLogin/Wow_*.png` stay UNtracked). Decide
commit-only vs release v1.3.4.

### What's in the batch (all luac-clean; MoP-verified where noted)
1. **Dead-code purge (~3,900 lines):** removed the legacy standalone options window
   (`options/options.lua` body + `sections.lua` + `tabs.lua` + `refresh.lua` + their TOC lines —
   superseded by the Blizzard Settings canvas in `settings_panel.lua`), CenterMarker rename-leftover
   aliases (db.lua/player_tracker), abandoned features (SetupGlowHook, oldest-fade, AnimateIconsToSlots…),
   unused constants/funcs. Multi-agent review done; verified no dangling callers.
2. **Errors fixed:** savedvars pressed-size clamp (4–24 → 10–50); Meters `x ~= nil and x or saved`
   boolean idiom; DPS/HPS `C_DamageMeter` guards; **Pressed Indicator Class colour** (UnitClass
   multi-return truncation — now uses `uiShared.GetPlayerClassColorRGB`).
3. **Press Detection** (Center Marker): toggle on the Meters tab; marker monitors input & blinks like
   the Pressed Indicator via shared `UI:ComputePressState` (ui/indicator.lua). White shapes flash
   green/red; full-colour art keeps colours.
4. **"Player Tracker" → "Center Marker"** rename throughout; legacy tab keys kept.
5. **Name source:** grey "GSE Sequence Name" + fall back to Spell Name when GSE absent
   (`GetActionTrackerUseSpellName` returns true if `_G.GSE==nil`); removed Macro-Name swap; example
   text "Sequence / Spell".
6. **Sliders on Anny (TBC):** option sliders draw the **stock Blizzard groove texture**
   (`UI-SliderBar-Background`, horiz-tile) via CreateTexture — `OptionsSliderTemplate` doesn't draw a
   groove and has no SetBackdrop on TBC. (`AddSliderTrack` in settings_panel.lua.)
7. **Force Blizzard Native font:** now reads stock `ActionButton1`'s font (per-client native), not the
   configured font (utils/shared.lua `GetActionButtonFont`).
8. **Center Marker dropdown filter:** drop AHLight (no `ns.Caps.assistedHighlight`) AND Specialization
   (`GetNumSpecializations() <= 0`) — Era/TBC hide them; MoP/Retail keep them.
9. **Classic Meters (MoP-CONFIRMED working):**
   - GCD readout ungated (Blizzard cooldown read, spell 61304): `_G.GSETracker_GCDCapable=true`; GCD.lua gated on it.
   - DPS/HPS read from the **Details! addon** when no real C_DamageMeter
     (`_G.GSETracker_DetailsPerSecond(1=dmg/2=heal)` in compat.lua; DPS/HPS.lua gate on
     `_G.GSETracker_MetersCapable`, NOT bare `C_DamageMeter` — MoP has a stub C_DamageMeter table).
   - Per-feature gates in Meters.lua: `GCDOK()` / `DPSHPSOK()` (live `GSETracker_HasDPSSource()` =
     C_DamageMeter OR `_G.Details`) / `AHUsageOK()`. MetersOK = GCDOK or DPSHPSOK.
   - MetersOptions greying runs once at **PLAYER_LOGIN** (Details! may load after us): grey DPS/HPS +
     Details controls if no DPS source; SBA% if not mainline; GCD + sliders never greyed.
   - **Details window controls** (Show / Hide-in-Combat) drive the **Details! addon's own window** on
     Classic via `Details:GetInstance(1):ShowWindow()/:HideWindow()/:IsEnabled()` (meters/Details.lua
     branches when not `GSETracker_MetersCapable`).
   - **Meters Opacity** now fades the Center Marker too (it's UIParent-parented, doesn't inherit the
     anchor alpha): player_tracker `GetMetersOpacity()` multiplies marker alpha; `Meter_SetOpacity`
     calls `_G.GSETracker_RefreshCenterMarker()`.
   - **Specialization marker on MoP:** `GetSpecialization()` returns nil on MoP Classic; resolver falls
     back to `GetPrimaryTalentTree()` → `GetTalentTabInfo(tree)` (icon = 4th return). (player_tracker
     `ResolveDynamicMarkerTexture`.)
10. Marker images re-encoded to 8-bit RGBA (indexed PNGs showed green blocks); manifest regenerated.
11. **`/rl`** reload alias restored (utils/debug.lua).
12. **Spec-icon border: tried, then REMOVED** at user request ("tired of messing with it") — no
    border/mask on the Center Marker icon now.
13. Added root `CLAUDE.md` (cross-version rule) — excluded from the shipped zip via `.pkgmeta`.

## Proven in-game facts (MoP Classic 5.5.x / interface 50504, Feral druid)
- `_G.Details` present; `Details:GetCurrentCombat():GetActor(1,UnitName"player").total / :GetCombatTime()` → DPS (attr 2 = healing).
- `Details:GetInstance(1)` → `:ShowWindow()/:HideWindow()/:IsEnabled()` (and `:ToggleWindow` exists).
- `GetNumSpecializations()` = 4 but `GetSpecialization()` = nil; `GetPrimaryTalentTree()` = 2; `GetTalentTabInfo(2)` → id,name,desc,**icon(132115)**.
- MoP exposes a **stub `C_DamageMeter`** (non-functional) — never gate on bare existence; use `_G.GSETracker_MetersCapable`.

## PENDING / next steps
- **Commit the batch** (commit-only or release v1.3.4) — user's call.
- **Test on Anny (TBC):** GCD spell 61304 likely absent pre-Wrath → GCD may show blank there. If so, add a
  **haste-based GCD** fallback (`1.5/(1+haste)` driven off casts) for Era/TBC.
- Verify Details-window toggle + Meters opacity on MoP in-game (built, not yet user-confirmed).
