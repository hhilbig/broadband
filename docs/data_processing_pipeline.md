# Data processing pipeline for Breitbandatlas historical data

## Recent updates (July 2026)

This version recovers most data previously dropped during AGS standardization:

1. **Reproducible AGS reference (new step 00)**: `00_build_ags_reference.R` generates `data/ags_reference/destatis_ags_2021.rds` (10,994 municipalities) from the 2020 sheet of the Destatis Umsteigeschlüssel workbook. The previous committed binary lacked Berlin and Hamburg because their round numeric AGS codes were rendered in scientific notation and mangled during extraction; both city-states are now in the panel.
2. **Nearest-year crosswalk fallback**: step 06 maps historical AGS codes that appear in a different year's crosswalk sheet than the data year label (e.g., Sachsen-Anhalt 2005-2006 files carrying post-2007-Kreisreform codes). This recovers 1,084 of the previously 1,206 unmapped codes; the residual filter drops 9,948 rows (0.33%) covering 122 codes.
3. **Non-reporting zero fix**: municipality-years with exactly 0 across all speed tiers in 2010-2014 (33,138 municipality-years, 79,432 long rows) are removed as non-reporting; see the "Known limitations" section for details and consequences.
4. **Berlin/Hamburg 2020-2021 via Bezirke**: the two city-states are reported only at Bezirk level in 2020-2021; step 06 aggregates the 7+12 Bezirk codes to the city codes with an unweighted mean (no Bezirk household weights exist in the source; all Bezirk values lie in 97-100).
5. **Consistent population weighting**: recovered constituents enter the population-weighted aggregation with donor-sheet population weights, which revises some 2005-2007 values in Sachsen-Anhalt, Sachsen, and Thüringen.

## Recent updates (May 2026)

This version fixes several data quality issues:

1. **2005-2008 Baseline Fix**: Historical DSL coverage (`speed_mbps_gte = 0.128`) is correctly included in `share_broadband_baseline`. Previously these years showed 0% coverage.
2. **AGS Validation**: All output AGS codes are validated against the Destatis 2021 reference. Step 06 filters unmapped historical AGS codes (see the July 2026 update for current counts).
3. **Value Bounds**: Coverage values outside [0, 100] are filtered before aggregation. Standardized outputs fail validation if out-of-bounds values remain; they are not capped.
4. **Deduplication**: Duplicate AGS-year-technology-speed cells are collapsed with `max(value)` before AGS standardization so overlapping source files do not inflate percentages.

## Introduction

This document details the data processing pipeline created to clean, standardize, and combine historical broadband availability data for German municipalities ("Gemeinden"). The pipeline produces a long-format intermediate dataset with municipality-year-technology-speed observations and a final public wide panel with one row per municipality-year.

The data originates from three main "Pakets" (bundles) provided by the Bundesnetzagentur, containing historical data from previous Breitbandatlas operators. The focus of this processing is on data relevant to private households ("privat").

## Overall approach

The core strategy involves:

1. **Paket-Specific Processing**: Developing separate R scripts to handle the unique formats and challenges within each data Paket (`Paket_1`, `Paket_2`, `Paket_3`).
2. **Helper Functions**: Creating a suite of reusable R functions for common tasks like year extraction, AGS (Amtlicher Gemeindeschlüssel - official municipality key) identification, and parsing broadband variable names.
3. **Data Harmonization**: Transforming varied column names and data structures into a consistent schema across all Pakets. This includes extracting technology type, minimum speed (>= Mbit/s), and the reported value.
4. **Filtering**: Focusing on data for "privat" (private households) and excluding "gewerbe" (business) and "mobilfunk" (mobile telecommunications) where specified.
5. **Verification**: Implementing checks within scripts and separate verification scripts to ensure data integrity (e.g., correct AGS format, consistent year assignment).
6. **Combination**: Merging the processed data from individual Pakets into a comprehensive long-format intermediate dataset used to build the public panel.

All R scripts utilize libraries from the `tidyverse` for data manipulation, `readxl` for Excel files, `stringr` for string operations, and `here` for path management.

## Key helper functions

Several helper functions were developed and refined throughout the project. These are typically defined within each processing script or sourced if they were in a common file.

