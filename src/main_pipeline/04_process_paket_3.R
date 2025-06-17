library(tidyverse)
library(readxl) # Not strictly needed for CSVs but often loaded with tidyverse
library(stringr)
library(here)

# --- Helper Functions ---

extract_year_from_filename <- function(filename) {
    # Try to extract a 4-digit year preceded by an underscore or at the start of a block
    # e.g., _2019_ or _2019. or 2019_
    year_match <- str_extract(filename, "(?<=[_.-])(200[5-9]|201[0-9]|202[0-4])(?=[_.-])|(^200[5-9]|201[0-9]|202[0-4])(?=[_.-])|(?<=[_.-])(200[5-9]|201[0-9]|202[0-4])$")
    if (!is.na(year_match)) {
        return(as.integer(year_match))
    }

    # Fallback for names like "some_name_2019_extra.csv" or "prefix2019suffix.ext"
    # This tries to find a 4-digit number starting with 20xx if the previous didn't catch it.
    year_match_general <- str_extract(filename, "(?<!\\d)(200[5-9]|201[0-9]|202[0-4])(?!\\d)")
    if (!is.na(year_match_general)) {
        return(as.integer(year_match_general))
    }

    # Fallback for "ende" or "mitte" followed by two digits (e.g., ende18) - less likely for Paket 3 but keep as safety
    year_match_short <- str_match(tolower(filename), "(?:ende|mitte)(\\d{2})")
    if (!is.na(year_match_short[1, 2])) {
        return(as.integer(paste0("20", year_match_short[1, 2])))
    }
    return(NA_integer_)
}

determine_data_category <- function(filename) {
    filename_lower <- tolower(filename)
    if (str_detect(filename_lower, "privat")) {
        return("privat")
    } else if (str_detect(filename_lower, "gewerbe_gwg|gew_")) { # Catches gewerbe_gwg and gew_
        return("gewerbe")
    } else if (str_detect(filename_lower, "gewerbe")) { # General gewerbe if not gwg
        return("gewerbe")
    } else if (str_detect(filename_lower, "mobilfunk")) {
        return("mobilfunk")
    }
    return(NA_character_)
}

find_ags_column_name <- function(col_names) {
    col_names_lower <- tolower(col_names)
    # Adding "kennziffer" as seen in some other contexts, and common AGS related terms
    ags_patterns <- c("^ags$", "^gemeindeschluessel$", "^gemeindeschlüssel$", "^gem$", "^kennziffer$")
    for (pattern in ags_patterns) {
        match_idx <- str_which(col_names_lower, pattern)
        if (length(match_idx) > 0) {
            return(col_names[match_idx[1]]) # Return the original case name
        }
    }
    return(NA_character_)
}

parse_broadband_variable <- function(variable_name) {
    # No year extraction from variable for Paket 3 initially, assuming year comes from filename
    year_in_var <- NA_integer_

    # Regex for modern names like "Technology Name ≥ 100 Mbit/s" or "Technology Name  100 Mbit/s"
    # This is the primary pattern expected in Paket 3 CSVs based on inspection.
    match_modern <- str_match(variable_name, "^([a-zA-ZäöüÄÖÜß\\.\\s/()-]+?)(?:\\s*≥\\s*|\\s+)(\\d+)\\s+Mbit/s$")
    if (!is.na(match_modern[1, 1])) {
        technology <- str_trim(match_modern[1, 2])
        # Normalize FTTH/B
        if (tolower(technology) == "ftth/b") technology <- "FTTH/B"
        speed <- as.integer(match_modern[1, 3])
        return(tibble(technology_group = technology, speed_mbps_gte = speed, year_from_variable = year_in_var))
    }

    # Add specific handling for Mobilfunk columns if they don't fit the Mbit/s pattern
    # Example: "LTE" or "5G" - these might not have explicit Mbit/s in the name
    # For now, mobilfunk columns that don't match Mbit/s will be NA for speed.
    # We can add rules here if specific mobilfunk column names need parsing without speed.
    # e.g. if (tolower(variable_name) == "lte") return(tibble(technology_group = "LTE", speed_mbps_gte = NA_integer_, year_from_variable = year_in_var))


    # Fallback if no pattern matches
    return(tibble(technology_group = variable_name, speed_mbps_gte = NA_integer_, year_from_variable = year_in_var))
}

