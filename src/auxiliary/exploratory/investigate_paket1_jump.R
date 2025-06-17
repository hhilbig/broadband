library(tidyverse)
library(readxl)
library(stringr)
library(here)

# --- Helper Functions (copied from process_paket_1.R for reference, though not directly used in this revised first step) ---
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

extract_year_for_sheet <- function(sheet_name, file_name_base) {
    # Corrected regex for R string
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

    year_match_file_direct <- str_extract(file_name_base, "\\b(200[5-9]|201[0-9]|202[0-4])\\b")
    if (!is.na(year_match_file_direct)) {
        return(as.integer(year_match_file_direct))
    }

    year_match_file_general <- str_extract(file_name_base, "(?<!\\d)(200[5-9]|201[0-9]|202[0-4])(?!\\d)") # Corrected regex for R string
    if (!is.na(year_match_file_general)) {
        return(as.integer(year_match_file_general))
    }

    year_match_file_short <- str_match(tolower(file_name_base), "(?:ende|mitte)(\\d{2})")
    if (!is.na(year_match_file_short[1, 2])) {
        return(as.integer(paste0("20", year_match_file_short[1, 2])))
    }

    return(NA_integer_)
}

# --- Main Investigation Logic ---

print("--- Starting Paket 1 Jump Investigation for verf_privat_alle_2010_2018.xls ---")

file_to_investigate <- here("data", "Paket_1", "verf_privat_alle_2010_2018.xls")
sheet_to_investigate <- "verf_gemeinde_10_18_percent" # Identified as relevant

if (!file.exists(file_to_investigate)) {
    stop(paste("Target file not found:", file_to_investigate))
}

print(paste("Reading sheet:", sheet_to_investigate, "from file:", basename(file_to_investigate)))
raw_data <- tryCatch(
    {
        read_excel(file_to_investigate, sheet = sheet_to_investigate)
    },
    error = function(e) {
        stop(paste("Error reading sheet:", e$message))
    }
)

if (is.null(raw_data) || nrow(raw_data) == 0) {
    stop("No data read or empty sheet.")
}

print("--- Raw Data Glimpse (first few rows and columns) ---")
print(glimpse(raw_data[, 1:min(ncol(raw_data), 10)])) # Show first 10 cols, or fewer if not that many

original_colnames <- colnames(raw_data)

# Dynamically find the AGS column based on common names, case-insensitive
ags_col_name_identified <- NA
col_names_lower <- tolower(original_colnames)
# Simplified AGS patterns, as "ags" seems to be the primary one found.
ags_patterns <- c("^ags$", "^gemeindeschluessel$", "^gemeindeschlüssel$", "^gem$")

for (pattern in ags_patterns) {
    match_idx <- str_which(col_names_lower, pattern)
    if (length(match_idx) > 0) {
        ags_col_name_identified <- original_colnames[match_idx[1]]
        print(paste("Identified AGS column as:", ags_col_name_identified))
        break
    }
}

if (is.na(ags_col_name_identified)) {
    # Fallback if not found, try to print all column names to help user identify it manually
    print("Could not automatically identify AGS column. Available column names:")
    print(original_colnames)
    stop("Please inspect column names and identify the AGS column manually if needed.")
}

# Identify columns for 2014 and 2015 relevant metrics
cols_2014 <- original_colnames[str_detect(tolower(original_colnames), "_2014$")]
cols_2015 <- original_colnames[str_detect(tolower(original_colnames), "_2015$")]

print("--- Columns identified for 2014 metrics ---")
if (length(cols_2014) > 0) print(cols_2014) else print("No columns ending in _2014 found.")

print("--- Columns identified for 2015 metrics ---")
if (length(cols_2015) > 0) print(cols_2015) else print("No columns ending in _2015 found.")

if (length(cols_2014) == 0 || length(cols_2015) == 0) {
    stop("Did not find relevant metric columns for both 2014 and 2015. Cannot proceed with comparison.")
}

# Prepare data for comparison
raw_data_ags_char <- raw_data %>%
    mutate(!!sym(ags_col_name_identified) := as.character(!!sym(ags_col_name_identified))) %>%
    mutate(!!sym(ags_col_name_identified) := str_pad(!!sym(ags_col_name_identified), 8, side = "left", pad = "0"))

