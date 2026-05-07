# German Municipal Broadband Availability, 2005-2021

This repository provides a harmonized panel of broadband internet availability for German municipalities. The public file is `output/panel_data_public.csv`.

The data should be used with care. The source files come from three historical Breitbandatlas data packages, reporting methods changed over time, and some historical AGS codes cannot be mapped to official 2021 municipal boundaries. This release is a best-effort harmonization of imperfect source data.

## May 2026 Release

If you downloaded an earlier version, please use the current release. It fixes several issues:

- 2005-2008 baseline coverage now uses the historical `>=0.128 Mbps` DSL measure instead of returning zeros.
- AGS codes are standardized to Destatis 2021 municipality boundaries.
- Invalid percentages outside `[0, 100]` are filtered rather than capped.
- Missing speed tiers are preserved as missing values instead of being filled with zero.
- Duplicate AGS-year-technology-speed cells are collapsed before border harmonization.

## Main Caveats

- There is no 2009 municipality panel in the current source files.
- The baseline measure changes in 2010: `share_broadband_baseline` uses `>=0.128 Mbps` in 2005-2008 and `>=1 Mbps` from 2010 onward.
- A major methodological break occurs in 2015. The public data include `method_change_2015` to flag this year.
- Step 06 filters 68,328 post-deduplicated long rows, 2.22% of the standardization input, because 1,206 historical AGS codes cannot be mapped defensibly to Destatis 2021 boundaries.
- Hamburg and Berlin are not present in the Destatis municipality reference used here.

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