### Year extraction

- `extract_year_from_filename(filename)`: Attempts to extract a 4-digit year (e.g., 2005-2024) from a filename using regex. Includes fallbacks for formats like "ende18" (interpreted as 2018).
- `extract_year_for_sheet(sheet_name, filename_year)`: Used primarily in Paket 1 and 2 for Excel files. It first tries to extract the year from the sheet name (e.g., patterns like `^(\d{4})_` for "2019_SheetName", or specific keywords like "ende JJ"). If unsuccessful, it falls back to the year extracted from the filename.

### AGS column identification

- `find_ags_column_name(col_names)`: Identifies the AGS column in a dataset by checking a list of common patterns (e.g., "ags", "gemeindeschluessel", "gem", "kennziffer") against the column names (case-insensitive). Returns the original column name.

### Data category determination

- `determine_data_category(filename)`: Determines if a file pertains to "privat", "gewerbe", "mobilfunk", or "alle" based on keywords in the filename.

### Broadband variable parsing

- `parse_broadband_variable(variable_name)`: This is a crucial and complex function responsible for interpreting the meaning of broadband-related column headers. It evolved significantly to handle various naming conventions across Pakets.
  - **Input**: A column name string.
  - **Output**: A tibble with `technology_group`, `speed_mbps_gte`, and potentially `year_from_variable`.
  - **Key Patterns Handled**:
    1. **Modern Names (e.g., Paket 3, newer Paket 2)**: `"Technology Name >= 100 Mbit/s"` or `"Technology Name  100 Mbit/s"`. Extracts technology and speed.
    2. **Historical `verf_` prefixed names (Paket 1)**: `"verf_100_50"` (leitungsgebunden, >= 50 Mbit/s), `"verf_200_30"` (drahtlos), `"verf_300_10"` (alle). Maps `verf_` codes to technology groups and extracts speed.
    3. **Historical specific tech names (Paket 1)**: `"DSL_16"`, `"CATV_400"`. Extracts technology and speed.
    4. **`_gtoe_` names (Paket 2)**: `"dsl_gtoe_16_mbits"`. Interprets "gtoe" as "greater than or equal to".
    5. **Prefixed tech names (Paket 2)**: `"priv_dsl_100"`, `"gew_lg_tech_50"`. Extracts prefix (user type), technology, and speed.
    6. **Household/Non-speed (Paket 2)**: `"HH_ges"` (total households), `"HH_DSL_16"`, `"GemFl"` (municipality area). Identifies these as distinct categories, often with `NA` speed.
    7. **Year in variable (Paket 1, Paket 2)**: If a variable name ends with `_YYYY` (e.g., `verf_alle_tech_100_2010`), this year is extracted and takes precedence.
  - If no pattern matches, the original variable name is typically returned as the `technology_group` with `NA` speed.

### Interpretation of common `technology_group` values

The `parse_broadband_variable` function generates various `technology_group` strings. Here's an interpretation of common ones encountered:

