# Unmapped AGS Codes Documentation

## Overview

During the data processing pipeline, **1,388 unique AGS codes** (affecting ~3.9% of panel rows) were identified that do not exist in the official Destatis 2021 municipality reference list. These records are **filtered out** in step 07 of the pipeline.

## Root Cause

The broadband source data (particularly Paket 1, years 2005-2008) uses an **AGS coding scheme that differs from official Destatis records** for certain regions, especially Sachsen-Anhalt.

### Example: Sachsen-Anhalt

| Source | AGS Pattern | District Codes |
|--------|-------------|----------------|
| Broadband data | `15081005`, `15081010` | 081, 082, 083... |
| Destatis crosswalk | `15101000`, `15151002` | 101, 151, 152... |

There is **zero overlap** between these two coding systems for Sachsen-Anhalt municipalities.

## Why Matching is Impossible

1. **Different AGS numbering schemes**: The broadband data provider used a non-standard or preliminary AGS system
2. **Missing municipality names**: Only 168 of 995 Sachsen-Anhalt entries in the source data have municipality names (83% are `NA`)
3. **No conversion table exists**: We searched all available Gebietsreformen files (1969-2024) and found no mapping between these schemes

## Affected Data

### By Year
| Year | Rows Filtered | Unique AGS |
|------|---------------|------------|
| 2005 | 896 | 896 |
| 2006 | 888 | 888 |
| 2007 | 83 | 83 |
| 2008 | 2 | 2 |
| 2018 | 171 | 171 |
| 2019 | 469 | 469 |
| 2020 | 450 | 450 |
| 2021 | 461 | 461 |

### By State
| State | Code | Count | % of Filtered |
|-------|------|-------|---------------|
| Sachsen-Anhalt | 15 | 688 | 49.6% |
| Thüringen | 16 | 243 | 17.5% |
| Sachsen | 14 | 85 | 6.1% |
| Niedersachsen | 03 | 84 | 6.1% |
| Other states | various | 288 | 20.7% |

## Resolution Attempts

### Successfully Mapped (609 AGS)
Using the Gebietsreformen files (2006-2024), we were able to chain municipality reform mappings for 609 AGS codes. These are applied during the AGS standardization step (06).

### Could Not Map (779 AGS)
The remaining 779 AGS codes (primarily Sachsen-Anhalt) cannot be mapped due to the incompatible coding schemes described above.

## Decision: Filter Out

These unmapped AGS codes are **filtered out** in `07_create_treatment_variables.R` because:

1. They cannot be linked to official 2021 municipality boundaries
2. They would cause issues when merging with other datasets using official AGS codes
3. The affected data represents only ~3.9% of the total panel
4. Most affected years (2005-2006) have limited broadband variation anyway (early DSL era)

## Impact on Analysis

- **Final panel**: Contains only AGS codes that exist in official Destatis 2021 records
- **Data loss**: ~3.9% of observations filtered out
- **Geographic coverage**: Some Sachsen-Anhalt municipalities in 2005-2006 are not represented
- **Temporal coverage**: 2005-2008 data for affected municipalities is missing

## Files

- Filtered AGS list: `output/unmapped_ags_for_review.csv`
- Supplementary crosswalk (for 609 mapped): `output/supplementary_ags_crosswalk.rds`
- Reform mappings source: `data/gebietsreformen/combined_reform_mappings.rds`

## Future Improvements

If additional data sources become available (e.g., historical municipality name lists for Sachsen-Anhalt), the unmapped AGS codes could potentially be reconciled through name-based matching.
