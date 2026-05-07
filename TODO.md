# Project Status

## Current Pipeline Status

- Main pipeline scripts `01` through `07` have been rerun after the data-quality fixes.
- Final public panel: `output/panel_data_public.csv`.
- Final panel dimensions: 171,621 municipality-year rows, 10,992 Destatis 2021 AGS codes, years 2005-2021 with no 2009 municipality panel.
- Missing higher-speed tiers are preserved as missing values in 2005-2008 rather than filled with zero.
- AGS standardization filters 68,328 post-deduplicated long rows covering 1,206 historical AGS codes that cannot be mapped defensibly to Destatis 2021 boundaries.

## Remaining Follow-Ups

- Add a maintained verification framework if we want checks beyond the direct R validation commands used in this release.
- If additional historical municipality-name crosswalks become available, revisit `output/unmapped_ags_for_review.csv`, especially the Sachsen-Anhalt codes.
