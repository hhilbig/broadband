# Data Processing Pipeline for Breitbandatlas Historical Data

## 1. Introduction

This document details the data processing pipeline created to clean, standardize, and combine historical broadband availability data for German municipalities ("Gemeinden"). The goal is to produce a single, long-format dataset where each row represents a municipality-year combination, along with broadband technology, speed, and a corresponding value (typically percentage coverage or household count).

The data originates from three main "Pakets" (bundles) provided by the Bundesnetzagentur, containing historical data from previous Breitbandatlas operators. The focus of this processing is on data relevant to private households ("privat").

## 2. Overall Approach

The core strategy involves:

1. **Paket-Specific Processing**: Developing separate R scripts to handle the unique formats and challenges within each data Paket (`Paket_1`, `Paket_2`, `Paket_3`).
2. **Helper Functions**: Creating a suite of reusable R functions for common tasks like year extraction, AGS (Amtlicher Gemeindeschlüssel - official municipality key) identification, and parsing broadband variable names.
3. **Data Harmonization**: Transforming varied column names and data structures into a consistent schema across all Pakets. This includes extracting technology type, minimum speed (≥ Mbit/s), and the reported value.
4. **Filtering**: Focusing on data for "privat" (private households) and excluding "gewerbe" (business) and "mobilfunk" (mobile telecommunications) where specified.
5. **Verification**: Implementing checks within scripts and separate verification scripts to ensure data integrity (e.g., correct AGS format, consistent year assignment).
6. **Combination**: Merging the processed data from individual Pakets into a final, comprehensive long-format dataset.

All R scripts utilize libraries from the `tidyverse` for data manipulation, `readxl` for Excel files, `stringr` for string operations, and `here` for path management.

## 3. Key Helper Functions

Several helper functions were developed and refined throughout the project. These are typically defined within each processing script or sourced if they were in a common file.

### 3.1. Year Extraction

- `extract_year_from_filename(filename)`: Attempts to extract a 4-digit year (e.g., 2005-2024) from a filename using regex. Includes fallbacks for formats like "ende18" (interpreted as 2018).
- `extract_year_for_sheet(sheet_name, filename_year)`: Used primarily in Paket 1 and 2 for Excel files. It first tries to extract the year from the sheet name (e.g., patterns like `^(\d{4})_` for "2019_SheetName", or specific keywords like "ende JJ"). If unsuccessful, it falls back to the year extracted from the filename.

### 3.2. AGS Column Identification

- `find_ags_column_name(col_names)`: Identifies the AGS column in a dataset by checking a list of common patterns (e.g., "ags", "gemeindeschluessel", "gem", "kennziffer") against the column names (case-insensitive). Returns the original column name.

### 3.3. Data Category Determination

- `determine_data_category(filename)`: Determines if a file pertains to "privat", "gewerbe", "mobilfunk", or "alle" based on keywords in the filename.

### 3.4. Broadband Variable Parsing

- `parse_broadband_variable(variable_name)`: This is a crucial and complex function responsible for interpreting the meaning of broadband-related column headers. It evolved significantly to handle various naming conventions across Pakets.
  - **Input**: A column name string.
  - **Output**: A tibble with `technology_group`, `speed_mbps_gte`, and potentially `year_from_variable`.
  - **Key Patterns Handled**:
        1. **Modern Names (e.g., Paket 3, newer Paket 2)**: `"Technology Name ≥ 100 Mbit/s"` or `"Technology Name  100 Mbit/s"`. Extracts technology and speed.
        2. **Historical `verf_` prefixed names (Paket 1)**: `"verf_100_50"` (leitungsgebunden, ≥ 50 Mbit/s), `"verf_200_30"` (drahtlos), `"verf_300_10"` (alle). Maps `verf_` codes to technology groups and extracts speed.
        3. **Historical specific tech names (Paket 1)**: `"DSL_16"`, `"CATV_400"`. Extracts technology and speed.
        4. **`_gtoe_` names (Paket 2)**: `"dsl_gtoe_16_mbits"`. Interprets "gtoe" as "greater than or equal to".
        5. **Prefixed tech names (Paket 2)**: `"priv_dsl_100"`, `"gew_lg_tech_50"`. Extracts prefix (user type), technology, and speed.
        6. **Household/Non-speed (Paket 2)**: `"HH_ges"` (total households), `"HH_DSL_16"`, `"GemFl"` (municipality area). Identifies these as distinct categories, often with `NA` speed.
        7. **Year in variable (Paket 1, Paket 2)**: If a variable name ends with `_YYYY` (e.g., `verf_alle_tech_100_2010`), this year is extracted and takes precedence.
  - If no pattern matches, the original variable name is typically returned as the `technology_group` with `NA` speed.

