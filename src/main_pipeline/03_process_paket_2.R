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
    year_match_in_var <- str_match(tolower(variable_name), "_(\\\\d{4})$") # Matches _YYYY at the end
    if (!is.na(year_match_in_var[1, 2])) {
        year_in_var <- as.integer(year_match_in_var[1, 2])
        # Remove year from variable_name for further parsing if needed, e.g., "verf_300_50_2010" -> "verf_300_50"
        variable_name_no_year <- str_replace(tolower(variable_name), "_\\\\d{4}$", "")
    } else {
        variable_name_no_year <- tolower(variable_name)
    }

    # Regex for modern names like "Technology Name ≥ 100 Mbit/s" or "Technology Name  100 Mbit/s"
    match_modern <- str_match(variable_name, "^([a-zA-ZäöüÄÖÜß\\.\\s/]+?)(?:\\s*≥\\s*|\\s+)(\\d+)\\s+Mbit/s$")
    if (!is.na(match_modern[1, 1])) {
        technology <- str_trim(match_modern[1, 2])
        speed <- as.integer(match_modern[1, 3])
        return(tibble(technology_group = technology, speed_mbps_gte = speed, year_from_variable = year_in_var))
    }

    # Regex for names like "priv_dsl_100", "gew_lg_tech_50" from 2021_BBA_Gemeindedaten.xls
    match_prefix_tech_speed <- str_match(variable_name_no_year, "^([a-z]+)_([a-z_]+)_(\\d+)$")
    if (!is.na(match_prefix_tech_speed[1, 1])) {
        prefix <- match_prefix_tech_speed[1, 2] # e.g., "priv", "gew", "schulen"
        tech_base <- match_prefix_tech_speed[1, 3] # e.g., "alle_tech", "lg_tech", "dsl"
        speed_val <- as.integer(match_prefix_tech_speed[1, 4])

        full_tech_name <- case_when(
            tech_base == "alle_tech" ~ "Alle Technologien",
            tech_base == "lg_tech" ~ "Leitungsg. Technologien",
            tech_base == "dsl" ~ "DSL",
            tech_base == "catv" ~ "CATV",
            tech_base == "ftthb" ~ "FTTH/B",
            TRUE ~ str_to_title(str_replace_all(tech_base, "_", " "))
        )

        final_technology_group <- paste0(full_tech_name, " (", prefix, ")")

        return(tibble(technology_group = final_technology_group, speed_mbps_gte = speed_val, year_from_variable = year_in_var))
    }

    # Regex for historical verf_XXX_YY names (e.g., verf_100_30)
    match_hist_verf <- str_match(variable_name_no_year, "^verf_(\\\\d{3})_(\\\\d+)")
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
    match_hist_tech <- str_match(variable_name_no_year, "^(dsl|catv|ftthb|fttb|hfc)_(\\\\d+)") # Added HFC
    if (!is.na(match_hist_tech[1, 1])) {
        technology_raw <- match_hist_tech[1, 2]
        speed <- as.integer(match_hist_tech[1, 3])
        technology <- case_when(
            technology_raw == "dsl" ~ "DSL (hist)",
            technology_raw == "catv" ~ "CATV (hist)",
            technology_raw == "ftthb" ~ "FTTH/B (hist)",
            technology_raw == "fttb" ~ "FTTB (hist)",
            technology_raw == "hfc" ~ "HFC (hist)", # Added HFC
            TRUE ~ paste0("hist_tech_", technology_raw)
        )
        return(tibble(technology_group = technology, speed_mbps_gte = speed, year_from_variable = year_in_var))
    }

    # Regex for columns like "HH_ges" or "HH_DSL_16" or "GemFl"
    # These might appear in Paket 2 files like BBA_historisch_2018_2021.xlsx
    match_hh_gemfl <- str_match(tolower(variable_name), "^hh_([a-z0-9]+)_(\\d+)$") # e.g. hh_dsl_16
    if (!is.na(match_hh_gemfl[1, 1])) {
        technology_raw <- match_hh_gemfl[1, 2]
        speed <- as.integer(match_hh_gemfl[1, 3])
        technology <- case_when(
            technology_raw == "dsl" ~ "DSL (HH)",
            technology_raw == "catv" ~ "CATV (HH)",
            technology_raw == "ftthb" ~ "FTTH/B (HH)",
            technology_raw == "fttb" ~ "FTTB (HH)",
            technology_raw == "hfc" ~ "HFC (HH)",
            TRUE ~ paste0(toupper(technology_raw), " (HH)")
        )
        return(tibble(technology_group = technology, speed_mbps_gte = speed, year_from_variable = year_in_var))
    }

    # Regex for names like "leitungsg_technologien_gtoe_100_mbits"
    match_gtoe_mbits <- str_match(variable_name_no_year, "^([a-z_]+)_gtoe_(\\d+)_mbits$")
    if (!is.na(match_gtoe_mbits[1, 1])) {
        technology_raw <- match_gtoe_mbits[1, 2]
        speed <- as.integer(match_gtoe_mbits[1, 3])
        technology <- case_when(
            technology_raw == "leitungsg_technologien" ~ "Leitungsg. Technologien (gtoe)",
            technology_raw == "dsl" ~ "DSL (gtoe)",
            technology_raw == "catv" ~ "CATV (gtoe)",
            technology_raw == "ftthb" ~ "FTTH/B (gtoe)",
            TRUE ~ paste0(str_to_title(str_replace_all(technology_raw, "_", " ")), " (gtoe)") # Generic cleanup
        )
        return(tibble(technology_group = technology, speed_mbps_gte = speed, year_from_variable = year_in_var))
    }

    # Handle "HH_ges" and "GemFl" without speed
    if (tolower(variable_name) %in% c("hh_ges", "hh_gesamt", "gemfl", "gemeindeflaeche", "gemeindefläche")) {
        return(tibble(technology_group = variable_name, speed_mbps_gte = NA_integer_, year_from_variable = year_in_var))
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

    # For Paket 2, files like BBA_historisch_2018_2021.xlsx have sheets like "2018_Gemeindedaten"
    year_match_sheet_prefix <- str_match(sheet_name, "^(\\d{4})_") # Rule 4
    if (!is.na(year_match_sheet_prefix[1, 2])) {
        year_val <- as.integer(year_match_sheet_prefix[1, 2])
        if (year_val >= 2005 && year_val <= 2024) {
            return(year_val)
        }
    }

    # Priority 2: Try from filename (using logic similar to clean_data.R's year extraction)
    year_match_file_direct <- str_extract(file_name_base, "\\b(200[5-9]|201[0-9]|202[0-4])\\b")
    if (!is.na(year_match_file_direct)) {
        return(as.integer(year_match_file_direct))
    }

    year_match_file_general <- str_extract(file_name_base, "(?<!\\d)(200[5-9]|201[0-9]|202[0-4])(?!\\d)")
    if (!is.na(year_match_file_general)) {
        return(as.integer(year_match_file_general))
    }

    year_match_file_short <- str_match(tolower(file_name_base), "(?:ende|mitte)(\\d{2})")
    if (!is.na(year_match_file_short[1, 2])) {
        return(as.integer(paste0("20", year_match_file_short[1, 2])))
    }

    return(NA_integer_)
}

