library(tidyverse)
library(readxl)
library(stringr)
library(here)

# --- Helper Functions ---

find_ags_column_name <- function(col_names) {
    col_names_lower <- tolower(col_names)
    ags_patterns <- c("^ags$", "^gemeindeschluessel$", "^gemeindeschlüssel$", "^gem$")
    for (pattern in ags_patterns) {
        match_idx <- str_which(col_names_lower, pattern)
        if (length(match_idx) > 0) {
            return(col_names[match_idx[1]])
        }
    }
    return(NA)
}

parse_broadband_variable <- function(variable_name) {
    # Attempt to extract year from variable name first, e.g., verf_300_50_2010 -> 2010
    year_in_var <- NA_integer_
    year_match_in_var <- str_match(tolower(variable_name), "_(\\d{4})$") # Matches _YYYY at the end
    if (!is.na(year_match_in_var[1, 2])) {
        year_in_var <- as.integer(year_match_in_var[1, 2])
        # Remove year from variable_name for further parsing if needed, e.g., "verf_300_50_2010" -> "verf_300_50"
        variable_name_no_year <- str_replace(tolower(variable_name), "_\\d{4}$", "")
    } else {
        variable_name_no_year <- tolower(variable_name)
    }

    # Regex for modern names like "Technology Name ≥ 100 Mbit/s" or "Technology Name  100 Mbit/s"
    # Uses variable_name_no_year if year was stripped, otherwise original variable_name
    # This pattern does not typically have embedded years that need stripping for this regex.
    match_modern <- str_match(variable_name, "^([a-zA-ZäöüÄÖÜß\\.\\s/]+?)(?:\\s*≥\\s*|\\s+)(\\d+)\\s+Mbit/s$")
    if (!is.na(match_modern[1, 1])) {
        technology <- str_trim(match_modern[1, 2])
        speed <- as.integer(match_modern[1, 3])
        return(tibble(technology_group = technology, speed_mbps_gte = speed, year_from_variable = year_in_var))
    }

    # Regex for historical verf_XXX_YY names (e.g., verf_100_30)
    # Uses variable_name_no_year to parse columns like "verf_300_50" after year is stripped
    match_hist_verf <- str_match(variable_name_no_year, "^verf_(\\d{3})_(\\d+)")
    if (!is.na(match_hist_verf[1, 1])) {
        group_code <- match_hist_verf[1, 2]
        speed <- as.integer(match_hist_verf[1, 3])
        technology <- case_when(
            group_code == "100" ~ "leitungsg. Technologien (hist)",
            group_code == "200" ~ "mobile Technologien (hist)",
            group_code == "300" ~ "alle Technologien (hist)",
            TRUE ~ paste0("hist_verf_", group_code)
        )
        return(tibble(technology_group = technology, speed_mbps_gte = speed, year_from_variable = year_in_var))
    }

    # Regex for historical tech_YY names (e.g., DSL_16, CATV_400)
    # Uses variable_name_no_year for consistency, though this pattern also doesn't usually embed _YYYY
    match_hist_tech <- str_match(variable_name_no_year, "^(dsl|catv|ftthb|fttb)_(\\d+)")
    if (!is.na(match_hist_tech[1, 1])) {
        technology_raw <- match_hist_tech[1, 2]
        speed <- as.integer(match_hist_tech[1, 3])
        technology <- case_when(
            technology_raw == "dsl" ~ "DSL (hist)",
            technology_raw == "catv" ~ "CATV (hist)",
            technology_raw == "ftthb" ~ "FTTH/B (hist)",
            technology_raw == "fttb" ~ "FTTB (hist)",
            TRUE ~ paste0("hist_tech_", technology_raw)
        )
        return(tibble(technology_group = technology, speed_mbps_gte = speed, year_from_variable = year_in_var))
    }

    # Regex for verf_dsl (>=128 kbit/s) from 2005-2008 files
    if (variable_name_no_year == "verf_dsl") {
        return(tibble(technology_group = "DSL (hist)", speed_mbps_gte = 0.128, year_from_variable = year_in_var))
    }

    # Fallback if no pattern matches
    return(tibble(technology_group = variable_name, speed_mbps_gte = NA_integer_, year_from_variable = year_in_var))
}