- **`Leitungsg. Technologien (gtoe)` / `leitungsg. Technologien`**: Refers to "fixed-line technologies" (literally "line-bound technologies"). The "(gtoe)" likely indicates "greater than or equal to", often seen in newer Paket 2/3 data where the speed is explicitly part of the original column name in a format like "Leitungsg. Technologien >= X Mbit/s". The version without "(gtoe)" might come from older data or different naming schemes.
- **`DSL (gtoe)` / `DSL` / `DSL (hist)`**: Refers to Digital Subscriber Line technology. "(gtoe)" has the same meaning as above. "(hist)" indicates it was parsed from a historical naming convention (e.g., `DSL_16` from Paket 1).
- **`CATV (gtoe)` / `CATV` / `CATV (hist)`**: Refers to cable television network based broadband. "(gtoe)" and "(hist)" as above.
- **`FTTH/B (gtoe)` / `FTTH/B` / `FTTH/B (hist)`**: Refers to Fiber to the Home / Fiber to the Building. "(gtoe)" and "(hist)" as above.
- **`HFC (hist)`**: Hybrid Fiber Coaxial, parsed from historical data in Paket 2.
- **`alle Technologien (hist)` / `alle Technologien`**: Refers to an aggregation of all available technologies (fixed-line and potentially wireless, depending on source context). "(hist)" denotes parsing from older formats (e.g. `verf_300_X`).
- **`leitungsg. Technologien (hist)`**: Fixed-line technologies, parsed from older formats (e.g. `verf_100_X`).
- **`mobile Technologien (hist)`**: Wireless/mobile technologies, parsed from older formats (e.g. `verf_200_X`). These are generally filtered out of the final "privat" household dataset.
- **`[prefix]_[tech]_[speed]` derived groups (e.g., `priv_dsl_100 -> DSL (privat)`)**: In Paket 2, some column names included prefixes like "priv" (private), "gew" (business), "schulen" (schools). The parsing logic often tried to incorporate this prefix into the technology group, like "DSL (privat)".
- **Non-speed metrics (often with `NA` speed_mbps_gte)**:
  - `id`: Likely an identifier or sequential number from the original data, not a broadband metric.
  - `ewz` / `einwohner`: Likely "Einwohnerzahl" (population count).
  - `HH_ges`: Likely "Haushalte gesamt" (total households).
  - `GemFl`: Likely "Gemeindefläche" (municipality area).
  - `Anschl_Glasfaser`: Likely "Anschlüsse Glasfaser" (fiber optic connections).
  - `unternehmen_X`: Metrics related to businesses of size X.
  - `Verfügbarkeit`: Generic availability, often seen with more specific technology names.

This list is not exhaustive, as new or unparsed variable names would become their own `technology_group`. The `original_variable` column should always be consulted for the exact source string.

## Initial excel inspection (`inspect_excel_sheets.R`)

- **Purpose**: To systematically identify which sheets within Excel files (primarily in Paket 1 and 2) contain relevant municipality-level data.
- **Process**:
  1. Lists all `.xls` and `.xlsx` files in specified Paket directories (e.g., `data/Paket_1`, `data/Paket_2`), excluding temporary files (e.g., starting with `~$`).
  2. For each Excel file, it iterates through all its sheets.
  3. For each sheet, it attempts to read the header row(s).
  4. It uses `find_ags_column_name` to check if an AGS column is present in the sheet's header.
  5. Records the file path, sheet name, and whether an AGS column was found.
- **Output**: A CSV file, `output/excel_sheet_inspection_summary.csv`, listing each Excel file, its sheets, and a boolean indicating AGS column presence. This summary is then used by subsequent Paket processing scripts.

## Processing paket 1 (`process_paket_1.R`)

- **Input**:
  - Excel files from `data/Paket_1`.
  - `output/excel_sheet_inspection_summary.csv`.
- **Key Steps**:
  1. Filters the inspection summary for Paket 1 files/sheets where an AGS column was found.
  2. Iterates through these selected sheets.
  3. The `process_sheet_data_paket1` function handles each sheet:
     a.  Reads the Excel sheet using `read_excel`.
     b.  Cleans column names using `make.names(unique=TRUE)` and keeps a map to original names.
     c.  Identifies the AGS column using `find_ags_column_name`.
     d.  Determines the `year` for the sheet's data using `extract_year_for_sheet` (tries sheet name first, then filename).
     e.  Pivots the data into a long format using `pivot_longer`, transforming all measure columns into `original_variable` and `value_raw` columns. The `value_raw` is initially treated as character to handle mixed types.
     f.  For each `original_variable`, it calls `parse_broadband_variable` to extract `technology_group`, `speed_mbps_gte`, and `year_from_variable`.
     - A specific rule was added to handle the historical `verf_dsl` variable from 2005-2008 files, interpreting it as `DSL (hist)` with a speed of `0.128` (representing >=128 kbit/s).
     g.  If `year_from_variable` is present, it overrides the sheet/filename-derived year.
     h.  The `value_raw` is converted to numeric.
     i.  Selects and renames columns to the standard output format.
  4. Combines data from all processed sheets.
  5. Standardizes AGS to 8 digits (padding with leading zeros).
  6. Filters out rows with NA values for key fields.
- **Output**: `output/broadband_gemeinde_paket_1_long.rds`.
- **Verification (`verify_paket_1_output.R`)**: This script was created to check if the year assignment logic, particularly the override from `year_from_variable` in `parse_broadband_variable` (e.g., for columns like `verf_300_50_2010`), was working correctly. It confirmed that when a year was present in the variable name, it was correctly used in the final `year` column.