### 3.5. Interpretation of Common `technology_group` Values

The `parse_broadband_variable` function generates various `technology_group` strings. Here's an interpretation of common ones encountered:

- **`Leitungsg. Technologien (gtoe)` / `leitungsg. Technologien`**: Refers to "fixed-line technologies" (literally "line-bound technologies"). The "(gtoe)" likely indicates "greater than or equal to", often seen in newer Paket 2/3 data where the speed is explicitly part of the original column name in a format like "Leitungsg. Technologien ≥ X Mbit/s". The version without "(gtoe)" might come from older data or different naming schemes.
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

## 4. Initial Excel Inspection (`inspect_excel_sheets.R`)

- **Purpose**: To systematically identify which sheets within Excel files (primarily in Paket 1 and 2) contain relevant municipality-level data.
- **Process**:
    1. Lists all `.xls` and `.xlsx` files in specified Paket directories (e.g., `data/Paket_1`, `data/Paket_2`), excluding temporary files (e.g., starting with `~$`).
    2. For each Excel file, it iterates through all its sheets.
    3. For each sheet, it attempts to read the header row(s).
    4. It uses `find_ags_column_name` to check if an AGS column is present in the sheet's header.
    5. Records the file path, sheet name, and whether an AGS column was found.
- **Output**: A CSV file, `output/excel_sheet_inspection_summary.csv`, listing each Excel file, its sheets, and a boolean indicating AGS column presence. This summary is then used by subsequent Paket processing scripts.

## 5. Processing Paket 1 (`process_paket_1.R`)

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
            *   A specific rule was added to handle the historical `verf_dsl` variable from 2005-2008 files, interpreting it as `DSL (hist)` with a speed of `0.128` (representing ≥128 kbit/s).
        g.  If `year_from_variable` is present, it overrides the sheet/filename-derived year.
        h.  The `value_raw` is converted to numeric.
        i.  Selects and renames columns to the standard output format.
    4. Combines data from all processed sheets.
    5. Standardizes AGS to 8 digits (padding with leading zeros).
    6. Filters out rows with NA values for key fields.
- **Output**: `output/broadband_gemeinde_paket_1_long.csv`.
- **Verification (`verify_paket_1_output.R`)**: This script was created to check if the year assignment logic, particularly the override from `year_from_variable` in `parse_broadband_variable` (e.g., for columns like `verf_300_50_2010`), was working correctly. It confirmed that when a year was present in the variable name, it was correctly used in the final `year` column.

## 6. Processing Paket 2 (`process_paket_2.R`)

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
            *   Added patterns for household data (e.g., `HH_DSL_16`) and non-speed columns (e.g., `HH_ges`, `GemFl`).
            *Enhanced regex for modern column names (e.g., `"Technology Name ≥ 100 Mbit/s"`) to better handle spacing.
            *   Added rule for `prefix_technology_speed` pattern (e.g., `priv_dsl_100`).
        e.  More robust cleaning of the `value` column before numeric conversion (e.g., handling non-standard characters like "-", replacing commas with dots).
        f.  A check was added to skip sheets with fewer than 3 columns if they were not of a "Kennziffer" (AGS-only) type, to avoid processing irrelevant small sheets.
    4. Combines data from all processed sheets.
    5. Standardizes AGS and filters NA values.
- **Output**: `output/broadband_gemeinde_paket_2_long.csv`.
- **Verification (`verify_paket_2_output.R`)**: Checked for year assignment from variable names (similar to Paket 1). The final check showed no such variables were present in the *final output* of Paket 2 that matched the `_YYYY` suffix pattern, meaning year assignment relied on sheet/filename for this paket.

## 7. Processing Paket 3 (`process_paket_3.R`)

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
        d.  Uses `parse_broadband_variable` (primarily matching "modern" names like `"Technology Name ≥ X Mbit/s"`).
        e.  Converts `value` to numeric.
    6. Combines data from all processed "privat" CSV files.
    7. Further filters out any remaining "mobil" related `technology_group` entries as a safeguard.
    8. Standardizes AGS and filters NAs.