# --- Core Processing Function for a Single Sheet ---
process_sheet_data_paket2 <- function(data_df, ags_col_name, year_val_sheet_file, file_basename_for_log) {
    original_colnames <- colnames(data_df)
    clean_colnames <- make.names(original_colnames, unique = TRUE)
    colnames(data_df) <- clean_colnames
    names_map <- setNames(original_colnames, clean_colnames)

    ags_col_name_clean <- names(names_map)[which(names_map == ags_col_name)]
    if (length(ags_col_name_clean) == 0) ags_col_name_clean <- NA_character_

    if (is.na(ags_col_name_clean) || !(ags_col_name_clean %in% colnames(data_df))) {
        message(paste("AGS column (\'", ags_col_name, "\' -> \'", ags_col_name_clean, "\') not found after cleaning or invalid for file:", file_basename_for_log))
        return(NULL)
    }

    data_df <- data_df %>%
        mutate(!!sym(ags_col_name_clean) := as.character(!!sym(ags_col_name_clean)))

    long_data <- data_df %>%
        rename(AGS = !!sym(ags_col_name_clean)) %>%
        select(AGS, everything()) %>%
        pivot_longer(
            cols = -AGS,
            names_to = "variable_raw_clean",
            values_to = "value_raw",
            values_transform = list(value_raw = as.character) # Keep as character for initial processing
        ) %>%
        mutate(
            year_sheet_file = year_val_sheet_file,
            data_category = "privat", # Assuming Paket 2 is also primarily 'privat' or general
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
        mutate(
            value_cleaned = str_replace_all(value, "[^0-9.,-]", ""), # Keep digits, comma, dot, minus
            value_cleaned = str_replace(value_cleaned, ",", "."),
            value = as.numeric(value_cleaned)
        ) %>%
        filter(!is.na(value), !is.na(AGS), str_length(AGS) > 0, !is.na(year))

    return(processed_data)
}

# --- Main Script Logic ---

print("Starting processing for Paket 2 Excel files...")

inspection_summary_file <- here("output", "excel_sheet_inspection_summary.csv")
if (!file.exists(inspection_summary_file)) {
    stop("Error: Inspection summary file not found at ", inspection_summary_file, ". Please run inspect_excel_sheets.R first.")
}

inspection_df <- read_csv(inspection_summary_file, show_col_types = FALSE)

# Filter for Paket 2 and sheets with AGS
paket2_sheets_to_process <- inspection_df %>%
    filter(str_detect(tolower(file_path), "paket_2"), ags_column_found == TRUE)

if (nrow(paket2_sheets_to_process) == 0) {
    print("No relevant sheets found for Paket 2 in the inspection summary.")
} else {
    print(paste("Found", nrow(paket2_sheets_to_process), "sheets from Paket 2 to process."))
    all_processed_paket2_data <- list()

    for (i in 1:nrow(paket2_sheets_to_process)) {
        sheet_info <- paket2_sheets_to_process[i, ]
        file_path <- sheet_info$file_path
        sheet_name <- sheet_info$sheet_name
        ags_col <- sheet_info$identified_ags_column
        file_basename <- basename(file_path)

        print(paste("Processing file:", file_basename, "- Sheet:", sheet_name))

        year_for_this_sheet <- extract_year_for_sheet(sheet_name, file_basename)
        if (is.na(year_for_this_sheet)) {
            # Try to infer year from file name if it's a multi-year file like BBA_historisch_2018_2021.xlsx
            # and sheet name itself doesn't have a clear year. This is a bit of a fallback.
            if (str_detect(tolower(file_basename), "bba_historisch_(\\d{4})_(\\d{4})\\.xlsx")) {
                # For files like BBA_historisch_2018_2021.xlsx, sheet name *should* have the year.
                # If not, it's ambiguous. Let's rely on sheet name primarily.
                message(paste("  Skipping sheet, could not determine year for file:", file_basename, "Sheet:", sheet_name, "- Multi-year file where sheet name lacks clear year."))
                next
            } else {
                message(paste("  Skipping sheet, could not determine year for file:", file_basename, "Sheet:", sheet_name))
                next
            }
        }
        print(paste("  Determined year:", year_for_this_sheet))

        current_sheet_data <- tryCatch(
            {
                read_excel(file_path, sheet = sheet_name, .name_repair = "minimal") # Use minimal name repair
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

        if (all(is.na(colnames(current_sheet_data))) || all(str_detect(colnames(current_sheet_data), "^\\.\\.\\.\\d+$"))) {
            message(paste("  Skipping sheet with empty or non-informative header:", sheet_name, "in file:", file_basename))
            next
        }

        # Additional check for Paket 2: some sheets might have few columns (e.g. just AGS and a note)
        if (ncol(current_sheet_data) < 3 && !str_detect(tolower(ags_col), "kennziffer")) { # Allow if AGS is Kennziffer type
            message(paste("  Skipping sheet with very few columns ( < 3) that might not be data tables:", sheet_name, "in file:", file_basename))
            next
        }


        processed_tibble <- process_sheet_data_paket2(current_sheet_data, ags_col, year_for_this_sheet, file_basename)

        if (!is.null(processed_tibble) && nrow(processed_tibble) > 0) {
            all_processed_paket2_data[[length(all_processed_paket2_data) + 1]] <- processed_tibble
        } else {
            message(paste("  No data returned after processing sheet:", sheet_name, "in file:", file_basename))
        }
    }

    if (length(all_processed_paket2_data) > 0) {
        final_paket2_data <- bind_rows(all_processed_paket2_data)
        final_paket2_data <- final_paket2_data %>%
            mutate(
                AGS = str_pad(AGS, 8, pad = "0"),
                speed_mbps_gte = as.integer(speed_mbps_gte),
                value = as.numeric(value)
            ) %>%
            filter(!is.na(AGS), !is.na(year), !is.na(value), str_length(AGS) == 8) %>%
            distinct()

        print(paste("Total rows in combined Paket 2 dataset:", nrow(final_paket2_data)))
        print("Summary of final_paket2_data:")
        summary(final_paket2_data)
        print("Sample of final_paket2_data (first 6 rows):")
        print(head(final_paket2_data))

        unparsed_tech_summary_p2 <- final_paket2_data %>%
            filter(is.na(speed_mbps_gte) & !technology_group %in% c("HH_ges", "HH_gesamt", "GemFl", "Gemeindeflaeche", "Gemeindefläche")) %>%
            count(technology_group, original_variable, sort = TRUE)

        if (nrow(unparsed_tech_summary_p2) > 0) {
            print("Summary of Paket 2 technology groups that might need refined parsing logic (excluding HH_ges, GemFl):")
            print(unparsed_tech_summary_p2, n = 50)
        } else {
            print("All relevant technology groups in Paket 2 seem to have been parsed into speed categories or are known non-speed variables.")
        }

        output_file_p2 <- here("output", "broadband_gemeinde_paket_2_long.csv")
        if (!dir.exists(here("output"))) {
            dir.create(here("output"))
        }
        write_csv(final_paket2_data, output_file_p2)
        print(paste("Saved processed Paket 2 data to:", output_file_p2))
    } else {
        print("No data was processed successfully for Paket 2.")
    }
}

print("Finished processing for Paket 2.")