## Processing paket 2 (`process_paket_2.R`)

- **Input**:
  - Excel files from `data/Paket_2`.
  - `output/excel_sheet_inspection_summary.csv`.
- **Key Steps (adaptations and additions compared to Paket 1 processing are highlighted)**:
  1. Filters inspection summary for Paket 2.
  2. Iterates through selected sheets.
  3. The `process_sheet_data_paket2` function handles each sheet:
     a.  Reads Excel sheets, using `.name_repair = "minimal"` in `read_excel` to handle potentially problematic column names initially.
     b.  Year extraction via `extract_year_for_sheet` included rules for sheet names like `2018_Gemeindedaten`.
     c.  **Optimized Parsing**: Instead of calling `parse_broadband_variable` for every row in the long data, it first finds unique `original_variable` names from the sheet, parses them once, and then joins the parsing results back to the long data. This significantly improved performance for large sheets.
     d.  **Refined `parse_broadband_variable`**:
     *Added "hfc" to historical technology regex.
     - Added patterns for household data (e.g., `HH_DSL_16`) and non-speed columns (e.g., `HH_ges`, `GemFl`).
     *Enhanced regex for modern column names (e.g., `"Technology Name >= 100 Mbit/s"`) to better handle spacing.
     - Added rule for `prefix_technology_speed` pattern (e.g., `priv_dsl_100`).
     e.  More robust cleaning of the `value` column before numeric conversion (e.g., handling non-standard characters like "-", replacing commas with dots).
     f.  A check was added to skip sheets with fewer than 3 columns if they were not of a "Kennziffer" (AGS-only) type, to avoid processing irrelevant small sheets.
  4. Combines data from all processed sheets.
  5. Standardizes AGS and filters NA values.
- **Output**: `output/broadband_gemeinde_paket_2_long.rds`.
- **Verification (`verify_paket_2_output.R`)**: Checked for year assignment from variable names (similar to Paket 1). The final check showed no such variables were present in the *final output* of Paket 2 that matched the `_YYYY` suffix pattern, meaning year assignment relied on sheet/filename for this paket.

## Processing paket 3 (`process_paket_3.R`)

- **Input**: CSV files from `data/Paket_3`. This Paket was simpler as it contained only CSVs.
- **Key Steps**:
  1. Lists all CSV files in `data/Paket_3`.
  2. Iterates through each file.
  3. `determine_data_category` used to classify files (e.g., "privat", "gewerbe", "mobilfunk"). The script was configured to **only process "privat" files and to explicitly exclude files containing `_stats` in their name**.
  4. `extract_year_from_filename` used to get the year.
  5. The `process_csv_file_paket3` function handles each CSV:
     a.  Reads the CSV file. Handles potential semicolon delimiters by trying `read_csv2` if `read_csv` results in a single column.
     b.  Column cleaning and AGS identification similar to other Pakets.
     c.  Pivots data longer.
     d.  Uses `parse_broadband_variable` (primarily matching "modern" names like `"Technology Name >= X Mbit/s"`).
     e.  Converts `value` to numeric.
  6. Combines data from all processed "privat" CSV files.
  7. Further filters out any remaining "mobil" related `technology_group` entries as a safeguard.
  8. Standardizes AGS and filters NAs.
- **Output**: `output/broadband_gemeinde_paket_3_long.rds`.
- **Verification (`verify_paket_3_output.R`)**:
  1. Confirmed that only `data_category == "privat"` rows were present.
  2. Confirmed that no `technology_group` containing "mobil" was present.
     Both checks passed.

## Combining datasets (`combine_datasets.R`)

- **Purpose**: To merge the processed long-format data from Pakets 1, 2, and 3 into a single, unified dataset.
- **Input**:
  - `output/broadband_gemeinde_paket_1_long.rds`
  - `output/broadband_gemeinde_paket_2_long.rds`
  - `output/broadband_gemeinde_paket_3_long.rds`
