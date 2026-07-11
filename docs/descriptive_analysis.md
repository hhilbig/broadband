# Descriptive analysis of harmonized broadband data

This document provides a brief descriptive overview of the harmonized German municipal broadband panel dataset (2005-2021).

Last updated: July 11, 2026 (v2.1.0). Plots were regenerated from `output/panel_data_public.csv`.

## Data quality notes

### Use with caution

This dataset has known limitations that users should be aware of:

1. **Methodological breaks**: the 2010 baseline definition change, tier changes at 2013 and 2018, and the 2015 provider change affect comparability across years (see below)
2. **Missing years and tiers**: 2009 is absent from the municipality panel; 2005-2008 only report the historical baseline tier; the 1, 6, and 30 Mbps tiers are only reported from 2018, so before then the higher-tier share columns are measured at stricter tiers (recorded in the `tier_*` columns)
3. **2010-2014 covers only reporting municipalities** (~4,400-4,500 per year, skewed toward larger municipalities); non-reporting municipalities coded as zero were removed in v2.0.0
4. **Filtered observations**: Step 06 filters 9,948 post-deduplicated long rows (0.33%) covering 122 historical AGS codes that cannot be mapped to Destatis 2021 boundaries (see [unmapped_ags_documentation.md](unmapped_ags_documentation.md) for details)

### If using prior data

If you previously used this dataset, please re-download and see [CHANGELOG.md](../CHANGELOG.md). Highlights: v2.0.0 removed ~33,000 false-zero municipality-years in 2010-2014, added Berlin and Hamburg, and recovered previously unmapped municipalities; v2.1.0 added the `tier_*` columns that record the speed tier behind each share value and corrected codebook errors.

## Discontinuous changes in the data

The panel data is constructed from historical sources with changing methodologies and changing speed-tier menus. This results in several breaks in the time series that users must be aware of.

### The 2009/2010 break

To create a continuous series for basic internet availability, the `share_broadband_baseline` variable was constructed from different underlying sources:

- **For 2005-2008**: The variable is based on historical DSL availability data (`speed_mbps_gte = 0.128`, representing >=0.128 Mbps).
- **For 2009**: No municipality panel is available in the current input files.
- **From 2010 onwards**: The variable is based on the lowest reported tier: >=2 Mbps in 2010-2017 and >=1 Mbps from 2018 (see `tier_baseline`). Since these imply >=0.128 Mbps, they are lower bounds on basic access.

**The consequence is a discontinuity in the data where the definition of the baseline metric changes.** In the current panel, this appears as a drop between 2008 and 2010, when the source switches from historical DSL availability to the stricter tier. This is distinct from organic change in broadband availability.

### The 2013 and 2018 tier breaks

The share columns take the lowest reported tier at or above their named threshold, and the reported tiers change over time. `share_gte6mbps` is measured at >=50 Mbps in 2010-2012 (where it is identical to `share_gte30mbps` by construction), at >=16 Mbps in 2013-2017, and at >=6 Mbps from 2018. `share_gte30mbps` is measured at >=50 Mbps through 2017 and at >=30 Mbps from 2018. `share_gte1mbps` and the baseline are measured at >=2 Mbps through 2017 and >=1 Mbps from 2018. Part of the level jumps at 2013 and 2018 is therefore definitional, not rollout. The per-observation `tier_*` columns identify the measurement tier; analyses spanning these years should condition on them or restrict to constant-tier windows.

### The 2015 break

2015 marks a change in the primary data provider and reporting standards. Since the removal of the 2010-2014 false zeros in v2.0.0, the remaining content of this break is mostly a composition change: the panel returns to near-complete municipality coverage in 2015, while the within-municipality baseline jump among continuous reporters is only 1.2 percentage points. The `method_change_2015` dummy variable is included in the dataset to allow researchers to control for this event.

---

## Descriptive plots

### Average annual coverage

This plot shows the mean coverage for the baseline metric alongside higher speed tiers. The dashed lines mark the **2010 definition break**, the **2013 and 2018 tier breaks**, and the **2015 method break**. The sharp rises in the >=6 Mbps series at 2013 and 2018 sit exactly on the tier breaks and are partly definitional.

![Average Annual Coverage](../output/descriptives/average_annual_coverage_plot.png)

### Year-over-year change in coverage

This plot highlights the magnitude of the year-on-year changes in unweighted means. Changes at the dashed break lines mix definitional shifts and sample-composition changes with organic rollout; changes elsewhere reflect rollout among reporting municipalities.

![Year-over-Year Change in Coverage](../output/descriptives/yoy_coverage_change_plot.png)

### Distribution of coverage levels

This set of histograms shows the distribution of coverage values. The `share_broadband_baseline` is heavily skewed towards 100%, indicating that most municipalities achieved full basic coverage relatively early. In contrast, higher speed tiers show more variation and a larger concentration near 0%.

![Distribution of Coverage Levels](../output/descriptives/coverage_distribution_plot.png)