- **Output**: `output/broadband_gemeinde_paket_3_long.csv`.
- **Verification (`verify_paket_3_output.R`)**:
    1. Confirmed that only `data_category == "privat"` rows were present.
    2. Confirmed that no `technology_group` containing "mobil" was present.
    Both checks passed.

## 8. Combining Datasets (`combine_datasets.R`)

- **Purpose**: To merge the processed long-format data from Pakets 1, 2, and 3 into a single, unified dataset.
- **Input**:
  - `output/broadband_gemeinde_paket_1_long.csv`
  - `output/broadband_gemeinde_paket_2_long.csv`
  - `output/broadband_gemeinde_paket_3_long.csv`
- **Key Steps**:
    1. The `load_and_check_paket_data(file_path, paket_name)` function is used for each Paket's CSV:
        a.  Loads the data.
        b.  Ensures `AGS` is character type.
        c.  **Filters out mobile technologies**: Removes rows where `technology_group` (case-insensitive) contains "mobil". This acts as a final consistency check.
        d.  **AGS Format Check**: Verifies that all `AGS` entries are exactly 8 digits long and not NA. Reports errors if any. (All Pakets passed this).
        e.  **Duplicate Metric Check**: Groups data by `AGS`, `year`, `technology_group`, `speed_mbps_gte` and checks if any group has more than one row (using `summarise(n_rows = n()) %>% filter(n_rows > 1)`).
            *Paket 1 & 3: Passed (SUCCESS).
            *   Paket 2: Showed a WARNING, indicating that multiple `original_variable` names mapped to the same parsed `technology_group` and `speed_mbps_gte`. This was deemed acceptable as it reflects the varied source naming, and data isn't lost.
        f.  Adds a `source_paket` column (e.g., "Paket 1", "Paket 2", "Paket 3") to trace data origin.
        g.  **Column Standardization**: Ensures a `data_category` column exists (adds as `NA_character_` if missing). Converts `value` to numeric (handling potential commas as decimals). Selects a common, defined set of columns (`AGS, year, data_category, technology_group, speed_mbps_gte, value, original_variable, source_paket`) to ensure consistent schemas before binding.
    2. The processed data frames from each Paket are combined using `bind_rows()`.
    3. Ensures consistent data types for key columns (`speed_mbps_gte` as integer, `value` as numeric, `year` as integer) across the combined dataset.
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
- **Output**: `output/broadband_gemeinde_combined_long.csv`.

## 9. Standardizing Municipal Borders to 2021 (`standardize_ags_to_2021.R`)

- **Purpose**: To transform the combined broadband data from its historical municipal boundaries (as represented by `AGS` and `year`) to the standardized municipal boundaries of 31.12.2021. This is crucial for consistent longitudinal analysis, especially for econometric studies, as municipal borders change over time due to mergers and administrative reforms.
- **Input**:
  - `output/broadband_gemeinde_combined_long.csv`: The combined dataset with historical AGS codes.
  - `data/muni_mergers/ref-gemeinden-umrech-2021-2000-2010.xlsx`: Destatis reclassification table for years 2000-2010 to 2021.
  - `data/muni_mergers/ref-gemeinden-umrech-2021-2011-2020.xlsx`: Destatis reclassification table for years 2011-2020 to 2021.
