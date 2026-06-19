# GSE: Tracker — Developer Rules

## Cross-version compatibility (HARD RULE)

**Every change MUST work on all supported WoW flavors — not just the one you're testing on.**
Supported flavors and their TOCs:

| Flavor | TOC | Interface | `WOW_PROJECT_ID` |
|---|---|---|---|
| Retail | `GSE_Tracker.toc` (`_Mainline`) | 120007 | 1 (`WOW_PROJECT_MAINLINE`) |
| Classic Era (Vanilla) | `GSE_Tracker_Vanilla.toc` | 11507 | 2 |
| Burning Crusade Classic (Anniversary) | `GSE_Tracker_TBC.toc` | 20505 | 5 |
| Mists of Pandaria Classic | `GSE_Tracker_Mists.toc` | 50504 | 19 |

A change that loads on Retail but errors on Classic Era (or vice-versa) is a regression. APIs differ in **both** directions: some `C_*` namespaces are Retail-only, and some legacy globals (`GetSpellInfo`, `GetSpellCharges`, `GetAddOnMetadata`, …) were **removed on Retail**.

### How to stay compatible

1. **Use the `utils/api.lua` wrappers** for anything version-sensitive instead of calling the
   raw API. They already fall back across `C_Spell`/`C_AddOns` ↔ legacy globals:
   - `API.GetSpellTexture`, `API.GetSpellName`, `API.GetAddOnMetadata`, `API.CreateFrame`,
     `API.GetTime`, `API.UnitClass`, … If you need a new version-sensitive call, **add a wrapper
     here** rather than calling it inline.

2. **Gate Retail-only subsystems on capability flags, not bare existence.** Some Classic clients
   expose *stub* `C_*` tables that pass `if C_Foo then`. Use the published flags from
   `utils/compat.lua`:
   - `ns.Caps.assistedHighlight` — `C_AssistedCombat` (AND `mainline` flavor)
   - `ns.Caps.meters` — `C_DamageMeter` (AND `mainline` flavor); mirrored as the global
     `_G.GSETracker_MetersCapable` for the `meters/*` engine files
   - `ns.Caps.settingsPanel` — Blizzard `Settings` canvas
   - `DetectFeatures()` gates these on `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, **not** just API
     presence — keep that pattern.

3. **Existence-check any inline version-specific API** you can't route through a wrapper:
   `if GetSpecialization and GetSpecializationInfo then …`,
   `if Settings and Settings.OpenToCategory then …`,
   `if C_Spell and C_Spell.GetSpellCooldown then … elseif _G.GetSpellCooldown then … end`.
   Prefer the `C_*` form first (Retail), legacy global as the fallback (Classic).

4. **Retail-only features must degrade, not break.** On Classic the feature should be inert and
   greyed out in the options (see the `ns.Caps` checks + grey-out in `options/settings_panel.lua`).
   The **Center Marker** is the one Meters-group element that works on Classic — keep it working.

5. **The game runs Lua 5.1.** `luac` 5.4 is fine for a syntax check, but don't use 5.2+ syntax
   (goto/`<close>`, integer division `//`, bitwise operators, etc.).

### Before committing — checklist

- [ ] Syntax-check every changed file: `luac -p <file>` (all `.lua` must pass).
- [ ] No new **unguarded** Retail-only `C_*` call (`C_AssistedCombat`, `C_DamageMeter`,
      `C_ClassTalents`, `Settings.*`, …) and no new **unguarded** legacy global that's gone on
      Retail (`GetSpellInfo`, `GetSpellCharges`, `GetSpellCooldown`, `GetAddOnMetadata`, …).
- [ ] New version-sensitive access goes through `utils/api.lua` or an existence check.
- [ ] If you added a `.lua` file, add it to **all four** TOCs.
- [ ] Bump `## Version:` in all four TOCs together for a release.

## Other notes

- **Marker images** (`media/marker-images/`) must be **8-bit RGBA PNG** (or TGA) at **power-of-2**
  sizes (e.g. 256×256). Indexed/palette PNGs and non-power-of-2 sizes render as a **green block**
  in-game. After adding/removing arbitrarily-named images, regenerate the manifest:
  `bash tools/gen_marker_manifest.sh`. (Numbered `CrosshairsNNN.png` are auto-detected at load.)
- **GSE: Tracker and the GSE macro compiler are separate addons.** Only `tracker/gse_bridge.lua`
  may touch `_G.GSE`; never modify the GSE repo for tracker work.
