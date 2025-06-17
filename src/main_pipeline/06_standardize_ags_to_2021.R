library(tidyverse)
library(readxl)
library(here)

# --- Configuration ---
file_mergers_2000_2010 <- here("data", "muni_mergers", "ref-gemeinden-umrech-2021-2000-2010.xlsx")
file_mergers_2011_2020 <- here("data", "muni_mergers", "ref-gemeinden-umrech-2021-2011-2020.xlsx")

# Column names - these are PREDICTED based on inspection and user feedback.
# We will VERIFY these within process_merger_sheet by printing actual colnames.
# The \r\n might be read differently by R (e.g. as space or just \n).
# For constructing ags_hist_col_name, use sprintf for \r\n if R sees it, or adjust.
col_name_ags_2021_target <- "Gemeinden\r\n 31.12.2021" # As provided by user
col_name_pop_share_target <- "bevölkerungs- \r\nproportionaler \r\nUmsteige- \r\nschlüssel"

# Function to process a single merger sheet
process_merger_sheet <- function(file_path, sheet_name_year_str) {
    print(paste("Processing file:", basename(file_path), "- Sheet:", sheet_name_year_str))

    # Construct the expected historical AGS column name for this sheet
    # Using simple concatenation for now. If R reads \r\n literally, this needs adjustment.
    ags_hist_col_name_expected <- paste0("Gemeinden 31.12.", sheet_name_year_str) # Tentative: assuming \r\n becomes space
    # Alternative if \r\n is kept by R:
    # ags_hist_col_name_expected <- sprintf("Gemeinden\r\n 31.12.%s", sheet_name_year_str)

    # These Destatis files often have metadata at the top.
    # Common skip values are 4, 5, or 6. Let's try with a common skip and refine if needed.
    # For now, assume read_excel might get it or we read without skipping and then check.
    raw_sheet_data <- tryCatch(
        {
            read_excel(file_path, sheet = sheet_name_year_str, .name_repair = "minimal")
        },
        error = function(e) {
            message(paste("Error reading sheet:", sheet_name_year_str, "from", basename(file_path), ":", e$message))
            return(NULL)
        }
    )

    if (is.null(raw_sheet_data)) {
        return(NULL)
    }

    actual_colnames <- colnames(raw_sheet_data)
    print("Actual column names as read by R:")
    print(actual_colnames)

    # --- Dynamically find column indices based on partial matches or expected structure ---
    # This is safer than relying on exact matches of names with \r\n
    # Historical AGS: typically the first column containing "Gemeinden" and the sheet_name_year_str
    idx_ags_hist <- which(str_detect(actual_colnames, fixed(paste0("31.12.", sheet_name_year_str))) & str_detect(actual_colnames, "Gemeinden"))[1]

    # 2021 AGS: contains "Gemeinden" and "31.12.2021"
    idx_ags_2021 <- which(str_detect(actual_colnames, fixed("31.12.2021")) & str_detect(actual_colnames, "Gemeinden"))[1]

    # Population Share: contains "bevölkerungs-" and "proportionaler"
    idx_pop_share <- which(str_detect(tolower(actual_colnames), "bevölkerungs-") & str_detect(tolower(actual_colnames), "proportionaler"))[1]

    # Check if all columns were found
    if (is.na(idx_ags_hist) || is.na(idx_ags_2021) || is.na(idx_pop_share)) {
        message(paste("Could not find all required columns in sheet:", sheet_name_year_str, "of file:", basename(file_path)))
        message("Indices found: AGS_hist=", idx_ags_hist, ", AGS_2021=", idx_ags_2021, ", pop_share=", idx_pop_share)
        return(NULL)
    }

    print(paste(
        "Found columns: AGS_hist at index", idx_ags_hist, "(", actual_colnames[idx_ags_hist], ")",
        "; AGS_2021 at index", idx_ags_2021, "(", actual_colnames[idx_ags_2021], ")",
        "; pop_share at index", idx_pop_share, "(", actual_colnames[idx_pop_share], ")"
    ))

    processed_data <- raw_sheet_data %>%
        select(
            AGS_hist_raw = all_of(idx_ags_hist),
            AGS_2021_raw = all_of(idx_ags_2021),
            population_part_raw = all_of(idx_pop_share) # Renamed from pop_share_raw
        ) %>%
        # The first few rows might still be metadata if read_excel didn't skip, or column headers themselves
        # We need to ensure we are starting from actual data rows.
        # Heuristic: Data rows start when AGS_hist_raw looks like an AGS (numeric, potentially with NAs for totals)
        filter(!is.na(as.numeric(AGS_hist_raw)) | !is.na(as.numeric(AGS_2021_raw))) %>% # Keep if either AGS looks numeric
        mutate(
            AGS_hist_raw_num = as.numeric(AGS_hist_raw), # For grouping and calculations
            population_part = as.numeric(population_part_raw)
        ) %>%
        filter(!is.na(population_part)) %>% # Filter out rows where the population part is NA early
        group_by(AGS_hist_raw_num) %>% # Group by the raw historical AGS to sum parts
        mutate(total_population_for_AGS_hist = sum(population_part, na.rm = TRUE)) %>%
        ungroup() %>%
        mutate(
            AGS_hist = str_pad(as.character(AGS_hist_raw), 8, side = "left", pad = "0"),
            AGS_2021 = str_pad(as.character(AGS_2021_raw), 8, side = "left", pad = "0"),
            pop_share = ifelse(total_population_for_AGS_hist > 0, population_part / total_population_for_AGS_hist, 0),
            year_hist = as.integer(sheet_name_year_str)
        ) %>%
        select(AGS_hist, year_hist, AGS_2021, pop_share) %>%
        filter(!is.na(pop_share)) # Final filter, just in case (e.g. if population_part was NA initially)

    print(paste("Processed sheet", sheet_name_year_str, "- rows extracted:", nrow(processed_data)))
    if (nrow(processed_data) > 0) {
        print("Sample of processed data from this sheet:")
        print(head(processed_data))
    }
    return(processed_data)
}