- **Key Steps**:
    1. **Master Crosswalk Generation**:
        a.  The `process_merger_sheet` function reads individual sheets from the Destatis Excel files. Each sheet typically corresponds to a specific historical year (e.g., "2010", "2015").
        b.  It dynamically identifies key columns within each sheet: the historical AGS (e.g., "Gemeinden 31.12.YYYY"), the target 2021 AGS ("Gemeinden 31.12.2021"), and the population-proportional key ("bevölkerungs- proportionaler Umsteige- schlüssel"). Column names containing `\r\n` are handled by `str_detect`.
        c.  Crucially, the values from the "bevölkerungs- proportionaler Umsteige- schlüssel" column are treated as raw population figures for the part of the historical municipality mapping to a 2021 municipality. The function calculates the true `pop_share` (0-1 proportion) for each mapping by dividing this part-population by the sum of all part-populations for that specific historical AGS in that year. This ensures that the sum of `pop_share` for any given historical AGS (for a specific year) equals 1.0.
        d.  AGS codes are standardized to 8-digit character strings with leading zeros.
        e.  The script iterates through all relevant years (2005-2020), processes the corresponding sheets from the two Excel files, and binds them into a single `master_crosswalk` table containing `AGS_hist`, `year_hist`, `AGS_2021`, and `pop_share`.
        f.  A validation step checks that the sum of `pop_share` for each `AGS_hist` and `year_hist` combination in the `master_crosswalk` is approximately 1.0.
    2. **Loading and Preparing Broadband Data**:
        a.  Loads `output/broadband_gemeinde_combined_long.csv`.
        b.  Ensures `AGS` and `year` columns are of the correct type for joining (character and integer, respectively).
    3. **Joining Broadband Data with Master Crosswalk**:
        a.  The `master_crosswalk` is augmented: AGS-year combinations present in the broadband data but *not* in the Destatis 2005-2020 crosswalks (e.g., data from years > 2020, or stable municipalities within the 2005-2020 period not listed in merger files) are assumed to represent 1:1 mappings. For these, `AGS_2021` is set to the original `AGS`, and `pop_share` is set to 1.0.
        b.  The broadband data is then left-joined with this augmented crosswalk using the historical `AGS` and `year`.
    4. **Apportioning Broadband Values**:
        a.  For each row in the joined data, the broadband `value` (which is a coverage percentage) is multiplied by the corresponding `pop_share` from the crosswalk. This calculates the `weighted_value`, representing the contribution of that historical AGS part to the 2021 AGS's overall broadband coverage for a specific metric.
    5. **Aggregating to 2021 AGS**:
        a.  The data is grouped by the new `AGS_2021` (renamed to `AGS`), `year`, `data_category`, `technology_group`, and `speed_mbps_gte`.
        b.  The `weighted_value` is summed for these groups to get the new `value` for the 2021 AGS.
        c.  `original_variable` and `source_paket` are handled by concatenating unique sorted values, separated by a semicolon, to preserve traceability. An `n_agg` column counts how many original rows were aggregated.
        d.  The aggregated `value` (coverage) is capped at 100 if any sums slightly exceed this due to floating-point arithmetic.
- **Output**: `output/broadband_gemeinde_combined_long_ags2021.csv`. This file contains broadband data where all municipalities are represented by their 2021 AGS codes, with coverage values appropriately apportioned.

## 10. Creating Treatment Variables (`create_treatment_variables.R`)

- **Purpose**: To generate broadband treatment variables and event study timing variables for econometric analysis, based on the AGS-2021 standardized dataset.
- **Input**: `output/broadband_gemeinde_combined_long_ags2021.csv` (the output from the AGS standardization step).
- **Key Steps**:
    1. **Data Loading and Initial Filtering**:
        a.  Loads the AGS-2021 standardized data.
        b.  Filters out rows with NA `speed_mbps_gte` and `value` not in the [0,100] range.
    2. **Collapse and Widen to Share Columns**:
        a.  Groups by `AGS, year, speed_mbps_gte` and takes `max(value)` as `coverage_at_specific_speed`.
        b.  Creates `speed_bucket` categories: "gte1" (≥1 & <6 Mbps), "gte6" (≥6 & <30 Mbps), "gte30" (≥30 Mbps).
        c.  Groups by `AGS, year, speed_bucket` and takes `max(coverage_at_specific_speed)` as `share`.
        d.  Pivots wider to create `share_gte1mbps`, `share_gte6mbps`, `share_gte30mbps`, using `values_fill = 0`.
    3. **Hierarchical Consistency**: Ensures that `share_gte1mbps >= share_gte6mbps >= share_gte30mbps`. Values are adjusted upwards if a lower-speed bucket has less coverage than a higher-speed bucket for the same AGS and year.
    4. **2015 Methodological Change Dummy**: Based on external analysis indicating a methodological shift, a dummy variable `method_change_2015` is added. It takes the value `1` for observations in the year 2015 and `0` otherwise.
    5. **Diagnostic Checks**: Includes summaries of panel dimensions, AGS-year uniqueness, and share column distributions. Also calculates year-on-year changes in share columns to flag large increases (>50 ppt) or significant decreases (< -20 ppt), summarizing these by year and generating a plot (`output/large_yoy_changes_plot.png`).
    6. **Treatment Variable Creation**:
        - `treat_low = share_gte1mbps >= 50`
        - `treat_medium = share_gte6mbps >= 50`
        - `treat_high = share_gte30mbps >= 50`
        - `log_share6 = log1p(share_gte6mbps)`
    7. **Event Study Timing Variables**:
        - `first_year50_6 = min(year)` where `treat_medium == 1`, by `AGS`.
        - `event_time = year - first_year50_6`.
    8. **Further Diagnostics**: Includes counts and summaries for treatment variables and event study variables, including NA checks and sanity checks for `event_time` calculation.
    9. **Plotting Average Coverage**: Generates and saves a plot (`output/average_annual_coverage_plot.png`) showing the average annual coverage across all municipalities for the three share categories.
