# Unmapped AGS Codes Documentation

## Overview

During AGS standardization, step 06 filters **68,328 post-deduplicated long rows** because their historical AGS codes cannot be mapped to the official Destatis 2021 municipality reference. This is **2.22%** of the post-deduplicated long input to the crosswalk step.

The filtered rows cover **1,206 unique historical AGS codes**. The final public panel contains only AGS codes present in the Destatis 2021 reference.

## Root Cause

The broadband source data, especially Paket 1 in 2005-2008, uses AGS coding schemes that differ from official Destatis records for some regions. Sachsen-Anhalt is the largest case.

### Example: Sachsen-Anhalt

| Source | AGS Pattern | District Codes |
|--------|-------------|----------------|
| Broadband data | `15081005`, `15081010` | 081, 082, 083... |
| Destatis crosswalk | `15101000`, `15151002` | 101, 151, 152... |

There is no reliable overlap between these two coding systems for many affected Sachsen-Anhalt municipalities.

## Mapping Attempt

Step 06 uses three mapping sources:

1. The official Destatis 2005-2020 to 2021 population-proportional crosswalks.
2. Direct 1:1 mappings only when the source AGS already exists in the Destatis 2021 reference.
3. Deterministic reform-chain mappings from `data/gebietsreformen/combined_reform_mappings.rds`.

The current run maps **525 unique historical AGS codes** through deterministic reform chains. These are saved in `output/supplementary_ags_crosswalk.rds`. Ambiguous reform paths, cycles, and codes with no path to a 2021 reference AGS are not forced into a mapping.

## Remaining Unmapped Codes

The remaining **1,206 unique historical AGS codes** are saved in `output/unmapped_ags_for_review.csv`.

### By State

| State code | Unique AGS |
|------------|------------|
| 15 | 688 |
| 16 | 239 |
| 03 | 80 |
| 09 | 63 |
| 13 | 37 |
| 07 | 29 |
| 14 | 23 |
| 11 | 12 |
| 05 | 9 |
| 02 | 7 |
| 01 | 6 |
| 06 | 6 |
| 04 | 5 |
| 10 | 1 |
| 12 | 1 |

## Decision: Filter Out

These unmapped AGS codes are filtered out in `06_standardize_ags_to_2021.R` because:

1. They cannot be linked defensibly to official 2021 municipality boundaries.
2. Keeping them would reintroduce non-reference AGS codes into the public panel.
3. The affected rows are 2.22% of the post-deduplicated long input to the standardization step.
4. Most affected early-year codes are in periods with limited broadband tier detail.

## Files

- Filtered AGS list: `output/unmapped_ags_for_review.csv`
- Reform-chain mapping details: `output/missing_ags_to_2021_mapping.rds`
- Supplementary crosswalk: `output/supplementary_ags_crosswalk.rds`
- Reform mappings source: `data/gebietsreformen/combined_reform_mappings.rds`

## Future Improvements

If additional historical municipality-name or provider-code crosswalks become available, especially for Sachsen-Anhalt, some currently unmapped AGS codes could potentially be reconciled through name-based or provider-code matching.