extract_year_for_sheet <- function(sheet_name, file_name_base) {
    # Priority 1: Try common patterns from sheet name
    year_match_sheet_direct <- str_extract(sheet_name, "\\b(200[5-9]|201[0-9]|202[0-4])\\b")
    if (!is.na(year_match_sheet_direct)) {
        return(as.integer(year_match_sheet_direct))
    }

    year_match_sheet_ende_mitte_yyyy <- str_match(tolower(sheet_name), "(?:ende|mitte)_(\\d{4})")
    if (!is.na(year_match_sheet_ende_mitte_yyyy[1, 2])) {
        year_val <- as.integer(year_match_sheet_ende_mitte_yyyy[1, 2])
        if (year_val >= 2005 && year_val <= 2024) {
            return(year_val)
        }
    }
    year_match_sheet_ende_mitte_yy <- str_match(tolower(sheet_name), "(?:ende|mitte)(\\d{2})")
    if (!is.na(year_match_sheet_ende_mitte_yy[1, 2])) {
        return(as.integer(paste0("20", year_match_sheet_ende_mitte_yy[1, 2])))
    }

    # Priority 2: Try from filename (using logic similar to clean_data.R's year extraction)
    year_match_file_direct <- str_extract(file_name_base, "\\b(200[5-9]|201[0-9]|202[0-4])\\b")
    if (!is.na(year_match_file_direct)) {
        return(as.integer(year_match_file_direct))
    }

    year_match_file_general <- str_extract(file_name_base, "(?<!\\\\d)(200[5-9]|201[0-9]|202[0-4])(?!\\\\d)")
    if (!is.na(year_match_file_general)) {
        return(as.integer(year_match_file_general))
    }

    year_match_file_short <- str_match(tolower(file_name_base), "(?:ende|mitte)(\\d{2})")
    if (!is.na(year_match_file_short[1, 2])) {
        return(as.integer(paste0("20", year_match_file_short[1, 2])))
    }

    # Special case for sheet names like "verf_2005_dsl_gem" from filenames like "2005_DSL_..."
    # This is largely covered by year_match_file_direct if sheet name fails

    return(NA_integer_)
}

# --- Core Processing Function for a Single Sheet ---
process_sheet_data_paket1 <- function(data_df, ags_col_name, year_val_sheet_file, file_basename_for_log) {
    original_colnames <- colnames(data_df)
    # Sanitize column names for R (make.names) and keep mapping to original
    clean_colnames <- make.names(original_colnames, unique = TRUE)
    colnames(data_df) <- clean_colnames
    names_map <- setNames(original_colnames, clean_colnames)

    # Find the cleaned version of the AGS column name
    ags_col_name_clean <- names(names_map)[which(names_map == ags_col_name)]
    if (length(ags_col_name_clean) == 0) {
        ags_col_name_clean <- make.names(ags_col_name)
    }

    if (is.na(ags_col_name_clean) || !(ags_col_name_clean %in% colnames(data_df))) {
        message(paste("AGS column (", ags_col_name, "->", ags_col_name_clean, ") not found after cleaning or invalid for file:", file_basename_for_log))
        return(NULL)
    }

    # Rename the identified AGS column to a standard name for simplicity.
    data_df <- data_df %>%
        rename(AGS = all_of(ags_col_name_clean)) %>%
        mutate(AGS = as.character(AGS))

    # Identify all columns that should NOT be pivoted (id_cols)
    # These are AGS and any other known non-metric identifiers
    known_id_patterns <- c("id", "gen", "ewz", "bez")

    # Find the cleaned names of the id columns that exist in the current dataframe
    id_cols_to_keep <- c("AGS") # Start with our standardized AGS column

    for (clean_name in names(names_map)) {
        original_name <- names_map[[clean_name]]
        if (tolower(original_name) %in% known_id_patterns) {
            # Add the cleaned name, but avoid adding the original AGS column's clean name again
            if (clean_name != ags_col_name_clean) {
                id_cols_to_keep <- c(id_cols_to_keep, clean_name)
            }
        }
    }

    # Ensure the columns to keep actually exist in the dataframe before proceeding
    id_cols_to_keep <- intersect(id_cols_to_keep, colnames(data_df))

    long_data <- data_df %>%
        pivot_longer(
            cols = -all_of(id_cols_to_keep),
            names_to = "variable_raw_clean",
            values_to = "value_raw",
            values_transform = list(value_raw = as.character)
        ) %>%
        mutate(
            year_sheet_file = year_val_sheet_file,
            data_category = "privat",
            variable_original = names_map[variable_raw_clean]
        ) %>%
        filter(!is.na(variable_original))

    # Get unique original variable names to parse
    unique_vars_to_parse <- tibble(variable_original = unique(long_data$variable_original))

    # Parse each unique variable name only once
    # The result will be a tibble with 'variable_original' and the parsed components:
    # 'technology_group', 'speed_mbps_gte', 'year_from_variable'
    parsed_vars_map <- unique_vars_to_parse %>%
        mutate(parsed_components = map(variable_original, parse_broadband_variable)) %>%
        unnest(parsed_components)

    # Join the parsed components back to the main long_data table
    long_data_with_parsed_vars <- left_join(long_data, parsed_vars_map, by = "variable_original")

    # Now, proceed with further transformations using the joined columns
    processed_data <- long_data_with_parsed_vars %>%
        mutate(year = ifelse(!is.na(year_from_variable), year_from_variable, year_sheet_file)) %>%
        select(AGS, year, data_category, technology_group, speed_mbps_gte, value = value_raw, original_variable = variable_original) %>%
        mutate(value = as.numeric(str_replace(value, ",", "."))) %>%
        filter(!is.na(value), !is.na(AGS), str_length(AGS) > 0, !is.na(year)) # Ensure value, AGS, and year are valid

    return(processed_data)
}

