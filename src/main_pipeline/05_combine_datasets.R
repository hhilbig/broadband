library(tidyverse)
library(stringr)
library(here)

# Define file paths
file_p1 <- here("output", "broadband_gemeinde_paket_1_long.csv")
file_p2 <- here("output", "broadband_gemeinde_paket_2_long.csv")
file_p3 <- here("output", "broadband_gemeinde_paket_3_long.csv")

output_file_combined <- here("output", "broadband_gemeinde_combined_long.csv")

# Function to load, check, and prepare a single dataset
load_and_check_paket_data <- function(file_path, paket_name) {
    print(paste("--- Processing", paket_name, "---"))
    if (!file.exists(file_path)) {
        print(paste("File not found:", file_path, "Skipping this paket."))
        return(NULL)
    }

    data <- read_csv(file_path, show_col_types = FALSE)
    print(paste("Loaded", nrow(data), "rows from", basename(file_path)))

    # Ensure AGS is character
    data <- data %>% mutate(AGS = as.character(AGS))

    # Filter for fixed-line technologies (exclude mobile)
    # Paket 3 is already filtered during its processing, but doing it again won't harm
    # and ensures consistency if P1/P2 processing missed something.
    rows_before_mobile_filter <- nrow(data)
    data <- data %>%
        filter(!str_detect(tolower(technology_group), "mobil"))
    rows_after_mobile_filter <- nrow(data)
    if (rows_before_mobile_filter != rows_after_mobile_filter) {
        print(paste("Filtered out", rows_before_mobile_filter - rows_after_mobile_filter, "rows identified as mobile technologies."))
    }

    if (nrow(data) == 0) {
        print("No data remaining after mobile filter.")
        return(NULL)
    }

    # AGS Format Check (length 8)
    # Previous scripts should have padded and filtered, this is a verification
    ags_format_issues <- data %>%
        filter(nchar(AGS) != 8 | is.na(AGS))
    if (nrow(ags_format_issues) == 0) {
        print("AGS Format Check: SUCCESS. All AGS are 8 digits.")
    } else {
        print(paste("AGS Format Check: ERROR. Found", nrow(ags_format_issues), "AGS entries not 8 digits long or NA."))
        # print("Sample of AGS format issues:")
        # print(head(ags_format_issues %>% select(AGS, original_variable, year)))
    }

    # Duplicate Metric Check
    # Checking for cases where the same AGS, year, tech_group, speed results in multiple distinct values or original_variables
    duplicate_metrics <- data %>%
        group_by(AGS, year, technology_group, speed_mbps_gte) %>%
        summarise(n_rows = n(), n_distinct_values = n_distinct(value), .groups = "drop") %>%
        filter(n_rows > 1) # If n_rows > 1, it means multiple original_variables mapped here OR same var had multiple values (less likely after distinct in individual scripts)

    if (nrow(duplicate_metrics) == 0) {
        print("Duplicate Metric Check: SUCCESS. No single metric (AGS-year-tech-speed) has multiple differing rows/values.")
    } else {
        print(paste(
            "Duplicate Metric Check: WARNING. Found", nrow(duplicate_metrics),
            "AGS-year-tech-speed combinations that appear in multiple rows (likely from different original_variables or needing value aggregation)."
        ))
        # print("Sample of duplicate metrics (showing the group counts):")
        # print(head(duplicate_metrics))
        # To see actual data: data %>% semi_join(head(duplicate_metrics), by=c("AGS", "year", "technology_group", "speed_mbps_gte")) %>% arrange(AGS, year, technology_group, speed_mbps_gte, original_variable) %>% print(n=20)
    }

    # Add source paket column
    data <- data %>% mutate(source_paket = paket_name)

    # Select and ensure types for common columns to avoid bind_rows issues
    # Ensure 'value' is numeric. If it was 'value_raw' or similar and already character, this handles it.
    # Ensure 'data_category' exists, even if NA, for consistent schema.
    if (!("data_category" %in% colnames(data))) {
        data$data_category <- NA_character_
    }

    data <- data %>%
        mutate(value = as.numeric(str_replace(as.character(value), ",", "."))) %>% # Handle commas as decimal and ensure character first
        select(
            AGS,
            year,
            data_category,
            technology_group,
            speed_mbps_gte,
            value,
            original_variable,
            source_paket
        )

    print(paste("Finished processing for", paket_name, ". Rows to combine:", nrow(data)))
    return(data)
}

# Load and check each dataset
data_p1 <- load_and_check_paket_data(file_p1, "Paket 1")
data_p2 <- load_and_check_paket_data(file_p2, "Paket 2")
data_p3 <- load_and_check_paket_data(file_p3, "Paket 3")

# Combine datasets
all_data_list <- list(data_p1, data_p2, data_p3)
# Filter out NULLs if any file was not found or empty after filtering
all_data_list_filtered <- all_data_list[!sapply(all_data_list, is.null)]

if (length(all_data_list_filtered) == 0) {
    print("No data to combine. Exiting.")
} else {
    combined_data <- bind_rows(all_data_list_filtered)
    print(paste("--- Combined Data --- "))
    print(paste("Total rows before final distinct:", nrow(combined_data)))

    # Ensure consistent data types for key columns before distinct, esp. for numeric ones
    combined_data <- combined_data %>%
        mutate(
            speed_mbps_gte = as.integer(speed_mbps_gte),
            value = as.numeric(value),
            year = as.integer(year)
        )

    # Perform a final distinct operation
    # distinct() keeps all columns by default, ensuring row uniqueness
    final_data <- combined_data %>% distinct()
    print(paste("Total rows after final distinct:", nrow(final_data)))

    # Summary of the final dataset
    print("Summary of combined dataset:")
    print(paste("Number of unique AGS:", n_distinct(final_data$AGS)))
    print("Range of years:")
    print(range(final_data$year, na.rm = TRUE))
    print("Distinct years present:")
    print(final_data %>% count(year, sort = TRUE))
    print("Data categories present:")
    print(final_data %>% count(data_category, sort = TRUE))
    print("Source Pakets contribution:")
    print(final_data %>% count(source_paket, sort = TRUE))

    # Glimpse of final data
    print("Glimpse of final combined data:")
    glimpse(final_data)
    print("Sample of final combined data:")
    print(head(final_data))

    # Save the combined dataset
    write_csv(final_data, output_file_combined)
    print(paste("Saved combined dataset to:", output_file_combined))

    # --- Additional Summaries of Unique Values ---
    print("--- Unique Values Summaries for Relevant Columns ---")

    # Technology Group
    print("Unique technology_group values and their counts (top 20):")
    print(final_data %>% count(technology_group, sort = TRUE, name = "count_tech_group"))

    # Speed Mbps GTE
    print("Unique speed_mbps_gte values and their counts:")
    print(final_data %>% count(speed_mbps_gte, sort = TRUE, name = "count_speed"))

    # Original Variable
    print(paste("Number of unique original_variable names:", n_distinct(final_data$original_variable)))
    print("Sample of unique original_variable names (first 20 sorted):")
    print(final_data %>% distinct(original_variable) %>% arrange(original_variable) %>% head(20))
}

print("--- Script Finished ---")
