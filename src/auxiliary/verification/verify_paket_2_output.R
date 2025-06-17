library(tidyverse)
library(stringr)
library(here)

# Load the processed Paket 2 data
paket2_data_file <- here("output", "broadband_gemeinde_paket_2_long.csv")
if (!file.exists(paket2_data_file)) {
    stop(paste("Paket 2 output file not found:", paket2_data_file, "
Please run process_paket_2.R first."))
}

paket2_data <- read_csv(paket2_data_file, show_col_types = FALSE)

print(paste("Loaded", nrow(paket2_data), "rows from", basename(paket2_data_file)))

# Verification for year assignment from variable names
# In process_paket_2.R, if a variable name ends with _YYYY, that year should be used.
# The regex used in parse_broadband_variable was: "_(\\\\d{4})$"

# Identify rows where original_variable might contain a year suffix
vars_with_potential_year_suffix <- paket2_data %>%
    filter(str_detect(tolower(original_variable), "_\\\\d{4}$")) %>%
    mutate(
        year_from_original_variable = as.integer(str_extract(tolower(original_variable), "(?<=_)(\\\\d{4})$"))
    )

if (nrow(vars_with_potential_year_suffix) > 0) {
    print(paste("Found", nrow(vars_with_potential_year_suffix), "rows where original_variable ends with _YYYY."))

    # Check if the 'year' column matches the year extracted from original_variable
    mismatches <- vars_with_potential_year_suffix %>%
        filter(year != year_from_original_variable)

    if (nrow(mismatches) == 0) {
        print("SUCCESS: For all variables ending in _YYYY, the 'year' column correctly matches the year from the variable name.")
    } else {
        print(paste("ERROR: Found", nrow(mismatches), "mismatches where 'year' column does not match year from original_variable suffix."))
        print("Sample of mismatches:")
        print(head(mismatches %>% select(AGS, year, original_variable, year_from_original_variable, technology_group)))
    }

    # Sanity check: display some rows where year was potentially overridden
    print("Sample of rows where year might have been taken from variable name suffix:")
    print(head(vars_with_potential_year_suffix %>% select(AGS, year, original_variable, year_from_original_variable, technology_group)))
} else {
    print("No original_variables ending with _YYYY found in Paket 2 output.")
    print("This means either no such variables existed, or the year override logic was not triggered/needed for this pattern.")
}

# General check for NA in the year column
na_year_count <- sum(is.na(paket2_data$year))
if (na_year_count == 0) {
    print("SUCCESS: No NA values found in the 'year' column for Paket 2 data.")
} else {
    print(paste("ERROR: Found", na_year_count, "NA values in the 'year' column for Paket 2 data."))
}

print("Distinct years in Paket 2 data:")
print(distinct(paket2_data, year) %>% arrange(year))

print("Verification for Paket 2 output complete.")