# --- Core Processing Function for a Single CSV File ---
process_csv_file_paket3 <- function(file_path_full, year_val, data_cat) {
    print(paste("Processing:", basename(file_path_full)))

    raw_data <- NULL
    tryCatch(
        {
            # Try with semicolon delimiter first, common in German CSVs
            raw_data <- read_csv2(file_path_full, show_col_types = FALSE, locale = locale(encoding = "UTF-8"))
            if (ncol(raw_data) <= 1 && nrow(raw_data) > 0) { # Check if parsing failed (e.g. wrong delimiter)
                message(paste("  Trying comma delimiter for CSV:", basename(file_path_full)))
                raw_data <- read_csv(file_path_full, show_col_types = FALSE, locale = locale(encoding = "UTF-8"))
            }
        },
        error = function(e_utf8) {
            message(paste("  Error reading CSV with UTF-8 (", basename(file_path_full), "):", e_utf8$message))
            tryCatch(
                {
                    message(paste("  Trying latin1 encoding for CSV:", basename(file_path_full)))
                    raw_data <- read_csv2(file_path_full, show_col_types = FALSE, locale = locale(encoding = "latin1"))
                    if (ncol(raw_data) <= 1 && nrow(raw_data) > 0) {
                        message(paste("  Trying comma delimiter with latin1 for CSV:", basename(file_path_full)))
                        raw_data <- read_csv(file_path_full, show_col_types = FALSE, locale = locale(encoding = "latin1"))
                    }
                },
                error = function(e_latin1) {
                    message(paste("  Failed to read CSV with latin1 as well (", basename(file_path_full), "):", e_latin1$message))
                    return(NULL)
                }
            )
        }
    )

    if (is.null(raw_data) || nrow(raw_data) == 0) {
        message(paste("  No data read or empty file for:", basename(file_path_full)))
        return(NULL)
    }

    original_colnames <- colnames(raw_data)
    ags_col_name_orig <- find_ags_column_name(original_colnames)

    if (is.na(ags_col_name_orig)) {
        message(paste("  AGS column not found in:", basename(file_path_full)))
        message(paste("    Available columns:", paste(head(original_colnames, 10), collapse = ", ")))
        return(NULL)
    }

    # Minimal name cleaning, then select AGS and pivot
    clean_colnames <- make.names(original_colnames, unique = TRUE)
    colnames(raw_data) <- clean_colnames
    names_map <- setNames(original_colnames, clean_colnames)
    ags_col_name_clean <- names(names_map)[which(names_map == ags_col_name_orig)]
    if (length(ags_col_name_clean) == 0) ags_col_name_clean <- NA_character_


    if (is.na(ags_col_name_clean) || !(ags_col_name_clean %in% colnames(raw_data))) {
        message(paste("  AGS column ('", ags_col_name_orig, "' -> '", ags_col_name_clean, "') not found after cleaning or invalid for file:", basename(file_path_full)))
        return(NULL)
    }

    raw_data <- raw_data %>%
        mutate(!!sym(ags_col_name_clean) := as.character(!!sym(ags_col_name_clean)))

    long_data <- raw_data %>%
        rename(AGS = !!sym(ags_col_name_clean)) %>%
        select(AGS, everything()) %>%
        pivot_longer(
            cols = -AGS,
            names_to = "variable_raw_clean",
            values_to = "value_raw",
            values_transform = list(value_raw = as.character)
        ) %>%
        mutate(
            year = year_val,
            data_category_file = data_cat, # data_category from filename
            variable_original = names_map[variable_raw_clean]
        ) %>%
        filter(!is.na(variable_original)) # Filter out any columns that were not in names_map (should not happen with everything())

    if (nrow(long_data) == 0) {
        message(paste("  No data after pivot for file:", basename(file_path_full)))
        return(NULL)
    }

    # Parse unique original variable names
    unique_vars_to_parse <- tibble(variable_original = unique(long_data$variable_original))

    parsed_vars_map <- unique_vars_to_parse %>%
        mutate(parsed_components = map(variable_original, parse_broadband_variable)) %>%
        unnest(parsed_components)

    long_data_with_parsed_vars <- left_join(long_data, parsed_vars_map, by = "variable_original")

    processed_data <- long_data_with_parsed_vars %>%
        # Year from variable is NA for Paket 3 initial setup, so year column is already correct from year_val
        select(AGS, year, data_category = data_category_file, technology_group, speed_mbps_gte, value = value_raw, original_variable = variable_original) %>%
        mutate(
            # Basic cleaning for value column before numeric conversion
            value_cleaned = str_replace_all(value, "[^0-9.,-]", ""), # Keep digits, comma, dot, minus
            value_cleaned = str_replace(value_cleaned, ",", "."),
            value = suppressWarnings(as.numeric(value_cleaned)) # Suppress warnings for NAs by coercion
        ) %>%
        filter(!is.na(value), !is.na(AGS), str_length(AGS) > 0, !is.na(year)) %>%
        mutate(AGS = str_pad(AGS, 8, pad = "0")) %>%
        filter(str_length(AGS) == 8)


    return(processed_data)
}


