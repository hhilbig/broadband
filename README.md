# German Municipal Broadband Availability, 2005-2021

**Current version: v2.0.0 (July 2026).** If you downloaded an earlier version, please update: v2.0.0 removes a large block of false zeros in 2010-2014, adds Berlin and Hamburg, and recovers previously dropped municipalities. See [CHANGELOG.md](CHANGELOG.md) for what changed between versions and who is affected.

This repository provides a harmonized panel of broadband internet availability for German municipalities. The public file is `output/panel_data_public.csv`.

The data should be used with care. The source files come from three historical Breitbandatlas data packages, reporting methods changed over time, and some historical AGS codes cannot be mapped to official 2021 municipal boundaries. This release is a best-effort harmonization of imperfect source data.

## Versioning

Releases follow a semantic scheme: major versions change existing values or observations, minor versions add data or variables, patch versions change documentation only. Each version is a git tag and a [GitHub Release](https://github.com/hhilbig/broadband/releases) with the panel CSV attached, and the current version is recorded in the `VERSION` file. All changes are documented in [CHANGELOG.md](CHANGELOG.md).

## v2.0.0 (July 2026)

This update recovers most of the data previously dropped during AGS standardization and removes a large block of false zeros:

- **Non-reporting zeros removed from 2010-2014.** About 6,600 municipalities per year carried exactly 0 across all speed tiers throughout 2010-2014 while averaging 87% baseline coverage in 2008 and 98% in 2015. These were non-reporting municipalities coded as zero in the historical source, not true zeros. The affected 33,138 municipality-years are removed; 2010-2014 now covers roughly 4,400-4,500 reporting municipalities per year. This resolves most of the previously documented 2015 break: the unweighted mean jump from 2014 to 2015 was 57 percentage points before the fix, while the within-municipality jump among continuous reporters is 1.2 percentage points.
- A nearest-year crosswalk fallback maps historical AGS codes delivered under a different boundary vintage than their year label (for example, Sachsen-Anhalt 2005-2006 files carry post-2007-Kreisreform codes). This recovers 1,084 of the previously unmapped 1,206 codes; the residual filter now removes 9,948 long rows (0.33% of the standardization input) covering 122 codes.
- Berlin and Hamburg are now included. Their absence was a bug in the construction of the Destatis 2021 reference (their AGS codes were mangled by scientific-notation formatting), not a property of the source data. Hamburg has city-level data for 2005-2021; Berlin for 2005-2008 and 2015-2021 (its 2010-2014 source rows were non-reporting zeros). Both cities' 2020-2021 values are aggregated from Bezirk-level data (see caveats).
- Municipality counts rise to 10,994 Destatis 2021 AGS codes; the panel has 140,232 municipality-year rows.
- Population weights are now applied consistently when historical constituents are aggregated to 2021 boundaries, which revises some published 2005-2007 values in Sachsen-Anhalt, Sachsen, and Thüringen (recovered constituent municipalities are now included in the population-weighted means).

## v1.0.0 (May 2026)

Relative to the initial June 2025 upload, this release fixed several issues:

- 2005-2008 baseline coverage now uses the historical `>=0.128 Mbps` DSL measure instead of returning zeros.
- AGS codes are standardized to Destatis 2021 municipality boundaries.
- Invalid percentages outside `[0, 100]` are filtered rather than capped.
- Missing speed tiers are preserved as missing values instead of being filled with zero.
- Duplicate AGS-year-technology-speed cells are collapsed before border harmonization.

## Main Caveats

- There is no 2009 municipality panel in the current source files.
- The baseline measure changes in 2010: `share_broadband_baseline` uses `>=0.128 Mbps` in 2005-2008 and `>=1 Mbps` from 2010 onward.
- **2010-2014 covers only reporting municipalities** (roughly 4,400-4,500 per year). Municipality-years with exactly 0 across all speed tiers in this window were non-reporting coded as zero in the source and have been removed (see `output/nonreporting_zero_blocks.csv` for the full list). Reporters skew toward larger municipalities, so unweighted means over 2010-2014 describe a selected sample.
- The 2015 provider change (`method_change_2015`) remains flagged, but after the removal of false zeros the residual break is small: the within-municipality baseline jump from 2014 to 2015 is 1.2 percentage points, and higher-tier jumps are in line with adjacent-year rollout growth. The main effect of 2015 is the return to near-complete municipality coverage, i.e., a composition change.
- About 700 all-tier-zero municipality-years remain in 2015-2021. Most are persistently zero small municipalities where a genuine zero is plausible; they are retained and listed in `output/nonreporting_zero_blocks.csv` for review.
- Step 06 filters 9,948 post-deduplicated long rows, 0.33% of the standardization input, because 122 historical AGS codes cannot be mapped defensibly to Destatis 2021 boundaries (mostly Bavarian unincorporated areas and sub-municipal district codes).
- Berlin and Hamburg values for 2020-2021 are unweighted means across their 19 Bezirke, because the source reports only Bezirk-level coverage in those years and contains no Bezirk household weights. All underlying Bezirk values lie between 97 and 100, so the approximation error is below 1 percentage point.

Details on filtered AGS codes are in `docs/unmapped_ags_documentation.md`.

## Output Files

- `output/panel_data_public.csv`: public municipality-year panel.
- `output/panel_data_with_treatment.csv`: internal version with treatment indicators and event-time variables.
- `docs/data_processing_pipeline.md`: processing details and validation notes.
- `output/average_annual_coverage_plot.png` and `output/large_yoy_changes_plot.png`: diagnostic plots.
- `output/county_gte30_coverage_map_2021.png`: county-level 2021 map of `>=30 Mbps` coverage, aggregating municipality values with population weights.

## Public Data Codebook

| Variable | Type | Description |
| --- | --- | --- |
| `AGS` | character | 8-digit official municipality key, standardized to 2021 boundaries. |
| `year` | integer | Observation year. The panel covers 2005-2021, excluding 2009. |
| `share_broadband_baseline` | double | Share of households with access to basic broadband. Uses `>=0.128 Mbps` in 2005-2008 and `>=1 Mbps` from 2010 onward. |
| `share_gte1mbps` | double | Share of households with access to `>=1 Mbps`; missing before this tier is reported. |
| `share_gte6mbps` | double | Share of households with access to `>=6 Mbps`; missing before this tier is reported. |
| `share_gte30mbps` | double | Share of households with access to `>=30 Mbps`; missing before this tier is reported. |
| `method_change_2015` | integer | Indicator for the 2015 methodological break. |

All share variables are percentages on the 0-100 scale.

## Attribution

The original data come from the Breitbandatlas / Gigabit-Grundbuch. When using this harmonized dataset, cite the original source and make clear that the data have been modified and harmonized.

Original source: Breitbandatlas | Gigabit-Grundbuch (<https://gigabitgrundbuch.bund.de>)
