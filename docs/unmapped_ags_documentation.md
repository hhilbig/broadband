# Unmapped AGS Codes Documentation

## Overview

During AGS standardization, step 06 filters **9,726 post-deduplicated long rows** because their historical AGS codes cannot be mapped to the official Destatis 2021 municipality reference. This is **0.32%** of the post-deduplicated long input to the crosswalk step.

The filtered rows cover **121 unique historical AGS codes**. The final public panel contains only AGS codes present in the Destatis 2021 reference (10,994 municipalities, generated reproducibly by `src/main_pipeline/00_build_ags_reference.R`).

Before the July 2026 v2.0.0 update, 68,328 rows (2.22%) covering 1,206 codes were filtered; the nearest-year crosswalk fallback recovered 1,084 of those codes (v2.0.0 residual: 9,948 rows / 122 codes). v3.0.0 recovered one further code (NI `03156501`, see below) via the relaxed reform fallback, leaving 121.

## Root Cause of the Former Gap

The broadband source data uses AGS coding schemes from a different boundary vintage than the year label of the delivery. Sachsen-Anhalt was the largest case: the 2005-2006 files carry post-2007-Kreisreform district codes (15081-15091), which do not exist in the 2005/2006 Destatis crosswalk sheets. Similar year-vintage mismatches affected Thüringen, Niedersachsen, and other states in 2018-2021 (dissolved codes lingering in newer deliveries).

Because the crosswalk join is keyed on the pair (AGS, year), these codes found no match in their own year's sheet even though they have an unambiguous mapping in another sheet.

## Mapping Sources

Step 06 uses five mapping sources, applied in this order of precedence:

1. The official Destatis 2005-2020 to 2021 population-proportional crosswalks, joined on (AGS, year).
2. **Nearest-year crosswalk fallback**: for codes absent from their own year's sheet but present in another sheet, the mapping from the sheet closest to the data year is used (ties broken toward the later sheet). For every recovered code, the set of 2021 targets is identical across all sheets in which the code appears, so the donor-year choice does not affect the target. Year-2021 rows with valid 2021 codes keep their identity mapping (the data is already on 2021 boundaries) with donor-sheet population weights. Details per mapping: `output/nearest_year_fallback_mapping.rds`.
3. **Bezirk-to-city aggregation (Berlin/Hamburg, 2020-2021 only)**: the source reports the two city-states only at Bezirk level in 2020-2021. The 7 Hamburg and 12 Berlin Bezirk codes map fully into their city code with equal weights (unweighted mean; the source contains no Bezirk household weights, and all observed Bezirk values lie in 97-100).
4. Direct 1:1 mappings when the source AGS already exists in the Destatis 2021 reference and appears in no crosswalk sheet (mainly new 2021 codes).
5. Deterministic reform-chain mappings from `data/gebietsreformen/combined_reform_mappings.rds`, applied only for reforms at or after the data year. Ambiguous reform paths, cycles, and codes with no path to a 2021 reference AGS are not forced into a mapping.
6. **Relaxed reform-chain fallback (v3.0.0)**: for codes still unmapped after (5), a reform predating the data year is applied when the legacy code carries actual coverage (not all-zero) and resolves unambiguously to a valid 2021 reference unit. This recovers late-arriving legacy codes such as NI `03156501` -> `03159501`. All-zero legacy codes are excluded so that an unpopulated gemeindefreies Gebiet is not folded into a populated successor.

## Remaining Unmapped Codes

The remaining **121 unique historical AGS codes** (9,726 rows) are saved in `output/unmapped_ags_for_review.csv` (with affected years and row counts per code). The by-state table below reflects the v2.1.0 breakdown; v3.0.0 removed the Niedersachsen row (recovered).

### By State

