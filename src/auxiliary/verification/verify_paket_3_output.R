library(tidyverse)
library(stringr)
library(here)

# Load the processed Paket 3 data
paket3_data_file <- here("output", "broadband_gemeinde_paket_3_long.csv")
if (!file.exists(paket3_data_file)) {
    stop(paste("Paket 3 output file not found:", paket3_data_file, "
Please run process_paket_3.R first."))
}

paket3_data <- read_csv(paket3_data_file, show_col_types = FALSE)

print(paste("Loaded", nrow(paket3_data), "rows from", basename(paket3_data_file)))

# 1. Verify that only 'privat' data_category is present
non_privat_categories <- paket3_data %>%
    filter(tolower(data_category) != "privat") %>%
    distinct(data_category)

if (nrow(non_privat_categories) == 0) {
    print("SUCCESS: All rows in Paket 3 output have data_category as 'privat'.")
} else {
    print("ERROR: Found data_categories other than 'privat' in Paket 3 output:")
    print(non_privat_categories)
}

# 2. Verify that no 'mobil' technology_group is present
mobil_technologies <- paket3_data %>%
    filter(str_detect(tolower(technology_group), "mobil")) %>%
    distinct(technology_group, original_variable)

if (nrow(mobil_technologies) == 0) {
    print("SUCCESS: No technology_groups containing 'mobil' found in Paket 3 output.")
} else {
    print("ERROR: Found technology_groups containing 'mobil' in Paket 3 output:")
    print(mobil_technologies)
}

# 3. General check for NA in the year column
na_year_count <- sum(is.na(paket3_data$year))
if (na_year_count == 0) {
    print("SUCCESS: No NA values found in the 'year' column for Paket 3 data.")
} else {
    print(paste("ERROR: Found", na_year_count, "NA values in the 'year' column for Paket 3 data."))
}

# 4. Check distinct years and their counts
print("Distinct years and their counts in Paket 3 data:")
print(paket3_data %>% count(year) %>% arrange(year))

# 5. Check for any remaining unparsed/unexpected technology groups (where speed is NA)
# These should ideally be non-speed related columns that are intentionally NA for speed.
remaining_na_speed_tech <- paket3_data %>%
    filter(is.na(speed_mbps_gte)) %>%
    count(technology_group, original_variable, sort = TRUE)

if (nrow(remaining_na_speed_tech) > 0) {
    print("INFO: Technology groups with NA for speed_mbps_gte (expected for non-speed metrics):")
    print(remaining_na_speed_tech, n = 20)
} else {
    print("SUCCESS: No technology groups with NA for speed_mbps_gte found (or all were filtered out).")
}


print("Verification for Paket 3 output complete.")