- **Output**: `output/panel_data_with_treatment.csv`. This is the final dataset intended for econometric analysis.

## 11. Final Data Structure (Panel for Analysis)

The final panel dataset for analysis (`output/panel_data_with_treatment.csv`) is structured at the municipality-year level and contains the following key columns:

- **`AGS`**: The 8-digit official municipality key (character), standardized to **2021 borders**. This is the primary identifier for each municipality.
- **`year`**: The year the data pertains to (integer).
- **`share_gte1mbps`**: Percentage of households (0-100) in the municipality with access to broadband speeds of at least 1 Mbit/s but less than 6 Mbit/s.
- **`share_gte6mbps`**: Percentage of households (0-100) with access to speeds of at least 6 Mbit/s but less than 30 Mbit/s.
- **`share_gte30mbps`**: Percentage of households (0-100) with access to speeds of at least 30 Mbit/s.
- **`treat_low`**: Binary indicator (`1`/`0`) if `share_gte1mbps` is 50% or greater.
- **`treat_medium`**: Binary indicator (`1`/`0`) if `share_gte6mbps` is 50% or greater.
- **`treat_high`**: Binary indicator (`1`/`0`) if `share_gte30mbps` is 50% or greater.
- **`log_share6`**: The natural logarithm of `1 + share_gte6mbps`, providing a continuous variable for treatment intensity.
- **`method_change_2015`**: Binary indicator (`1`/`0`) that flags the year 2015 to account for a significant change in data collection methodology.
- **`first_year50_6`**: The first year that a municipality met the `treat_medium` condition (i.e., the first year its `share_gte6mbps` reached 50%). It is `NA` if the municipality never reached this threshold in the observed period.
- **`event_time`**: A variable for event study analysis, calculated as `year - first_year50_6`. It is negative for years before treatment, 0 in the treatment year, positive for years after, and `NA` for never-treated municipalities.

### Final Dataset: Variable Dictionary

| Variable             | Type      | Description                                                                                                                   | Values                                                                |
| -------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `AGS`                | character | 8-digit official municipality key, standardized to 2021 borders.                                                              | e.g., "01001000"                                                      |
| `year`               | integer   | The year of the observation.                                                                                                  | 2005-2021                                                             |
| `share_gte1mbps`     | double    | Share of households (%) with access to ≥1 Mbps but <6 Mbps.                                                                   | 0-100                                                                 |
| `share_gte6mbps`     | double    | Share of households (%) with access to ≥6 Mbps but <30 Mbps.                                                                  | 0-100                                                                 |
| `share_gte30mbps`    | double    | Share of households (%) with access to ≥30 Mbps.                                                                              | 0-100                                                                 |
| `treat_low`          | integer   | Binary treatment dummy: `1` if `share_gte1mbps` ≥ 50, otherwise `0`.                                                          | `0`, `1`                                                              |
| `treat_medium`       | integer   | Binary treatment dummy: `1` if `share_gte6mbps` ≥ 50, otherwise `0`.                                                          | `0`, `1`                                                              |
| `treat_high`         | integer   | Binary treatment dummy: `1` if `share_gte30mbps` ≥ 50, otherwise `0`.                                                         | `0`, `1`                                                              |
| `log_share6`         | double    | Continuous treatment variable: `log(1 + share_gte6mbps)`.                                                                     | 0 - 4.615 (`log(101)`)                                                |
| `method_change_2015` | integer   | Dummy variable: `1` if `year` is 2015, otherwise `0`.                                                                         | `0`, `1`                                                              |
| `first_year50_6`     | integer   | The first year the municipality reached the `treat_medium` threshold.                                                         | Integer (Year, e.g., 2010) or `NA` if never treated.                  |
| `event_time`         | integer   | Relative time to treatment: `year` - `first_year50_6`.                                                                        | Integer (e.g., -2, -1, 0, 1, 2) or `NA` if `first_year50_6` is `NA`. |

