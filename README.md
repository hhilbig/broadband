# Harmonized historical broadband data for German municipalities

This project cleans, harmonizes, and combines historical broadband availability data for German municipalities ("Gemeinden") from 2005 to 2021, creating a panel dataset suitable for longitudinal analysis.

## Features

- **Municipality-level panel**: The final output is a panel dataset where each row represents a municipality-year observation.
- **Harmonized borders**: All municipal boundaries have been standardized to their 2021 equivalents to ensure consistency over time, accounting for mergers and administrative reforms.

## Data provenance and quality

This dataset is a best-effort attempt to harmonize data from various historical sources provided by the Breitbandatlas. Users should be aware of the following:

- **Limited documentation**: The historical broadband data comes from multiple providers and periods. According to direct correspondence with the Bundesnetzagentur, detailed information on how the original data was compiled, processed, or defined is not available. Some relevant documentation may be found in archived reports, but many specifics remain unclear. The repo contains some reports on the data in [`/docs/breitband_reports/`](./docs/breitband_reports/).
- **Inconsistent sources**: Changes in data providers, reporting standards, and variable definitions likely lead to inconsistencies in the data over time. The longitudinal data set is particularly subject to a structural break between 2014 and 2015.
- **The "2015 jump"**: There is a visible jump in coverage metrics between 2014 and 2015, likely due to a change in data provider and methodology (e.g., switch from *infas* to *Nexiga* for the household base). A dummy variable (`method_change_2015`) is included in the final dataset to help account for this.

## Project resources

- **Data processing pipeline**: For a complete overview of the cleaning and harmonization process, see the detailed documentation: **[Data Processing Pipeline](./docs/data_processing_pipeline.md)**. Note that this documentation describes the full pipeline, including the creation of event-study variables that are not present in the final public dataset.
- **Final dataset**: The final, analysis-ready public dataset can be found here: **[panel_data_public.csv](./output/panel_data_public.csv)**.

## Codebook for final public data

| Variable             | Type      | Description                                                                                                                   | Values                                                                |
| -------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `AGS`                | character | 8-digit official municipality key, standardized to 2021 borders.                                                              | e.g., "01001000"                                                      |
| `year`               | integer   | The year of the observation.                                                                                                  | 2010-2021                                                             |
| `share_gte1mbps`     | double    | Share of households (%) with access to ≥1 Mbps but <6 Mbps.                                                                   | 0-100                                                                 |
| `share_gte6mbps`     | double    | Share of households (%) with access to ≥6 Mbps but <30 Mbps.                                                                  | 0-100                                                                 |
| `share_gte30mbps`    | double    | Share of households (%) with access to ≥30 Mbps.                                                                              | 0-100                                                                 |
| `method_change_2015` | integer   | Dummy variable: `1` if `year` is 2015, otherwise `0`, to flag a methodological break.                                         | `0`, `1`                                                              |

---

## Data source and attribution

The data provided by the Breitbandatlas is free to use for commercial and non-commercial purposes.

When using this data, attribution must be given to the original source: **"Breitbandatlas | Gigabit-Grundbuch (<https://gigabitgrundbuch.bund.de>)"**. Any modifications or interpretations of the data, such as this harmonized dataset, must be clearly marked as such.