- **Key Steps**:
  1. The `load_and_check_paket_data(file_path, paket_name)` function is used for each Paket's data:
     a.  Loads the data.
     b.  Ensures `AGS` is character type.
     c.  **Filters out mobile technologies**: Removes rows where `technology_group` (case-insensitive) contains "mobil". This acts as a final consistency check.
     d.  **AGS Format Check**: Verifies that all `AGS` entries are exactly 8 digits long and not NA. Reports errors if any. (All Pakets passed this).
     e.  **Duplicate Metric Check**: Groups data by `AGS`, `year`, `technology_group`, `speed_mbps_gte` and checks if any group has more than one row (using `summarise(n_rows = n()) %>% filter(n_rows > 1)`).
     *Paket 1 & 3: Passed (SUCCESS).
     - Paket 2: Showed a WARNING, indicating that multiple `original_variable` names mapped to the same parsed `technology_group` and `speed_mbps_gte`. This was deemed acceptable as it reflects the varied source naming, and data isn't lost.
     f.  Adds a `source_paket` column (e.g., "Paket 1", "Paket 2", "Paket 3") to trace data origin.
     g.  **Column Standardization**: Ensures a `data_category` column exists (adds as `NA_character_` if missing). Converts `value` to numeric (handling potential commas as decimals). Selects a common, defined set of columns (`AGS, year, data_category, technology_group, speed_mbps_gte, value, original_variable, source_paket`) to ensure consistent schemas before binding.
  2. The processed data frames from each Paket are combined using `bind_rows()`.
  3. Ensures consistent data types for key columns (`speed_mbps_gte` as numeric, preserving `0.128`, `value` as numeric, `year` as integer) across the combined dataset.
  4. A final `distinct()` operation is performed on the entire combined dataset to remove any rows that are identical across all columns.
  5. Prints various summaries of the final dataset:
     - Total row counts before/after distinct.
     - Number of unique AGS.
     - Range of years and counts per year.
     - Data categories present (should be only "privat").
     - Contribution of each source Paket.
     - Unique `technology_group` values and counts.
     - Unique `speed_mbps_gte` values and counts.
     - Number and sample of unique `original_variable` names.
- **Output**: `output/broadband_gemeinde_combined_long.rds`.

## Standardizing municipal borders to 2021 (`standardize_ags_to_2021.R`)

- **Purpose**: To transform the combined broadband data from its historical municipal boundaries (as represented by `AGS` and `year`) to the standardized municipal boundaries of 31.12.2021. This is crucial for consistent longitudinal analysis, especially for econometric studies, as municipal borders change over time due to mergers and administrative reforms.
- **Input**:
  - `output/broadband_gemeinde_combined_long.rds`: The combined dataset with historical AGS codes.
  - `data/muni_mergers/ref-gemeinden-umrech-2021-2000-2010.xlsx`: Destatis reclassification table for years 2000-2010 to 2021.
  - `data/muni_mergers/ref-gemeinden-umrech-2021-2011-2020.xlsx`: Destatis reclassification table for years 2011-2020 to 2021.
