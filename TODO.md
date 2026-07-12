# Project Status

## Current Pipeline Status

- v3.0.0 (July 2026): trailing non-reporting zeros removed from 2015-2021 (141 municipality-years, mostly gemeindefreie Gebiete dropping ~100% -> 0% at 2021; audit `output/nonreporting_zero_blocks_2015_2021.csv`), and NI `03159501` ("Harz, gemeindefreies Gebiet") recovered for 2019-2020 via a relaxed reform fallback. Net: -141 / +2 municipality-years, 1 revised value. Standing release gate added: `src/auxiliary/verification/run_release_checks.R`.
- v2.1.0 (July 2026): the public panel gains `tier_baseline`/`tier_gte1`/`tier_gte6`/`tier_gte30` columns recording the speed tier behind each share value. The share columns are filled from the lowest reported tier at or above the named threshold, and the 1/6/30 Mbps tiers are only reported from 2018 (`share_gte6mbps` is >=50 coverage in 2010-2012 and >=16 in 2013-2017; `share_gte30mbps` is >=50 through 2017; gte1/baseline are >=2 through 2017). Codebook corrected; share values unchanged. Four latent code bugs fixed.
- Final public panel: `output/panel_data_public.csv`.
- Final panel dimensions: 140,093 municipality-year rows, 10,994 Destatis 2021 AGS codes (including Berlin and Hamburg), years 2005-2021 with no 2009 municipality panel.
- The Destatis 2021 reference is generated reproducibly by `src/main_pipeline/00_build_ags_reference.R`.
- A nearest-year crosswalk fallback and a relaxed reform fallback in step 06 recover historical AGS codes delivered under a different boundary vintage than their year label. The residual filter drops 9,726 post-deduplicated long rows (0.32%) covering 121 historical AGS codes.
- The 2010-2014 non-reporting zero fix removes 33,138 municipality-years that carried exactly 0 across all speed tiers (false zeros from non-reporting). 2010-2014 now covers ~4,400-4,500 reporting municipalities per year.
- Missing higher-speed tiers are preserved as missing values in 2005-2008 rather than filled with zero.
- Diagnostics: `verify_ags_recovery.R`, `verify_zero_fix.R`, and `run_release_checks.R` in `src/auxiliary/verification/`.

## Follow-Up Plan (drafted 2026-07-11, priority order)

### 1. Case-review the 26 unmapped codes — DONE (2026-07-12), NI recovery SHIPPED in v3.0.0

Reviewed against the 2021 reference, reform mappings, and raw source (see `docs/unmapped_ags_documentation.md`, "Case-review outcome"):

- **25 correctly excluded** (24 RP `07932*`/`07935*` + 1 SL `10942115`): all-tier-zero in 2018-2019, absent from the 2021 municipality reference, no reform path, non-standard Regierungsbezirk-digit-9 coding. Documentation updated; no data change.
- **1 recoverable** (NI `03156501` = "Harz, gemeindefreies Gebiet") -> `03159501`, which is in the 2021 reference. Currently missing from the panel for 2019-2021. Root cause: `resolve_reform_chain` only applies reforms with `reform_year >= source_year`, so the 2016 Osterode->Göttingen reform is skipped for 2018-2021 data carrying the old code. **Fix (value-changing, bundle into the v3.0.0 below):** add a last-resort reform fallback that ignores the year constraint, accepting only unambiguous chains ending in a valid 2021 reference code (analogous to the nearest-year crosswalk fallback). Verify it recovers `03159501` for 2019-2021 and does not perturb any other mapping.

### 2. Retained all-tier-zero municipality-years in 2015-2021 — SHIPPED in v3.0.0 (2026-07-12)

Implemented: the recommended rule (drop any 2015-2021 all-tier-zero municipality-year for a unit with prior positive coverage) removed 141 municipality-years; persistent and leading zeros retained (422). Implemented as a drop (consistent with the 2010-2014 non-reporting removal and preserving the "baseline always observed" property) rather than NA-filled rows. Audit: `output/nonreporting_zero_blocks_2015_2021.csv`. Original diagnosis below for reference.

Analyzed from the final panel (563 all-tier-zero municipality-years across 208 municipalities in 2015-2021; the earlier audit-file count of 697/284 is the pre-standardization historical view). Both earlier notes were wrong about the mechanism: it is not "sandwiched"/embedded zeros. Refined classification by full trajectory:

- **trailing_zero: 114 municipalities** — had positive coverage, then dropped to exactly 0 in a later year (overwhelmingly 100% through 2020 -> 0 in 2021). Almost all are gemeindefreie Gebiete (names "gemfr. Gebiet", "Forstgutsbez.", "...Forst", "...Wald"). This is the false-zero residual: coverage does not physically vanish, so the 2021 zero is a reporting dropout. 75% of all 208 affected units are named as gemeindefreie Gebiete/Forst/Wald/Gutsbezirk; 115 of the 204 all-tier-zero cases in 2021 had positive coverage in a prior year.
- **persistent_zero: 89** — 0 in every observed year; gemeindefreie Gebiete forests where a genuine zero is plausible (or arguably not populated units at all).
- **embedded_zero: 4** (7 municipality-years) — positive before and after a zero; cleanest false zeros (Schöningen gemfr. Gebiet, Enzen, Scheitenkorb, Scheiditz).
- **leading_zero: 1** — negligible.

Classification script: `scratchpad/zero_refine.R` (promote to `src/auxiliary/verification/` when the v3.0.0 work lands).

**Treatment decision needed (value-changing, v3.0.0):** recommended rule = set to NA (non-reporting) any 2015-2021 all-tier-zero municipality-year for a unit that had positive coverage in an earlier year (covers the 114 trailing + 4 embedded = ~119 units); leave persistent zeros as genuine. Alternative: also drop persistent-zero gemeindefreie Gebiete. Confirm the rule before implementing.

### 3. Standing verification script (cheap insurance; do with the next release)

Consolidate the release checks used for v2.0.0/v2.1.0 (`verify_zero_fix.R`, `verify_ags_recovery.R`, plus the v2.1.0 invariants: AGS-year uniqueness, [0,100] bounds, tier hierarchy, tier-composition-by-year table, Destatis reference membership, panel dimensions) into one `src/auxiliary/verification/run_release_checks.R` that fails loudly. Run before every tag.

### 4. Optional: `source_regime` / `reported` metadata (v2.x, additive)

`tier_*` (v2.1.0) covers the measurement-tier dimension. Remaining gaps: a per-observation source identifier (carry `source_paket` from the long file through step 07) and an explicit `reported` flag, which requires deciding whether the public panel should become balanced (adding non-reporting municipality-years as rows with `reported = 0`). Additive if existing rows are unchanged -> minor version.

### 5. Optional: household-weighted Bezirk aggregation for Berlin/Hamburg 2020-2021 (defer)

Requires external Bezirk household counts (Statistik Berlin-Brandenburg, Statistikamt Nord). Known impact is below 1 ppt (all Bezirk values lie in 97-100), and it changes published values -> bundle with the next major release rather than shipping alone.
