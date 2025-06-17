library(tidyverse)
library(stringr)
library(here)

# Define file paths for the processed long-format data from each Paket
paket1_file <- here("output", "broadband_gemeinde_paket_1_long.rds")
paket2_file <- here("output", "broadband_gemeinde_paket_2_long.rds")
paket3_file <- here("output", "broadband_gemeinde_paket_3_long.rds")

# Define the output file path for the combined data
output_file <- here("output", "broadband_gemeinde_combined_long.rds")

# Function to load, check, and prepare a single dataset
load_and_check_paket_data <- function(file_path, paket_name) {
    print(paste("--- Loading and Checking", paket_name, "---"))
    if (!file.exists(file_path)) {
        warning(paste("File not found for", paket_name, "at:", file_path))
        return(NULL)
    }

    # Load data from .rds file
    paket_data <- readRDS(file_path)
    print(paste("Loaded", nrow(paket_data), "rows from", basename(file_path)))

    # Ensure AGS is a character vector for consistency
    if ("AGS" %in% colnames(paket_data)) {
        paket_data <- paket_data %>% mutate(AGS = as.character(AGS))
    } else {
        warning(paste("'AGS' column not found in", paket_name))
        return(NULL)
    }

    # Filter out mobile technologies as a final safeguard
    initial_rows <- nrow(paket_data)
    paket_data <- paket_data %>%
        filter(!str_detect(tolower(technology_group), "mobil"))
    rows_removed <- initial_rows - nrow(paket_data)
    if (rows_removed > 0) {
        print(paste("Removed", rows_removed, "rows identified as mobile technologies from", paket_name))
    }

    # AGS Format Check
    invalid_ags_rows <- paket_data %>%
        filter(is.na(AGS) | str_length(AGS) != 8)
    if (nrow(invalid_ags_rows) > 0) {
        warning(paste("Found", nrow(invalid_ags_rows), "rows with invalid AGS (NA or not 8 digits) in", paket_name, ". These will be filtered out."))
        print("Examples of invalid AGS rows:")
        print(head(invalid_ags_rows))
        paket_data <- paket_data %>%
            filter(!is.na(AGS), str_length(AGS) == 8)
    } else {
        print(paste("AGS format check passed for", paket_name, "(all are 8 digits and not NA)."))
    }

    # Duplicate Metric Check: Are there multiple values for the same metric?
    duplicate_metrics <- paket_data %>%
        group_by(AGS, year, technology_group, speed_mbps_gte) %>%
        summarise(n_rows = n(), .groups = "drop") %>%
        filter(n_rows > 1)

    if (nrow(duplicate_metrics) > 0) {
        warning(paste("Found", nrow(duplicate_metrics), "groups of duplicate metrics in", paket_name, "(same AGS, year, tech, speed). This may indicate varied 'original_variable' names parsing to the same metric."))
        print("Sample of duplicate metrics:")
        print(head(duplicate_metrics))
    } else {
        print(paste("Duplicate metric check passed for", paket_name, "(no identical AGS-year-tech-speed groups)."))
    }

    # Add source paket column
    paket_data$source_paket <- paket_name

    # Standardize column set and types
    paket_data <- paket_data %>%
        mutate(
            data_category = if ("data_category" %in% names(.)) as.character(data_category) else NA_character_,
            value = as.numeric(str_replace_all(as.character(value), ",", ".")),
            speed_mbps_gte = as.integer(speed_mbps_gte),
            year = as.integer(year)
        ) %>%
        select(
            AGS, year, data_category, technology_group,
            speed_mbps_gte, value, original_variable, source_paket
        )

    return(paket_data)
}

# Load data from each Paket using the helper function
paket1_data <- load_and_check_paket_data(paket1_file, "Paket 1")
paket2_data <- load_and_check_paket_data(paket2_file, "Paket 2")
paket3_data <- load_and_check_paket_data(paket3_file, "Paket 3")

# Combine all loaded data frames
# Ensure we only bind non-null data frames
data_list <- list(paket1_data, paket2_data, paket3_data)
data_list_non_null <- data_list[!sapply(data_list, is.null)]

if (length(data_list_non_null) == 0) {
    stop("No data was loaded from any of the Pakets. Halting script.")
}

print("--- Combining all Pakets ---")
combined_data <- bind_rows(data_list_non_null)

print(paste("Total rows before final distinct operation:", nrow(combined_data)))

# Final distinct operation to remove fully duplicated rows across the whole dataset
combined_data <- distinct(combined_data)

print(paste("Total rows after final distinct operation:", nrow(combined_data)))

# --- Final Summaries and Saving ---
print("--- Final Combined Dataset Summary ---")
print(paste("Number of unique AGS:", n_distinct(combined_data$AGS)))
print("Range of years and counts per year:")
print(table(combined_data$year))
print("Data categories present:")
print(table(combined_data$data_category, useNA = "ifany"))
print("Contribution of each source Paket:")
print(table(combined_data$source_paket))
print("Unique technology_group values and counts:")
print(combined_data %>% count(technology_group, sort = TRUE) %>% print(n = 20))
print("Unique speed_mbps_gte values and counts:")
print(table(combined_data$speed_mbps_gte, useNA = "ifany"))

# Save the final combined dataset to .rds
saveRDS(combined_data, file = output_file)

print(paste("Successfully combined all Paket data. Final dataset has", nrow(combined_data), "rows."))
print(paste("Saved final combined data to:", output_file))