- **Key Steps**:
  1. **Master Crosswalk Generation**:
     a.  The `process_merger_sheet` function reads individual sheets from the Destatis Excel files. Each sheet typically corresponds to a specific historical year (e.g., "2010", "2015").
     b.  It dynamically identifies key columns within each sheet: the historical AGS (e.g., "Gemeinden 31.12.YYYY"), the target 2021 AGS ("Gemeinden 31.12.2021"), and the population-proportional key ("bevölkerungs- proportionaler Umsteige- schlüssel"). Column names containing `\r\n` are handled by `str_detect`.
     c.  The population-proportional transition key is combined with the historical population column to construct a `population_weight` for each historical-to-2021 mapping row.
     d.  AGS codes are standardized to 8-digit character strings with leading zeros.
     e.  The script iterates through all relevant years (2005-2020), processes the corresponding sheets from the two Excel files, and binds them into a single `master_crosswalk` table containing `AGS_hist`, `year_hist`, `AGS_2021`, `transition_share`, and `population_weight`.
     f.  A validation step checks that the transition shares for each `AGS_hist` and `year_hist` combination sum to approximately 1.0.
  2. **Loading and Preparing Broadband Data**:
     a.  Loads `output/broadband_gemeinde_combined_long.rds`.
     b.  Ensures `AGS` and `year` columns are of the correct type for joining (character and integer, respectively).
  3. **Joining Broadband Data with Master Crosswalk**:
     a.  The `master_crosswalk` is augmented only when a defensible mapping exists, in order of precedence: (i) a nearest-year crosswalk fallback for codes present in another year's sheet than the data year (donor-year target sets are identical for all affected codes; details in `output/nearest_year_fallback_mapping.rds`), (ii) Bezirk-to-city aggregation for Berlin/Hamburg 2020-2021, (iii) 1:1 mappings for valid 2021 AGS codes in no crosswalk sheet, and (iv) deterministic reform chains from `data/gebietsreformen/combined_reform_mappings.rds`. Assertions verify that no (AGS, year) key is served by multiple sources and that supplementary transition shares sum to 1.
     b.  Invalid AGS codes that cannot be mapped to the Destatis 2021 reference are written to `output/unmapped_ags_for_review.csv` (with years and row counts) and filtered. The current run filters 9,948 post-deduplicated long rows (0.33%) covering 122 historical AGS codes.
     c.  Before joining, duplicate historical AGS-year-technology-speed cells are collapsed with `max(value)`, preserving traceability in `original_variable` and `source_paket`.
     d.  The broadband data is left-joined with the crosswalk using historical `AGS` and `year`.
  4. **Aggregating Percentage Values to 2021 AGS**:
     a.  The data is grouped by the new `AGS_2021` (renamed to `AGS`), `year`, `data_category`, `technology_group`, and `speed_mbps_gte`.
     b.  Coverage percentages are aggregated with a population-weighted mean using `population_weight`. This avoids the prior error of summing percentages across merged municipalities or overlapping source packages.
     c.  `original_variable` and `source_paket` are handled by concatenating unique sorted values, separated by a semicolon, to preserve traceability. An `n_agg` column counts how many original rows were aggregated.
     d.  The script validates that aggregated coverage remains within [0, 100] and stops if it does not.
- **Output**: `output/broadband_gemeinde_combined_long_ags2021.rds`. This file contains broadband data where all municipalities are represented by their 2021 AGS codes, with coverage values appropriately apportioned.

## Final panel creation (`create_treatment_variables.R`)

- **Purpose**: To generate the final, wide-format panel dataset from the AGS-2021 standardized long-format data. This includes creating a consistent baseline coverage variable that incorporates historical (>=0.128 Mbps) data.
- **Input**: `output/broadband_gemeinde_combined_long_ags2021.rds` (the output from the AGS standardization step).
- **Key Steps**:
  1. **Data Loading and Initial Filtering**:
     a.  Loads the AGS-2021 standardized data.
     b.  Re-validates that AGS codes exist in the official Destatis 2021 reference list. The filtering of unmapped AGS codes occurs in step 06.
     c.  Filters only invalid rows with missing speed/value or values outside [0,100]. The current run filters zero rows at this stage.
  2. **Collapse and Widen to Share Columns**:
     a.  The script first groups data by `AGS`, `year`, and `speed_mbps_gte` to get the maximum coverage for each specific speed.
     b.  It then calculates several "greater-than-or-equal-to" share variables by taking the maximum coverage for any speed at or above a given threshold. This includes the new `share_broadband_baseline` (>=0.128 Mbps) and the standard tiers (>=1, >=6, >=30 Mbps).
     c.  **Critical for 2005-2008**: The `share_broadband_baseline` variable includes `speed_mbps_gte == 0.128`, representing historical DSL availability (>=0.128 Mbps). This ensures 2005-2008 baseline coverage is correctly populated (~81% mean in the final public file) rather than showing 0%.
     d.  Missing speed tiers remain missing (`NA`) instead of being converted to zero. In 2005-2008, `share_gte1mbps`, `share_gte6mbps`, and `share_gte30mbps` are missing because the source files do not report those tiers.
  3. **Hierarchical Consistency**: The "at or above" threshold construction enforces `share_broadband_baseline >= share_gte1mbps >= share_gte6mbps >= share_gte30mbps` whenever both adjacent tiers are observed. The script stops if violations remain.
  4. **2015 Methodological Change Dummy**: Based on external analysis indicating a methodological shift, a dummy variable `method_change_2015` is added. It takes the value `1` for observations in the year 2015 and `0` otherwise.
  5. **Diagnostic Checks**: Includes summaries of panel dimensions, AGS-year uniqueness, and share column distributions. Also calculates year-on-year changes in share columns to flag large increases (>50 ppt) or significant decreases (< -20 ppt), summarizing these by year and generating a plot (`output/large_yoy_changes_plot.png`).