# --- Main Script Logic ---
print("Starting AGS standardization to 2021 borders...")

# For testing the process_merger_sheet function with one sheet:
test_sheet_data <- process_merger_sheet(file_mergers_2000_2010, "2010")
test_sheet_data <- process_merger_sheet(file_mergers_2000_2010, "2005")

if (!is.null(test_sheet_data)) {
    print("Test run for 2010 sheet summary:")
    summary(test_sheet_data)
    print("Checking pop_share sums for test run (2010 sheet):")
    test_sheet_data %>%
        group_by(AGS_hist, year_hist) %>%
        summarise(total_pop_share = sum(pop_share, na.rm = TRUE), n_mappings = n(), .groups = "drop") %>%
        filter(total_pop_share < 0.99 | total_pop_share > 1.01 | (n_mappings > 1 & (total_pop_share < 0.99 | total_pop_share > 1.01))) %>%
        arrange(desc(abs(total_pop_share - 1))) %>%
        print(n = 20)
} else {
    print("Test run for 2010 sheet failed to produce data.")
}

# --- Build Master Crosswalk ---
print("--- Building Master Crosswalk (2005-2020) ---")
all_crosswalk_data <- list()
years_to_process <- 2005:2020 # Define the range of historical years needed for your broadband data

for (year_val in years_to_process) {
    year_str <- as.character(year_val)
    current_file <- NA

    if (year_val >= 2000 && year_val <= 2010) {
        current_file <- file_mergers_2000_2010
    } else if (year_val >= 2011 && year_val <= 2020) {
        current_file <- file_mergers_2011_2020
    }

    if (!is.na(current_file)) {
        sheet_data <- process_merger_sheet(current_file, year_str)
        if (!is.null(sheet_data) && nrow(sheet_data) > 0) {
            all_crosswalk_data[[length(all_crosswalk_data) + 1]] <- sheet_data
        }
    } else {
        message(paste("No crosswalk file defined for year:", year_val))
    }
}

