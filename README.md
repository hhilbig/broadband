# Harmonized historical broadband data for German municipalities

This project cleans, harmonizes, and combines historical broadband availability data for German municipalities ("Gemeinden") from 2005 to 2021. There are some data limitations, which are listed below.

## Important: Use the Most Recent Data

If you previously downloaded this dataset, please re-download. The February 2026 version fixes several issues:

- **Fixed 2005-2008 baseline coverage values** (previously showing 0%, now correctly ~82% mean DSL coverage)
- **Validated all AGS codes** against official Destatis 2021 reference
- **Removed invalid values** outside [0, 100] range

## Characteristics of the data

- **Municipality-level panel**: The final output is a panel dataset where each row represents a municipality-year observation.
- **Harmonized borders**: All municipal boundaries have been standardized to their 2021 equivalents by accounting for mergers and administrative reforms. I use the official BBSR crosswalk files for this.

## Data provenance and quality

This dataset is a best-effort attempt to harmonize data from various historical sources provided by the Breitbandatlas. Users should be aware of the following:

- **Limited documentation**: The historical broadband data comes from multiple providers and periods. Based on correspondence with the Bundesnetzagentur, detailed information on how the raw data was originally compiled by providers is often lacking.
- **Methodological break in 2015**: A significant change in the data provider and reporting standards in 2015 led to a structural break in the time series. This is visible as a large, discontinuous jump in coverage levels for that year. The `method_change_2015` dummy is included in the dataset to help account for this.

## Data quality caveats

### Known issues (use with caution)

| Issue | Severity | Years Affected | Mitigation |
|-------|----------|----------------|------------|
| 2015 methodological break | HIGH | 2015 | Use `method_change_2015` dummy variable |
| 2009-2017 data gap | MEDIUM | 2009-2017 | Panel is sparse for these years |
| Missing city-states | LOW | All | Hamburg (02), Berlin (11) not in data |
| Sachsen-Anhalt 2005-2006 | LOW | 2005-2006 | ~688 AGS could not be mapped to 2021 boundaries |

For detailed information on filtered AGS codes, see [unmapped_ags_documentation.md](./docs/unmapped_ags_documentation.md).

### Historical issues (now fixed)

- 2005-2008 baseline values showing 0% (fixed: now shows DSL coverage ~82%)
- Values >100% in some observations (fixed: capped to [0,100])
- Duplicate rows in intermediate files (fixed: removed via `distinct()`)

## Project resources

- **Data processing pipeline**: The full documentation of the data cleaning and harmonization process can be found here: **[data_processing_pipeline.md](./docs/data_processing_pipeline.md)**.
- **Descriptive analysis**: A summary of the data's key features, including the structural breaks, is available in [this PDF document](./docs/descriptive_analysis.pdf).
- **Final dataset**: The final dataset can be found here: **[panel_data_public.csv](./output/panel_data_public.csv)**.

## Codebook for the public data file

The final public dataset (`output/panel_data_public.csv`) has the following structure:

| Variable                   | Type      | Description                                                                                                                               | Values                                                                |
| -------------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `AGS`                      | character | 8-digit official municipality key, standardized to 2021 borders.                                                                          | e.g., "01001000"                                                      |
| `year`                     | integer   | The year of the observation.                                                                                                              | 2005-2021                                                             |
| `share_broadband_baseline` | double    | Share of households (%) with access to basic broadband. This is a composite variable: **for 2005-2008** it uses historical DSL availability (>=0.128 Mbps, `speed_mbps_gte = 0`); **for 2009** it blends historical and modern data; **from 2010 onwards** it is based on >=1 Mbps data. This creates a discontinuous change around 2010. | 0-100                                                                 |
| `share_gte1mbps`           | double    | Share of households (%) with access to **≥1 Mbps**. Becomes consistently available from 2010.                                             | 0-100                                                                 |
| `share_gte6mbps`           | double    | Share of households (%) with access to **≥6 Mbps**.                                                                                       | 0-100                                                                 |
| `share_gte30mbps`          | double    | Share of households (%) with access to **≥30 Mbps**.                                                                                      | 0-100                                                                 |
| `method_change_2015`       | integer   | Dummy variable: `1` if `year` is 2015, otherwise `0`, to flag a methodological break.                                                     | `0`, `1`                                                              |

---

## Data source and attribution

The data provided by the Breitbandatlas is free to use for commercial and non-commercial purposes.

When using this data, attribution must be given to the original source: **"Breitbandatlas | Gigabit-Grundbuch (<https://gigabitgrundbuch.bund.de>)"**. Any modifications or interpretations of the data, such as this harmonized dataset, must be clearly marked as such.
