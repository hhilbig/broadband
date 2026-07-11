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

## Remaining Follow-Ups

- Review the 697 all-tier-zero municipality-years in 2015-2021 listed in `output/nonreporting_zero_blocks.csv` (retained in the panel; mostly persistently zero small municipalities where a genuine zero is plausible, but ~150 are sandwiched between high-coverage years and are likely false).
- Review the 26 remaining case-review unmapped codes (24 Rheinland-Pfalz, 1 Niedersachsen, 1 Saarland) in `output/unmapped_ags_for_review.csv`.
- Optional: add `source_regime` and `reported` metadata variables to the public panel so users can model measurement regimes flexibly.
- Optional: replace the unweighted 2020-2021 Bezirk aggregation for Berlin/Hamburg with a household-weighted mean if external Bezirk population data are added.
- Add a maintained verification framework if we want checks beyond the direct R validation commands used in this release.