## 12. Analytical Potential and Data Availability

### Analytical Potential

This dataset is designed for quantitative longitudinal analysis of the effects of broadband internet rollout in Germany. Potential applications include:

1. **Econometric Impact Evaluation**: The `treat_*` and `event_time` variables allow for the use of quasi-experimental methods like **Difference-in-Differences (DiD)** or **Event Study** designs. Researchers can merge this dataset with other municipal-level data (e.g., on economic outcomes, demographics, political behavior) to measure the causal impact of reaching certain broadband availability thresholds.
2. **Descriptive Analysis**: The `share_*` variables can be used to describe the spatio-temporal diffusion of different tiers of broadband technology across Germany. The generated plots (`average_annual_coverage_plot.png`, `large_yoy_changes_plot.png`) provide an initial overview of these trends.
3. **Controlling for Methodological Breaks**: The `method_change_2015` dummy is crucial for any analysis spanning this year, as it allows researchers to control for the structural break in the data series caused by changes in the data provider and reporting standards.

### Data Availability

The panel is unbalanced, as not all municipalities report data in all years, and the availability of specific speed tiers varies over time.

- **Time Period**: The dataset covers the years **2005 to 2021**.
- **Baseline DSL (2005-2008)**: The earliest data often only contains a baseline measure for DSL availability (≥128 kbit/s). This data does not fall into the `share_gte1mbps` bucket or higher, correctly reflecting it as a pre-broadband speed.
- **Broadband Tiers (Post-2009)**: Meaningful data for the main `share_*` variables emerges as follows:
  - `share_gte1mbps` and `share_gte6mbps` can be measured relatively consistently from **2009 onwards**.
  - `share_gte30mbps` becomes a consistently reported metric from around **2013 onwards**, reflecting the rollout of VDSL and faster cable technologies.
- **AGS Standardization**: All municipal identifiers (`AGS`) have been standardized to the **31.12.2021** administrative boundaries. This ensures that analyses are not biased by municipal mergers or splits over the observation period.

### Observing Changes Over Time

- **Identifying Treatment Thresholds**: **Yes**, the dataset is explicitly designed to identify when a municipality's broadband coverage crosses a specific threshold. The `first_year50_6` variable, for example, pinpoints the exact year that 50% coverage was achieved for the ≥6 Mbit/s tier. This logic can be extended to create other threshold indicators as needed.
- **Temporal Granularity**: The key limitation is that observations are **annual snapshots**. If coverage in a municipality jumps from 10% to 60% between 2012 and 2013, we know the change occurred *during* that period, but we cannot know the specific month or the trajectory of the change (e.g., a gradual rollout vs. a single switch-on event).

### Limitations and Unobserved Factors

There are several dimensions that this dataset, by design, cannot measure:

- **Availability vs. Take-Up**: The data measures the **technical availability** of broadband, not the number of households or businesses that actually subscribe to or use the service (the take-up rate).
- **Quality of Service**: The dataset does not contain information on the quality of the connection, such as latency, jitter, or actual experienced speeds versus advertised speeds.
- **Competition and Technology Mix**: To create a consistent measure of access, the pipeline collapses all underlying technologies (DSL, Cable, Fiber) and providers into a single metric for the *maximum* available speed in an area. Therefore, the dataset does not provide information on the level of competition (e.g., number of providers) or the specific technology mix within a municipality.
- **Intra-Municipal Variation**: The final panel data is aggregated at the municipality level. While the raw data is based on a 100m x 100m grid, this fine-grained spatial information is lost in the final panel, meaning we cannot observe which specific neighborhoods within a town are covered.

## 13. Conclusion

This pipeline transforms diverse historical broadband data files into a structured, AGS-2021 standardized panel dataset suitable for econometric analysis. The process involves careful parsing of filenames, sheet names, and column headers; meticulous handling of municipal border changes using official reclassification tables; and the creation of theoretically grounded treatment and event study variables. While efforts were made to standardize categories, the `original_variable` and `source_paket` columns in intermediate datasets provide traceability to the raw data. The final panel data is robustly prepared for further analytical work.
