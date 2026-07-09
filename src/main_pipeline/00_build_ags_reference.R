library(tidyverse)
library(readxl)
library(stringr)
library(here)

set.seed(20260709)

# --- Purpose ---
# Reproducible generator for the Destatis 2021 AGS reference used by steps 06 and 07.
#
# The reference is extracted from the "2020" sheet of the official Destatis
# Umsteigeschluessel workbook: the distinct "Gemeinden 31.12.2021" target codes
# enumerate all 10,994 municipalities on 2021-12-31 boundaries.
#
# IMPORTANT: the AGS column in the workbook is numeric. Berlin (11000000) and
# Hamburg (2000000) are the only municipal codes round enough for R to render
# in scientific notation ("1.1e+07", "2e+06"). A naive as.character() +
# digit-strip extraction mangles exactly these two codes into invalid strings
# and silently drops them (this bug produced the previous 10,992-row reference
# that lacked both city-states). standardize_ags_8() below formats numeric-like
# values without scientific notation, which is why it must not be replaced by
# a plain gsub("\\D", "") approach.

merger_file_2011_2020 <- here("data", "muni_mergers", "ref-gemeinden-umrech-2021-2011-2020.xlsx")
ags_reference_file <- here("data", "ags_reference", "destatis_ags_2021.rds")

valid_ags_pattern <- "^(0[1-9]|1[0-6])\\d{6}$"

# Copy of standardize_ags_8() from 06_standardize_ags_to_2021.R (scripts are standalone).
standardize_ags_8 <- function(ags) {
    ags_chr <- str_trim(as.character(ags))
    ags_chr <- str_replace_all(ags_chr, ",", ".")
    numeric_like <- str_detect(ags_chr, "^[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$")
    numeric_like[is.na(numeric_like)] <- FALSE
    ags_out <- rep(NA_character_, length(ags_chr))

    if (any(numeric_like, na.rm = TRUE)) {
        ags_num <- suppressWarnings(as.numeric(ags_chr[numeric_like]))
        whole_number <- !is.na(ags_num) & abs(ags_num - round(ags_num)) < 0.001
        formatted <- rep(NA_character_, length(ags_num))
        formatted[whole_number] <- sprintf("%08.0f", round(ags_num[whole_number]))
        ags_out[numeric_like] <- formatted
    }

    non_numeric <- !numeric_like & !is.na(ags_chr)
    if (any(non_numeric, na.rm = TRUE)) {
        ags_digits <- str_replace_all(ags_chr[non_numeric], "\\D", "")
        ags_out[non_numeric] <- ifelse(
            str_length(ags_digits) > 0,
            str_pad(ags_digits, 8, pad = "0"),
            NA_character_
        )
    }

    ags_out
}

# --- Extract the 2021 municipality roster from the "2020" crosswalk sheet ---
raw_sheet <- read_excel(merger_file_2011_2020, sheet = "2020", .name_repair = "minimal")
sheet_colnames <- colnames(raw_sheet)

idx_ags_2021 <- which(str_detect(sheet_colnames, fixed("31.12.2021")) &
                          str_detect(sheet_colnames, "Gemeinden"))[1]
idx_name_2021 <- which(str_detect(sheet_colnames, regex("Gemeindename\\s*2021", ignore_case = TRUE)))[1]

if (is.na(idx_ags_2021)) {
    stop("Could not locate the 'Gemeinden 31.12.2021' column in the 2020 sheet.")
}
if (is.na(idx_name_2021)) {
    stop("Could not locate the 'Gemeindename 2021' column in the 2020 sheet.")
}

ags_reference <- raw_sheet %>%
    transmute(
        AGS = standardize_ags_8(.data[[sheet_colnames[idx_ags_2021]]]),
        name = as.character(.data[[sheet_colnames[idx_name_2021]]])
    ) %>%
    filter(str_detect(AGS, valid_ags_pattern)) %>%
    distinct(AGS, .keep_all = TRUE) %>%
    mutate(state_code = substr(AGS, 1, 2)) %>%
    select(AGS, state_code, name) %>%
    arrange(AGS)

# --- Assertions ---
if (nrow(ags_reference) != 10994) {
    stop("Expected 10,994 municipalities in the 2021 reference, got ", nrow(ags_reference))
}
if (!all(c("02000000", "11000000") %in% ags_reference$AGS)) {
    stop("Berlin (11000000) and/or Hamburg (02000000) missing from the reference - scientific-notation bug is back.")
}
if (anyDuplicated(ags_reference$AGS) > 0) {
    stop("Duplicate AGS codes in the reference.")
}
expected_states <- sprintf("%02d", 1:16)
missing_states <- setdiff(expected_states, unique(ags_reference$state_code))
if (length(missing_states) > 0) {
    stop("States missing from the reference: ", paste(missing_states, collapse = ", "))
}
if (any(is.na(ags_reference$name) | ags_reference$name == "")) {
    stop("Missing municipality names in the reference.")
}

saveRDS(ags_reference, ags_reference_file)

print(paste("Saved", nrow(ags_reference), "municipalities to", ags_reference_file))
print("State distribution:")
print(table(ags_reference$state_code))
print(ags_reference %>% filter(AGS %in% c("02000000", "11000000")))