# --- Main Script Logic ---

print("Starting processing for Paket 3 CSV files...")

data_base_path_paket3 <- here("data", "Paket_3")
output_dir <- here("output")
if (!dir.exists(output_dir)) {
    dir.create(output_dir)
}

all_csv_files_paket3 <- list.files(
    path = data_base_path_paket3,
    pattern = "\\.csv$",
    recursive = TRUE, # Though Paket 3 structure is flat, this is safer
    full.names = TRUE
)
all_csv_files_paket3 <- all_csv_files_paket3[!str_starts(basename(all_csv_files_paket3), "~\\$")] # Exclude temp files

# Filter for gemeinde level files (excluding 'bezirke' for now)
gemeinde_files_paket3 <- all_csv_files_paket3[
    str_detect(tolower(basename(all_csv_files_paket3)), "^gemeinde_") &
        !str_detect(tolower(basename(all_csv_files_paket3)), "_bezirke_")
]

if (length(gemeinde_files_paket3) == 0) {
    print("No 'gemeinde' level CSV files found in Paket 3 matching criteria.")
} else {
    print(paste("Found", length(gemeinde_files_paket3), "'gemeinde' level CSV files to process from Paket 3."))

    all_processed_paket3_data <- list()

    for (file_path in gemeinde_files_paket3) {
        file_basename <- basename(file_path)

        year_extracted <- extract_year_from_filename(file_basename)
        category_extracted <- determine_data_category(file_basename)

        if (is.na(year_extracted)) {
            message(paste("  Skipping file, could not extract year:", file_basename))
            next
        }
        if (is.na(category_extracted) || category_extracted != "privat") { # Focus only on privat files
            message(paste("  Skipping file, not 'privat' category or category undetermined:", file_basename))
            next
        }
        if (str_detect(tolower(file_basename), "_stats")) {
            message(paste("  Skipping file, contains '_stats':", file_basename))
            next
        }

        print(paste("Processing file:", file_basename, "| Year:", year_extracted, "| Category:", category_extracted))

        processed_tibble <- process_csv_file_paket3(file_path, year_extracted, category_extracted)

        if (!is.null(processed_tibble) && nrow(processed_tibble) > 0) {
            all_processed_paket3_data[[length(all_processed_paket3_data) + 1]] <- processed_tibble
        } else {
            message(paste("  No data returned after processing file:", file_basename))
        }
    }

    if (length(all_processed_paket3_data) > 0) {
        final_paket3_df <- bind_rows(all_processed_paket3_data)

        # Final cleanup and type enforcement
        final_paket3_df <- final_paket3_df %>%
            filter(!is.na(AGS), !is.na(year), !is.na(value)) %>%
            mutate(
                AGS = str_pad(AGS, 8, pad = "0"),
                speed_mbps_gte = as.integer(speed_mbps_gte)
            ) %>%
            filter(str_length(AGS) == 8) %>%
            distinct()

        # Save the final combined data for Paket 3
        output_file_rds <- here("output", "broadband_gemeinde_paket_3_long.rds")
        saveRDS(final_paket3_df, file = output_file_rds)

        print(paste("Successfully processed Paket 3. Final data has", nrow(final_paket3_df), "rows."))
        print(paste("Saved combined Paket 3 data to:", output_file_rds))
    } else {
        print("No data was processed from Paket 3.")
    }
}

print("Finished processing for Paket 3.")