master_crosswalk <- NULL
if (length(all_crosswalk_data) > 0) {
    master_crosswalk <- bind_rows(all_crosswalk_data)
    print(paste("Master crosswalk built with", nrow(master_crosswalk), "rows."))
    print("Summary of master_crosswalk:")
    summary(master_crosswalk)
    glimpse(master_crosswalk)

    print("--- Validating pop_share sums in Master Crosswalk ---")
    pop_share_validation <- master_crosswalk %>%
        group_by(AGS_hist, year_hist) %>%
        summarise(total_pop_share = sum(pop_share, na.rm = TRUE), n_rows_per_ags_hist_year = n(), .groups = "drop")

    problematic_shares <- pop_share_validation %>%
        filter(total_pop_share < 0.99 | total_pop_share > 1.01)
    # Only show problematic if it's a split (n_rows > 1) OR if it's 1:1 but share is not ~1.
    # If n_rows == 1, total_pop_share should be very close to 1.0 (or 0 if fully dissolved, but pop_share is NA then)

    if (nrow(problematic_shares) > 0) {
        print(paste("WARNING: Found", nrow(problematic_shares), "AGS_hist/year_hist combinations where sum of pop_share is not ~1.0 (outside 0.99-1.01 range). Review these:"))
        print(problematic_shares %>% arrange(year_hist, AGS_hist) %>% head(50))
    } else {
        print("Pop_share sums validation: All AGS_hist/year_hist combinations have pop_share sums within the 0.99-1.01 range.")
    }
} else {
    print("No data compiled into master_crosswalk. Stopping.")
    stop("Master crosswalk generation failed.")
}

# --- Load Broadband Data ---
print("--- Loading Combined Broadband Data ---")
broadband_file <- here("output", "broadband_gemeinde_combined_long.csv")
if (!file.exists(broadband_file)) {
    stop(paste("Broadband data file not found:", broadband_file))
}
broadband_data <- read_csv(broadband_file, show_col_types = FALSE)

table(broadband_data$year)

print(paste("Loaded", nrow(broadband_data), "rows from", basename(broadband_file)))

# Ensure AGS and year in broadband_data are of correct types for joining
broadband_data <- broadband_data %>%
    mutate(
        AGS = as.character(AGS),
        year = as.integer(year)
    )

# --- Join Broadband Data with Master Crosswalk ---
print("--- Joining Broadband Data with Master Crosswalk ---")
# Rename columns in master_crosswalk to avoid clashes and be clear
crosswalk_renamed <- master_crosswalk %>%
    rename(AGS_hist_cw = AGS_hist, year_hist_cw = year_hist)

# Perform the join
# An AGS in broadband_data might not be in the crosswalk if it didn't change
# or if it's from a year outside the crosswalk's range (e.g. > 2020).
# We need to handle these cases: if AGS_hist is not in crosswalk for that year,
# it means it maps 1:1 to itself with AGS_2021 = AGS_hist and pop_share = 1.

# Identify AGS-year combinations in broadband data that are *not* in the crosswalk
# These are assumed to be 1:1 mappings to themselves in 2021 terms for those years.
broadband_ags_years <- broadband_data %>% distinct(AGS, year)
crosswalk_ags_years <- crosswalk_renamed %>% distinct(AGS_hist_cw, year_hist_cw)

ags_not_in_crosswalk <- broadband_ags_years %>%
    anti_join(crosswalk_ags_years, by = c("AGS" = "AGS_hist_cw", "year" = "year_hist_cw"))

