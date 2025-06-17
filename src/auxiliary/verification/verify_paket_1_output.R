library(tidyverse)
library(here)
library(stringr)

# --- Script to Verify Year Assignment in Paket 1 Output ---

print("Starting verification of Paket 1 output (broadband_gemeinde_paket_1_long.csv)...")

paket1_output_file <- here("output", "broadband_gemeinde_paket_1_long.csv")

if (!file.exists(paket1_output_file)) {
    stop("Error: Processed Paket 1 output file not found at ", paket1_output_file, ". Please run process_paket_1.R first.")
}

data_to_verify <- read_csv(paket1_output_file, show_col_types = FALSE)

print(paste("Read", nrow(data_to_verify), "rows from Paket 1 output."))

# Focus on variables that likely had embedded years, e.g., from 'verf_privat_alle_2010_2018.xls'
# These typically start with 'verf_' and end with '_YYYY'
relevant_rows <- data_to_verify %>%
    filter(str_detect(tolower(original_variable), "^verf_\\w+_\\w+_\\d{4}$")) # Corrected for R string: \\w and \\d

if (nrow(relevant_rows) == 0) {
    print("No rows found that match the pattern of variables with embedded years (e.g., 'verf_..._YYYY').")
    print("Verification cannot proceed for these specific cases. This might be okay if Paket 1 didn't have such columns or they weren't processed.")

    # If no rows matching the specific "verf_..._YYYY" pattern are found,
    # check for other variables that might imply a year context from early DSL files.
    print("Checking general year assignments for files like '200X_DSL_Verfügbarkeit_Deutschland.xlsx'...")

    dsl_early_files_sample <- data_to_verify %>%
        filter(str_detect(tolower(original_variable), "^verf_dsl$") | # From the 2005-2008 DSL files
            str_detect(tolower(original_variable), "^id$") |
            str_detect(tolower(original_variable), "^ewz$")) %>%
        filter(year %in% c(2005, 2006, 2007, 2008)) # Focus on expected years for these files

    if (nrow(dsl_early_files_sample) > 0) {
        print("Sample of year assignments for early DSL files (2005-2008 data):")
        print(dsl_early_files_sample %>%
            group_by(year, original_variable) %>%
            summarise(n_rows = n(), .groups = "drop") %>%
            arrange(year, original_variable))
        print("If these years (2005-2008) look correct for these variables, then year assignment for these files is likely working.")
    } else {
        print("Could not find sample data for early DSL files (2005-2008) to perform a general year check.")
    }
} else { # This 'else' corresponds to 'if (nrow(relevant_rows) == 0)'
    print(paste("Found", nrow(relevant_rows), "rows potentially from multi-year columns to verify."))

    # Extract the year from the original_variable name
    relevant_rows_with_parsed_year <- relevant_rows %>%
        mutate(
            year_from_original_var = str_extract(tolower(original_variable), "(?<=_)(\\d{4})$"), # Corrected for R string: \\d
            year_from_original_var = as.integer(year_from_original_var)
        )

    # Check for discrepancies
    discrepancies <- relevant_rows_with_parsed_year %>%
        filter(year != year_from_original_var)

    if (nrow(discrepancies) == 0) {
        print("Verification successful! The 'year' column matches the year parsed from 'original_variable' for all relevant rows.")
        print("Example of verified data (first 5 relevant rows):")
        print(head(relevant_rows_with_parsed_year %>%
            select(AGS, year, original_variable, year_from_original_var, technology_group, speed_mbps_gte), 5))
    } else {
        print(paste("Found", nrow(discrepancies), "discrepancies in year assignment."))
        print("Showing first 10 discrepancies:")
        print(head(discrepancies %>%
            select(AGS, year, original_variable, year_from_original_var, technology_group, speed_mbps_gte), 10))

        # Further summary of discrepancies
        discrepancy_summary <- discrepancies %>%
            count(year, year_from_original_var, original_variable) %>%
            arrange(desc(n))
        print("Summary of discrepancy types (top 10 by count):")
        print(head(discrepancy_summary, 10))
    }

    # Sanity check: Are there NAs in year_from_original_var where we expected a year?
    na_in_parsed_year <- relevant_rows_with_parsed_year %>%
        filter(is.na(year_from_original_var))

    if (nrow(na_in_parsed_year) > 0) {
        print(paste("Warning:", nrow(na_in_parsed_year), "rows matched the general pattern for embedded years, but a year could not be parsed from original_variable."))
        print("Examples of original_variable where year parsing failed:")
        print(head(na_in_parsed_year %>% distinct(original_variable), 10))
    }
}

print("Verification script finished.")