- **Outputs**:
  - `output/panel_data_public.csv`: The final public dataset.
  - `output/panel_data_with_treatment.csv`: A version of the dataset including variables for internal econometric analysis.

## Final data structure (public panel)

The final public panel dataset (`output/panel_data_public.csv`) is structured at the municipality-year level and contains the following key columns:

### Variable dictionary

| Variable                     | Type      | Description                                                                                                                                              | Values           |
| ---------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `AGS`                      | character | 8-digit official municipality key, standardized to 2021 borders.                                                                                         | e.g., "01001000" |
| `year`                     | integer   | The year of the observation.                                                                                                                             | 2005-2021, excluding 2009 |
| `share_broadband_baseline` | double    | Share of households (%) with access to basic broadband (**>=0.128 Mbps**). This variable provides the most complete time series, starting in 2005. | 0-100            |
| `share_gte1mbps`           | double    | Share of households (%) with access to **>=1 Mbps**. Missing before the tier is reported.                                                          | 0-100 or missing |
| `share_gte6mbps`           | double    | Share of households (%) with access to **>=6 Mbps**. Missing before the tier is reported.                                                          | 0-100 or missing |
| `share_gte30mbps`          | double    | Share of households (%) with access to **>=30 Mbps**. Missing before the tier is reported.                                                         | 0-100 or missing |
| `method_change_2015`       | integer   | Dummy variable:`1` if `year` is 2015, otherwise `0`.                                                                                               | `0`, `1`     |

## Analytical potential and data availability

### Analytical potential

This dataset is designed for quantitative longitudinal analysis of the effects of broadband internet rollout in Germany. Potential applications include:

1. **Econometric Impact Evaluation**: Researchers can merge this dataset with other municipal-level data (e.g., on economic outcomes, demographics, political behavior) to study the impact of broadband availability. The panel structure is suitable for methods like Difference-in-Differences, though treatment indicators would need to be constructed by the user based on their research question.
2. **Descriptive Analysis**: The `share_*` variables can be used to describe the spatio-temporal diffusion of different tiers of broadband technology across Germany. The generated plots (`average_annual_coverage_plot.png`, `large_yoy_changes_plot.png`) provide an initial overview of these trends.
3. **Controlling for Methodological Breaks**: The `method_change_2015` dummy is crucial for any analysis spanning this year, as it allows researchers to control for the structural break in the data series caused by changes in the data provider and reporting standards.

### Data availability

The panel is unbalanced, as not all municipalities report data in all years, and the availability of specific speed tiers varies over time.

- **Time Period**: The dataset covers the years **2005 to 2021**, excluding 2009. The `share_broadband_baseline` variable provides the most complete measure of basic availability, but it has a definition break between 2008 and 2010.
- **Broadband Tiers**: Meaningful data for the higher-speed `share_*` variables still emerges over time:
  - `share_gte1mbps`, `share_gte6mbps`, and `share_gte30mbps` are observed from **2010 onwards** in the current final panel.
  - Before 2010, higher speed tiers are left missing rather than filled with zero.
- **AGS Standardization**: All municipal identifiers (`AGS`) have been standardized to the **31.12.2021** administrative boundaries. This ensures that analyses are not biased by municipal mergers or splits over the observation period.

### Observing changes over time

- **Identifying Coverage Thresholds**: **Yes**, the dataset allows users to identify when a municipality's broadband coverage crosses a specific threshold (e.g., 50%) by observing the `share_*` variables over time. This can be used to construct custom treatment indicators for analysis.
- **Temporal Granularity**: The key limitation is that observations are **annual snapshots**. If coverage in a municipality jumps from 10% to 60% between 2012 and 2013, we know the change occurred *during* that period, but we cannot know the specific month or the trajectory of the change (e.g., a gradual rollout vs. a single switch-on event).