# --- Main Script Logic ---

print("Starting processing for Paket 1 Excel files...")

inspection_summary_file <- here("output", "excel_sheet_inspection_summary.csv")
if (!file.exists(inspection_summary_file)) {
    stop("Error: Inspection summary file not found at ", inspection_summary_file, ". Please run inspect_excel_sheets.R first.")
}

inspection_df <- read_csv(inspection_summary_file, show_col_types = FALSE)

# Filter for Paket 1 and sheets with AGS
paket1_sheets_to_process <- inspection_df %>%
    filter(str_detect(tolower(file_path), "paket_1"), ags_column_found == TRUE)

if (nrow(paket1_sheets_to_process) == 0) {
    print("No relevant sheets found for Paket 1 in the inspection summary.")
} else {
    print(paste("Found", nrow(paket1_sheets_to_process), "sheets from Paket 1 to process."))
    all_processed_paket1_data <- list()

    for (i in 1:nrow(paket1_sheets_to_process)) {
        sheet_info <- paket1_sheets_to_process[i, ]
        file_path <- sheet_info$file_path
        sheet_name <- sheet_info$sheet_name
        ags_col <- sheet_info$identified_ags_column
        file_basename <- basename(file_path)

        print(paste("Processing file:", file_basename, "- Sheet:", sheet_name))

        year_for_this_sheet <- extract_year_for_sheet(sheet_name, file_basename)
        if (is.na(year_for_this_sheet)) {
            message(paste("  Skipping sheet, could not determine year for file:", file_basename, "Sheet:", sheet_name))
            next
        }
        print(paste("  Determined year:", year_for_this_sheet))

        current_sheet_data <- tryCatch(
            {
                read_excel(file_path, sheet = sheet_name)
            },
            error = function(e) {
                message(paste("  Error reading sheet:", sheet_name, "from file:", file_basename, "-", e$message))
                return(NULL)
            }
        )

        if (is.null(current_sheet_data) || nrow(current_sheet_data) == 0) {
            message(paste("  No data read or empty sheet for file:", file_basename, "Sheet:", sheet_name))
            next
        }

        print(paste("  Glimpse of sheet data for:", file_basename, "- Sheet:", sheet_name))
        glimpse(current_sheet_data)

        # --- ADDED DIAGNOSTIC BLOCK for 2005-2008 original column names and head ---
        if (!is.na(year_for_this_sheet) && year_for_this_sheet %in% 2005:2008) {
            cat(paste("\n--- DIAGNOSTIC: Original Variables for Early Year Sheet ---\n"))
            cat(paste("File:", file_basename, "| Sheet:", sheet_name, "| Determined Year:", year_for_this_sheet, "\n"))
            cat("Original Column Names (as read from Excel):\n")
            print(colnames(current_sheet_data))
            cat("First 6 rows of the sheet (head view):\n")
            print(head(current_sheet_data))
            cat(paste("--- END DIAGNOSTIC ---\n\n"))
        }
        # --- END OF ADDED DIAGNOSTIC BLOCK ---

        # Check for completely empty header (all column names are NA or like ...1, ...2)
        if (all(is.na(colnames(current_sheet_data))) || all(str_detect(colnames(current_sheet_data), "^\\.\\.\\.\\d+$"))) {
            message(paste("  Skipping sheet with empty or non-informative header:", sheet_name, "in file:", file_basename))
            next
        }

        processed_tibble <- process_sheet_data_paket1(current_sheet_data, ags_col, year_for_this_sheet, file_basename)

        if (!is.null(processed_tibble) && nrow(processed_tibble) > 0) {
            all_processed_paket1_data[[length(all_processed_paket1_data) + 1]] <- processed_tibble
        } else {
            message(paste("  No data returned after processing sheet:", sheet_name, "in file:", file_basename))
        }
    }

    if (length(all_processed_paket1_data) > 0) {
        final_paket1_df <- bind_rows(all_processed_paket1_data) %>%
            mutate(AGS = str_pad(AGS, 8, pad = "0")) %>%
            filter(str_length(AGS) == 8) # Final safety check for AGS length

        # Save the final combined data for Paket 1
        output_file_rds <- here("output", "broadband_gemeinde_paket_1_long.rds")
        saveRDS(final_paket1_df, file = output_file_rds)

        print(paste("Successfully processed Paket 1. Final data has", nrow(final_paket1_df), "rows."))
        print(paste("Saved combined Paket 1 data to:", output_file_rds))
    } else {
        print("No data was processed from Paket 1.")
    }
}

print("Finished processing for Paket 1 Excel files.")
