# Project Status

## Current Pipeline Status

- v2.1.0 (July 2026): the public panel gains `tier_baseline`/`tier_gte1`/`tier_gte6`/`tier_gte30` columns recording the speed tier behind each share value. A review found the share columns are filled from the lowest reported tier at or above the named threshold, and the 1/6/30 Mbps tiers are only reported from 2018 (`share_gte6mbps` is >=50 coverage in 2010-2012 and >=16 in 2013-2017; `share_gte30mbps` is >=50 through 2017; gte1/baseline are >=2 through 2017). Codebook corrected; share values unchanged. Four latent code bugs fixed (Paket 3 latin1 fallback, inert regex guard in 02, single-comma replacement, inspection error messages).
- Main pipeline scripts `00` through `07` have been rerun after the July 2026 AGS recovery fixes and the 2010-2014 non-reporting zero fix.
- Final public panel: `output/panel_data_public.csv`.
- Final panel dimensions: 140,232 municipality-year rows, 10,994 Destatis 2021 AGS codes (including Berlin and Hamburg), years 2005-2021 with no 2009 municipality panel.
- The Destatis 2021 reference is generated reproducibly by `src/main_pipeline/00_build_ags_reference.R` (the previous committed binary lacked Berlin and Hamburg due to a scientific-notation formatting bug).
- A nearest-year crosswalk fallback in step 06 recovers historical AGS codes delivered under a different boundary vintage than their year label. The residual filter drops 9,948 post-deduplicated long rows (0.33%) covering 122 historical AGS codes.
- The 2010-2014 non-reporting zero fix removes 33,138 municipality-years that carried exactly 0 across all speed tiers (false zeros from non-reporting). 2010-2014 now covers ~4,400-4,500 reporting municipalities per year. The residual within-municipality 2015 break is 1.2 ppt for the baseline; 98% of the previous 57 ppt jump was the false zeros.
- Missing higher-speed tiers are preserved as missing values in 2005-2008 rather than filled with zero.
- Diagnostics: `src/auxiliary/verification/verify_ags_recovery.R` and `src/auxiliary/verification/verify_zero_fix.R`.

## Follow-Up Plan (drafted 2026-07-11, priority order)

### 1. Case-review the 26 unmapped codes (small, bounded; do first)

24 Rheinland-Pfalz codes (2,016 rows), 1 Niedersachsen (222), 1 Saarland (84) in `output/unmapped_ags_for_review.csv`. Look each up in the Destatis Gemeindeverzeichnis (GV-ISys) to identify what the code was and whether a defensible 2021 mapping exists (Rheinland-Pfalz had several Verbandsgemeinde reforms in 2014-2020; the codes may be VG-level or dissolved-municipality codes with clean successors). If mappable, extend `data/gebietsreformen/combined_reform_mappings.rds`; adding constituents to existing weighted means changes values, so recovery ships as a major version (bundle with item 2). If not mappable, document them as correctly excluded in `docs/unmapped_ags_documentation.md` (patch release).

### 2. Classify the 697 retained all-tier-zero municipality-years in 2015-2021 (needs a decision before any change)

Correction to the earlier note: the audit file does not support "~150 sandwiched between high-coverage years". Only 3 of the 697 kept blocks have positive coverage in both adjacent years (none above 20%); 180 have one positive neighbor, which is consistent with normal rollout starts. The 697 blocks cover 284 municipalities; only 7 are persistently zero in 5+ years.

Plan: classify each of the 284 municipalities by full coverage trajectory (not just +/-1 year): (a) zeros embedded anywhere inside an otherwise high-coverage trajectory -> likely non-reporting; (b) leading zeros before first observed rollout -> plausible genuine; (c) persistently or near-persistently zero -> check municipality size (tiny units can genuinely have 0% fixed-line coverage). Produce a classification table, then decide treatment per class (drop vs set NA vs keep) - value-changing, so v3.0.0 territory. Discuss the rule before implementing.

### 3. Standing verification script (cheap insurance; do with the next release)

Consolidate the release checks used for v2.0.0/v2.1.0 (`verify_zero_fix.R`, `verify_ags_recovery.R`, plus the v2.1.0 invariants: AGS-year uniqueness, [0,100] bounds, tier hierarchy, tier-composition-by-year table, Destatis reference membership, panel dimensions) into one `src/auxiliary/verification/run_release_checks.R` that fails loudly. Run before every tag.

### 4. Optional: `source_regime` / `reported` metadata (v2.x, additive)

`tier_*` (v2.1.0) covers the measurement-tier dimension. Remaining gaps: a per-observation source identifier (carry `source_paket` from the long file through step 07) and an explicit `reported` flag, which requires deciding whether the public panel should become balanced (adding non-reporting municipality-years as rows with `reported = 0`). Additive if existing rows are unchanged -> minor version.

### 5. Optional: household-weighted Bezirk aggregation for Berlin/Hamburg 2020-2021 (defer)

Requires external Bezirk household counts (Statistik Berlin-Brandenburg, Statistikamt Nord). Known impact is below 1 ppt (all Bezirk values lie in 97-100), and it changes published values -> bundle with the next major release rather than shipping alone.