| State code | Unique AGS | Rows | Assessment |
|------------|------------|------|------------|
| 09 Bayern | 63 | 5,241 | Gemeindefreie Gebiete (unincorporated areas, pattern `xxxxx444`); no 2021 municipality equivalent, correctly excluded |
| 07 Rheinland-Pfalz | 24 | 2,016 | Non-municipal codes (`07932*`, `07935*`), all-tier-zero in the 2018-2019 source, absent from the Destatis 2021 municipality reference with no reform path; correctly excluded (see case-review note below) |
| 11 Berlin | 12 | 348 | 2019 Bezirk rows; city-level 2019 data already covers Berlin, so these are deliberately not aggregated |
| 05 Nordrhein-Westfalen | 9 | 1,179 | Köln Stadtbezirke (`05315001-05315009`); parent city already covered, mapping skipped to avoid blending sub-municipal with city values |
| 02 Hamburg | 7 | 203 | 2019 Bezirk rows; city-level 2019 data already covers Hamburg |
| 04 Bremen | 5 | 655 | Bremen Stadtteile (`04011001-04011005`); parent city already covered, mapping skipped |
| 10 Saarland | 1 | 84 | Non-municipal code (`10942115`), all-tier-zero in the 2018-2019 source, absent from the 2021 reference with no reform path; correctly excluded |

(The Niedersachsen code `03156501` = "Harz, gemeindefreies Gebiet" that appeared here in v2.1.0 is **recovered in v3.0.0** and no longer in the unmapped set; see below.)

### Case-review outcome (2026-07-12)

The 26 codes previously marked "case review pending" (24 Rheinland-Pfalz, 1 Niedersachsen, 1 Saarland) were reviewed against the Destatis 2021 reference, the reform mappings, and the raw source:

- **25 codes correctly excluded** (24 RP + 1 SL). All carry exactly zero across every speed tier in both 2018 and 2019, are absent from the Destatis 2021 municipality reference, and have no reform mapping to any 2021 code. They share the non-standard Regierungsbezirk digit `9` (`07-9-32`, `07-9-35`, `10-9-42`) that the Destatis municipality scheme does not use for these as municipalities, consistent with non-municipal/special territories in the source delivery. Excluding them loses only zeros.
- **1 code genuinely recoverable, now recovered in v3.0.0** (NI `03156501`). The source labels it "Gemeindefreies Gebiet, Harz (Landkreis Osterode)"; it uses the pre-2016 Osterode Kreis code (`03156`) that the 2016 Kreis reform folded into Landkreis Göttingen (`03159`). It carries real coverage (baseline 100% in 2018-2020) and maps unambiguously to `03159501` ("Harz (Landkreis Göttingen), gemfr. Geb."), which is in the 2021 reference. The constrained reform pass missed it because `resolve_reform_chain` only applied reforms with `reform_year >= source_year`, and the reform (2016) predates the data year (2018-2021). **v3.0.0 adds a relaxed reform fallback** (mapping source 6 below) that applies an earlier reform when the legacy code carries actual coverage and maps unambiguously to a valid 2021 reference unit. This recovers `03159501` for 2019-2020 and revises its 2018 value (both source deliveries now aggregate); its 2021 source value is a genuine all-zero dropout and is removed by the trailing-zero rule.

## Decision: Filter the Residual

The 121 residual codes are filtered in `06_standardize_ags_to_2021.R` because:

1. Most are not municipalities (unincorporated areas, sub-municipal districts).
2. Sub-municipal codes whose parent city already has data would blend duplicate information into existing values.
3. The affected rows are 0.32% of the post-deduplicated long input (row counts here reflect the pipeline state after the 2010-2014 non-reporting zero fix, which runs before the crosswalk join).

## Files

- Filtered AGS list (with years and row counts): `output/unmapped_ags_for_review.csv`
- Nearest-year fallback mapping details: `output/nearest_year_fallback_mapping.rds`
- Reform-chain mapping details: `output/missing_ags_to_2021_mapping.rds`
- Supplementary crosswalk: `output/supplementary_ags_crosswalk.rds`
- Reform mappings source: `data/gebietsreformen/combined_reform_mappings.rds`
- Recovery diagnostics: `src/auxiliary/verification/verify_ags_recovery.R`

## Future Improvements

- NI `03156501` -> `03159501` was recovered in v3.0.0 via the relaxed reform fallback. The other 25 case-review codes are confirmed correctly excluded.
- If external Bezirk household or population data are added, the 2020-2021 Berlin/Hamburg unweighted Bezirk aggregation can be upgraded to a weighted mean.