if (nrow(ags_not_in_crosswalk) > 0) {
    print(paste("Found", nrow(ags_not_in_crosswalk), "AGS-year combinations in broadband data not in crosswalk. Assuming 1:1 mapping."))
    # Create a supplementary crosswalk for these cases
    supplementary_crosswalk <- ags_not_in_crosswalk %>%
        mutate(
            AGS_hist_cw = AGS,
            year_hist_cw = year,
            AGS_2021 = AGS,
            pop_share = 1.0
        ) %>%
        select(AGS_hist_cw, year_hist_cw, AGS_2021, pop_share)

    # Add to the main crosswalk
    crosswalk_for_join <- bind_rows(crosswalk_renamed, supplementary_crosswalk)
} else {
    print("All AGS-year combinations in broadband data are covered by the generated crosswalk or do not require changes.")
    crosswalk_for_join <- crosswalk_renamed
}

# Now join broadband data with the (potentially augmented) crosswalk
joined_data <- broadband_data %>%
    left_join(crosswalk_for_join, by = c("AGS" = "AGS_hist_cw", "year" = "year_hist_cw"))

# Check for rows that didn't get a match (should not happen if supplementary_crosswalk logic is correct)
# or where AGS_2021 or pop_share became NA after join.
missing_join_info <- joined_data %>% filter(is.na(AGS_2021) | is.na(pop_share))
if (nrow(missing_join_info) > 0) {
    print(paste("WARNING:", nrow(missing_join_info), "rows had missing AGS_2021 or pop_share after join. This might indicate an issue."))
    print("Sample of rows with missing join info:")
    print(head(missing_join_info))
    # For now, we might want to assign AGS_2021 = AGS and pop_share = 1 for these as a fallback if they are truly stable
    # However, the supplementary_crosswalk should have handled this.
    # Let's investigate if this warning appears.
    # A more robust way: if AGS_2021 is NA, it means the original AGS was not in crosswalk_for_join.
    # This implies an issue with the supplementary_crosswalk creation if it occurs for AGS within 2005-2020.
    # If year is > 2020, they are expected to be 1:1 and AGS_2021 = AGS, pop_share = 1.
    joined_data <- joined_data %>%
        mutate(
            AGS_2021 = ifelse(is.na(AGS_2021), AGS, AGS_2021),
            pop_share = ifelse(is.na(pop_share), 1.0, pop_share)
        )
    print("Applied fallback for rows with missing join info: AGS_2021 set to original AGS, pop_share to 1.0")
} else {
    print("Join successful. All rows have AGS_2021 and pop_share.")
}


# --- Apportion and Aggregate Data to AGS_2021 ---
print("--- Apportioning and Aggregating Data to AGS_2021 ---")

standardized_data <- joined_data %>%
    mutate(weighted_value = value * pop_share) %>%
    group_by(AGS_2021, year, data_category, technology_group, speed_mbps_gte) %>%
    summarise(
        value = sum(weighted_value, na.rm = TRUE),
        # Concatenate unique original_variable and source_paket, sorted, semicolon-separated
        original_variable = paste(sort(unique(original_variable)), collapse = "; "),
        source_paket = paste(sort(unique(source_paket)), collapse = "; "),
        n_agg = n(), # Number of original rows aggregated into this new row
        .groups = "drop"
    ) %>%
    rename(AGS = AGS_2021) # Rename to standard AGS column name

# Ensure the new 'value' (coverage) is capped at 100 if any sums slightly exceed due to floating points.
standardized_data <- standardized_data %>%
    mutate(value = ifelse(value > 100, 100, value))

print(paste("Standardized data has", nrow(standardized_data), "rows."))
print("Summary of standardized_data:")
summary(standardized_data)
glimpse(standardized_data)

# --- Save Standardized Data ---
output_file_standardized <- here("output", "broadband_gemeinde_combined_long_ags2021.csv")
write_csv(standardized_data, output_file_standardized)
print(paste("Saved AGS 2021 standardized data to:", output_file_standardized))

print("AGS standardization script finished.")