sample_ags <- raw_data_ags_char %>%
    filter(!is.na(!!sym(ags_col_name_identified)) & str_length(!!sym(ags_col_name_identified)) > 0) %>%
    distinct(!!sym(ags_col_name_identified)) %>%
    head(5) %>%
    pull(!!sym(ags_col_name_identified))

if (length(sample_ags) == 0) {
    stop("Could not retrieve sample AGS codes.")
}

print(paste("--- Comparing raw values for sample AGS codes:", paste(sample_ags, collapse = ", "), "---"))

comparison_data_2014 <- raw_data_ags_char %>%
    filter(!!sym(ags_col_name_identified) %in% sample_ags) %>%
    select(all_of(ags_col_name_identified), all_of(cols_2014))

comparison_data_2015 <- raw_data_ags_char %>%
    filter(!!sym(ags_col_name_identified) %in% sample_ags) %>%
    select(all_of(ags_col_name_identified), all_of(cols_2015))

print("--- Data for 2014 (Sample AGS) ---")
print(comparison_data_2014)

print("--- Data for 2015 (Sample AGS) ---")
print(comparison_data_2015)


print("--- Average values for 2014 metrics (across all AGS) ---")
raw_data_ags_char %>%
    select(all_of(cols_2014)) %>%
    mutate(across(everything(), ~ as.numeric(str_replace(as.character(.), fixed(","), ".")))) %>%
    summarise(across(everything(), list(mean = ~ mean(.x, na.rm = TRUE), non_na_count = ~ sum(!is.na(.x))))) %>%
    glimpse()

print("--- Average values for 2015 metrics (across all AGS) ---")
raw_data_ags_char %>%
    select(all_of(cols_2015)) %>%
    mutate(across(everything(), ~ as.numeric(str_replace(as.character(.), fixed(","), ".")))) %>%
    summarise(across(everything(), list(mean = ~ mean(.x, na.rm = TRUE), non_na_count = ~ sum(!is.na(.x))))) %>%
    glimpse()

print("--- End of Investigation Script ---")



# Original code for identifying sources via extract_year_for_sheet - kept for reference
# print("--- Attempting to identify 2014 & 2015 sources again ---")
# inspection_summary_file <- here("output", "excel_sheet_inspection_summary.csv")
# inspection_df <- read_csv(inspection_summary_file, show_col_types = FALSE)
# paket1_inspected_sheets <- inspection_df %>%
#     filter(str_detect(tolower(file_path), "paket_1"), ags_column_found == TRUE)
# sources_2014 <- tibble(file_path = character(), sheet_name = character(), identified_ags_column = character())
# sources_2015 <- tibble(file_path = character(), sheet_name = character(), identified_ags_column = character())
# for (i in 1:nrow(paket1_inspected_sheets)) {
#     sheet_info <- paket1_inspected_sheets[i, ]
#     file_basename <- basename(sheet_info$file_path)
#     year_for_this_sheet <- extract_year_for_sheet(sheet_info$sheet_name, file_basename)
#     if (!is.na(year_for_this_sheet)) {
#         if (year_for_this_sheet == 2014) {
#             sources_2014 <- sources_2014 %>%
#                 add_row(file_path = sheet_info$file_path, sheet_name = sheet_info$sheet_name, identified_ags_column = sheet_info$identified_ags_column)
#         }
#         if (year_for_this_sheet == 2015) {
#             sources_2015 <- sources_2015 %>%
#                 add_row(file_path = sheet_info$file_path, sheet_name = sheet_info$sheet_name, identified_ags_column = sheet_info$identified_ags_column)
#         }
#     }
# }
# print("--- Identified Sources for 2014 Data (Paket 1) based on extract_year_for_sheet ---")
# if (nrow(sources_2014) > 0) print(sources_2014) else print("No specific sources found for 2014 using extract_year_for_sheet.")
# print("--- Identified Sources for 2015 Data (Paket 1) based on extract_year_for_sheet ---")
# if (nrow(sources_2015) > 0) print(sources_2015) else print("No specific sources found for 2015 using extract_year_for_sheet.")
