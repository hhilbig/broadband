# Changelog

All notable changes to the harmonized German municipal broadband panel are documented here. Each version is a git tag and a GitHub Release with `panel_data_public.csv` attached. Versioning follows a semantic scheme: **major** versions change existing values or observations, **minor** versions add data or variables without changing existing content, **patch** versions change documentation only.

## v2.1.0 (2026-07-11)

No existing share values change. This release makes the measurement tier behind each share column observable and corrects codebook errors.

### Added

- **`tier_baseline`, `tier_gte1`, `tier_gte6`, `tier_gte30` columns** in the public panel: the speed tier (Mbps) at which each share is measured, per municipality-year. The share construction takes the lowest reported tier at or above the named threshold, and the 1, 6, and 30 Mbps tiers are only reported from 2018, so before 2018 the shares measure stricter tiers: `share_gte6mbps` is >=50 Mbps coverage in 2010-2012 (identical to `share_gte30mbps` there) and >=16 Mbps in 2013-2017; `share_gte30mbps` is >=50 Mbps through 2017; `share_gte1mbps` and the 2010+ baseline are >=2 Mbps through 2017.
- Break markers at 2013 and 2018 (tier changes) in the release coverage plot.

### Fixed

- **Codebook misstatements**: earlier versions claimed the higher-tier share columns were "missing before this tier is reported" (they are populated from higher tiers from 2010 onward) and that the baseline uses ">=1 Mbps from 2010 onward" (it uses >=2 Mbps in 2010-2017).
- Latent pipeline bugs with no effect on outputs: the Paket 3 latin1 encoding fallback now propagates its result instead of being silently discarded, an inert lookaround regex in the Paket 1 year extraction was corrected, decimal-comma replacement handles multiple commas, and inspection error messages now include the sheet name.

### Who must update

- Anyone comparing `share_gte6mbps` or `share_gte30mbps` **across 2012/2013 or 2017/2018**: part of the level jump at those years is definitional (tier change), not rollout. Use the new `tier_*` columns to condition on the measurement tier.

## v2.0.0 (2026-07-10)

**Update if you use any earlier version.** This release removes a large block of false zeros, recovers previously dropped municipalities, and adds Berlin and Hamburg. Panel dimensions change from 171,621 rows / 10,992 municipalities to **140,232 rows / 10,994 municipalities**.

### Changed

- **2010-2014 non-reporting zeros removed.** About 6,600 municipalities per year carried exactly 0 across all speed tiers throughout 2010-2014 while averaging 87% baseline coverage in 2008 and 98% in 2015. These were non-reporting municipalities coded as zero in the historical source. The affected 33,138 municipality-years are removed; 2010-2014 now covers roughly 4,400-4,500 reporting municipalities per year (skewed toward larger municipalities). The removed keys are listed in `output/nonreporting_zero_blocks.csv`.
- **The 2015 break is reinterpreted.** 98% of the previously documented jump in unweighted means from 2014 to 2015 (57 percentage points) was these false zeros. Among municipalities observed in both years, the within-municipality baseline jump is 1.2 percentage points, and higher-tier jumps are in line with adjacent-year rollout growth. `method_change_2015` is retained; its main remaining content is the return to near-complete municipality coverage in 2015 (a composition change).
- **Population weighting is now consistent** when historical constituent municipalities are aggregated to 2021 boundaries. This revises some 2005-2007 values in Sachsen-Anhalt, Sachsen, and Thüringen (previously, recovered constituents were missing and weight scales were mixed).

### Added

- **Berlin (11000000) and Hamburg (02000000).** Their absence was a bug in the construction of the Destatis 2021 municipality reference (scientific-notation formatting mangled exactly these two AGS codes), not a property of the source data. Hamburg covers 2005-2021; Berlin covers 2005-2008 and 2015-2021 (its 2010-2014 source rows were non-reporting zeros). 2020-2021 values for both cities are unweighted means across their Bezirke (all underlying values 97-100, so the approximation error is below 1 percentage point).
- **Recovered municipalities via a nearest-year crosswalk fallback.** Some source files carry AGS codes from a different boundary vintage than their year label (for example, Sachsen-Anhalt 2005-2006 files use post-2007-Kreisreform codes). These codes now map through the closest crosswalk year; the mapping is unambiguous for every recovered code. This recovers 1,084 of the previously 1,206 unmapped historical codes. The residual filter removes 9,948 long rows (0.33%) covering 122 codes, mostly Bavarian unincorporated areas and sub-municipal district codes.
- Reproducible generator for the Destatis 2021 reference (`src/main_pipeline/00_build_ags_reference.R`), audit file for zero blocks (`output/nonreporting_zero_blocks.csv`), and verification scripts (`src/auxiliary/verification/verify_ags_recovery.R`, `verify_zero_fix.R`).

### Who must update

- Anyone using **2010-2014 values**: previously ~58% of municipality-years in this window were false zeros; means, event studies, and treatment definitions built on them are biased.
- Anyone using the **2015 break dummy** as a level-shift control: the break is now mostly a composition change, not a measurement level shift.
- Anyone analyzing **city-states**: Berlin and Hamburg are now present; Bremen was present throughout.
- Anyone matching on the **municipality set**: 344 municipality-years were added via recovered codes and city-states, 33,138 were removed as false zeros, and 2005-2007 values changed for some eastern German municipalities.

## v1.0.0 (2026-05)

First versioned release (retroactively tagged; published as the "May 2026 Release").

### Changed relative to the initial June 2025 upload

- 2005-2008 baseline coverage uses the historical `>=0.128 Mbps` DSL measure instead of returning zeros.
- AGS codes are standardized to Destatis 2021 municipality boundaries using population-proportional crosswalks.
- Invalid percentages outside `[0, 100]` are filtered rather than capped.
- Missing speed tiers are preserved as missing values instead of being filled with zero.
- Duplicate AGS-year-technology-speed cells are collapsed before border harmonization.

## Pre-release (2025-06)

Initial best-effort upload. Superseded; do not use.