### Limitations and unobserved factors

There are several dimensions that this dataset, by design, cannot measure:

- **Availability vs. Take-Up**: The data measures the **technical availability** of broadband, not the number of households or businesses that actually subscribe to or use the service (the take-up rate).
- **Quality of Service**: The dataset does not contain information on the quality of the connection, such as latency, jitter, or actual experienced speeds versus advertised speeds.
- **Competition and Technology Mix**: To create a consistent measure of access, the pipeline collapses all underlying technologies (DSL, Cable, Fiber) and providers into a single metric for the *maximum* available speed in an area. Therefore, the dataset does not provide information on the level of competition (e.g., number of providers) or the specific technology mix within a municipality.
- **Intra-Municipal Variation**: The final panel data is aggregated at the municipality level. While the raw data is based on a 100m x 100m grid, this fine-grained spatial information is lost in the final panel, meaning we cannot observe which specific neighborhoods within a town are covered.

## Known limitations

### Methodological breaks

1. **2010 baseline definition change**: `share_broadband_baseline` switches from >=0.128 Mbps (2005-2008) to >=1 Mbps (2010+). There is no 2009 municipality panel in the current input files. This creates a discontinuity in the series.
2. **2015 provider change**: A new data provider and reporting standards caused a large discontinuous jump across all speed tiers. Use the `method_change_2015` dummy to control for this.

### Filtered observations

Step 06 filters 9,948 post-deduplicated long rows (0.33%) covering 122 historical AGS codes because they cannot be mapped to official Destatis 2021 municipality boundaries. These are mostly Bavarian gemeindefreie Gebiete (unincorporated areas, no 2021 municipality equivalent) and sub-municipal district codes whose parent cities are already covered. The formerly large Sachsen-Anhalt gap (post-2007 codes in 2005-2006 files) is resolved by the nearest-year crosswalk fallback.

See [unmapped_ags_documentation.md](unmapped_ags_documentation.md) for complete details.

### Non-reporting coded as zero, 2010-2014 (fixed July 2026)

About 6,600 municipalities per year, including Berlin, showed exactly 0 across all speed tiers throughout 2010-2014 while averaging 87% baseline coverage in 2008 and 98% in 2015. These were non-reporting municipalities coded as zero in the historical Paket 1 source (`verf_300_*` columns), not true zeros. Step 06 removes municipality-years where all tiers (`speed_mbps_gte >= 1`) are exactly zero, restricted to 2010-2014: 33,138 municipality-years (79,432 long rows). The rule preserves genuine zeros at high tiers only (6,771 municipality-years in 2010-2014 have 0% at `>=30 Mbps` alongside `>=1 Mbps` coverage above 80%) and does not touch the genuine 2005-2008 DSL zeros. All-tier-zero municipality-years in 2015-2021 (697, mostly persistently zero small municipalities) are retained and written to `output/nonreporting_zero_blocks.csv` for review.

Consequences: 2010-2014 covers only reporting municipalities (~4,400-4,500 per year, skewed toward larger municipalities), and the 2015 break is largely resolved. The unweighted mean baseline jump from 2014 to 2015 was 57.3 percentage points before the fix; the within-municipality jump among the 4,536 continuous reporters is 1.2 percentage points, so 98% of the apparent jump was the false zeros. Higher-tier within-municipality jumps at 2015 (8-10 ppt) are in line with adjacent-year rollout growth. `method_change_2015` is retained; its main remaining content is the return to near-complete municipality coverage in 2015 (a composition change). Diagnostics: `src/auxiliary/verification/verify_zero_fix.R`.

### Missing geographic coverage

- **City-states**: Berlin and Hamburg are included at city level for 2005-2019; their 2020-2021 values are unweighted means across Bezirke (see caveats in README). Berlin's 2010-2014 values are affected by the non-reporting issue above.
- **Sparse years and tiers**: 2009 is absent from the current municipality panel; 2005-2008 only report the historical baseline tier.

## Conclusion

This pipeline transforms historical broadband data files into a panel dataset standardized to 2021 municipal boundaries. The `original_variable` and `source_paket` columns in intermediate files preserve traceability to the raw data.
