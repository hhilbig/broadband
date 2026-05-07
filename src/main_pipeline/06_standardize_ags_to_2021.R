library(tidyverse)
library(readxl)
library(stringr)
library(here)

# --- Configuration ---
input_file <- here("output", "broadband_gemeinde_combined_long.rds")
output_file <- here("output", "broadband_gemeinde_combined_long_ags2021.rds")

merger_file_2000_2010 <- here("data", "muni_mergers", "ref-gemeinden-umrech-2021-2000-2010.xlsx")
merger_file_2011_2020 <- here("data", "muni_mergers", "ref-gemeinden-umrech-2021-2011-2020.xlsx")
ags_reference_file <- here("data", "ags_reference", "destatis_ags_2021.rds")
reform_mapping_file <- here("data", "gebietsreformen", "combined_reform_mappings.rds")

supplementary_crosswalk_file <- here("output", "supplementary_ags_crosswalk.rds")
supplementary_mapping_detail_file <- here("output", "missing_ags_to_2021_mapping.rds")
unmapped_ags_file <- here("output", "unmapped_ags_for_review.csv")

valid_ags_pattern <- "^(0[1-9]|1[0-6])\\d{6}$"

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

load_destatis_ags <- function(path) {
    if (!file.exists(path)) {
        stop("Destatis 2021 AGS reference is missing: ", path)
    }

    readRDS(path) %>%
        mutate(AGS = standardize_ags_8(AGS)) %>%
        filter(str_detect(AGS, valid_ags_pattern)) %>%
        distinct(AGS)
}

process_merger_sheet <- function(file_path, sheet_name_year_str) {
    print(paste("Processing crosswalk sheet", sheet_name_year_str, "from", basename(file_path)))

    raw_sheet_data <- tryCatch(
        read_excel(file_path, sheet = sheet_name_year_str, .name_repair = "minimal"),
        error = function(e) {
            message("Error reading sheet ", sheet_name_year_str, " from ", basename(file_path), ": ", e$message)
            NULL
        }
    )

    if (is.null(raw_sheet_data)) {
        return(NULL)
    }

    actual_colnames <- colnames(raw_sheet_data)
    idx_ags_hist <- which(str_detect(actual_colnames, fixed(paste0("31.12.", sheet_name_year_str))) &
                              str_detect(actual_colnames, "Gemeinden"))[1]
    idx_ags_2021 <- which(str_detect(actual_colnames, fixed("31.12.2021")) &
                              str_detect(actual_colnames, "Gemeinden"))[1]
    idx_transition_share <- which(str_detect(actual_colnames, regex("^bev", ignore_case = TRUE)) &
                                      str_detect(actual_colnames, regex("umsteige", ignore_case = TRUE)))[1]
    idx_population <- which(str_detect(actual_colnames, regex("^Bev", ignore_case = TRUE)) &
                                str_detect(actual_colnames, fixed(paste0("31.12.", sheet_name_year_str))))[1]

    if (is.na(idx_ags_hist) || is.na(idx_ags_2021) || is.na(idx_transition_share)) {
        message("Could not find required columns in sheet ", sheet_name_year_str, " of ", basename(file_path))
        message("Indices found: AGS_hist=", idx_ags_hist,
                ", AGS_2021=", idx_ags_2021,
                ", transition_share=", idx_transition_share,
                ", population=", idx_population)
        return(NULL)
    }

    processed_data <- raw_sheet_data %>%
        select(
            AGS_hist_raw = all_of(idx_ags_hist),
            AGS_2021_raw = all_of(idx_ags_2021),
            transition_share_raw = all_of(idx_transition_share),
            population_raw = if (!is.na(idx_population)) all_of(idx_population) else NULL
        ) %>%
        mutate(
            AGS_hist = standardize_ags_8(AGS_hist_raw),
            AGS_2021 = standardize_ags_8(AGS_2021_raw),
            transition_share = suppressWarnings(as.numeric(transition_share_raw)),
            population_hist = if ("population_raw" %in% names(.)) {
                suppressWarnings(as.numeric(population_raw))
            } else {
                NA_real_
            },
            population_weight = case_when(
                !is.na(population_hist) & !is.na(transition_share) ~ population_hist * transition_share,
                !is.na(transition_share) ~ transition_share,
                TRUE ~ NA_real_
            ),
            year_hist = as.integer(sheet_name_year_str)
        ) %>%
        filter(
            str_detect(AGS_hist, valid_ags_pattern),
            str_detect(AGS_2021, valid_ags_pattern),
            !is.na(transition_share),
            transition_share >= 0,
            !is.na(population_weight),
            population_weight > 0
        ) %>%
        select(AGS_hist, year_hist, AGS_2021, transition_share, population_weight) %>%
        distinct()

    print(paste("Processed sheet", sheet_name_year_str, "- rows extracted:", nrow(processed_data)))
    processed_data
}

build_master_crosswalk <- function() {
    all_crosswalk_data <- list()

    for (year_val in 2005:2020) {
        current_file <- if (year_val <= 2010) merger_file_2000_2010 else merger_file_2011_2020
        sheet_data <- process_merger_sheet(current_file, as.character(year_val))

        if (!is.null(sheet_data) && nrow(sheet_data) > 0) {
            all_crosswalk_data[[length(all_crosswalk_data) + 1]] <- sheet_data
        }
    }

    if (length(all_crosswalk_data) == 0) {
        stop("Master crosswalk generation failed.")
    }

    bind_rows(all_crosswalk_data) %>%
        distinct()
}

resolve_reform_chain <- function(start_ags, source_year, reform_mappings, destatis_ags, max_hops = 25) {
    current_ags <- start_ags
    path <- current_ags

    if (current_ags %in% destatis_ags) {
        return(tibble(
            old_ags = start_ags,
            final_ags_2021 = current_ags,
            hops = 0L,
            path = paste(path, collapse = " -> "),
            status = "already_2021"
        ))
    }

    for (hop in seq_len(max_hops)) {
        candidates <- reform_mappings %>%
            filter(old_ags == current_ags,
                   reform_year >= source_year,
                   reform_year <= 2021) %>%
            arrange(reform_year, new_ags)

        if (nrow(candidates) == 0) {
            break
        }

        earliest_year <- candidates$reform_year[1]
        candidates <- candidates %>% filter(reform_year == earliest_year)

        if (n_distinct(candidates$new_ags) != 1) {
            return(tibble(
                old_ags = start_ags,
                final_ags_2021 = NA_character_,
                hops = hop - 1L,
                path = paste(path, collapse = " -> "),
                status = "ambiguous_reform"
            ))
        }

        next_ags <- candidates$new_ags[1]
        if (next_ags %in% path) {
            return(tibble(
                old_ags = start_ags,
                final_ags_2021 = NA_character_,
                hops = hop - 1L,
                path = paste(c(path, next_ags), collapse = " -> "),
                status = "cycle"
            ))
        }

        path <- c(path, next_ags)
        current_ags <- next_ags

        if (current_ags %in% destatis_ags) {
            return(tibble(
                old_ags = start_ags,
                final_ags_2021 = current_ags,
                hops = hop,
                path = paste(path, collapse = " -> "),
                status = "mapped"
            ))
        }
    }

    tibble(
        old_ags = start_ags,
        final_ags_2021 = NA_character_,
        hops = length(path) - 1L,
        path = paste(path, collapse = " -> "),
        status = "unmapped"
    )
}

build_supplementary_crosswalk <- function(ags_not_in_crosswalk, destatis_ags) {
    stable_crosswalk <- ags_not_in_crosswalk %>%
        filter(AGS %in% destatis_ags) %>%
        transmute(
            AGS_hist_cw = AGS,
            year_hist_cw = year,
            AGS_2021 = AGS,
            transition_share = 1.0,
            population_weight = 1.0,
            source = "destatis_2021_stable"
        )

    if (!file.exists(reform_mapping_file)) {
        reform_crosswalk <- tibble()
        reform_details <- tibble(
            old_ags = character(),
            final_ags_2021 = character(),
            hops = integer(),
            path = character(),
            status = character(),
            source_year = integer()
        )
    } else {
        reform_mappings <- readRDS(reform_mapping_file) %>%
            transmute(
                old_ags = standardize_ags_8(old_ags),
                new_ags = standardize_ags_8(new_ags),
                reform_year = as.integer(reform_year)
            ) %>%
            filter(str_detect(old_ags, valid_ags_pattern),
                   str_detect(new_ags, valid_ags_pattern),
                   !is.na(reform_year)) %>%
            distinct()

        reform_candidates <- ags_not_in_crosswalk %>%
            filter(!AGS %in% destatis_ags) %>%
            distinct(AGS, year)

        reform_details <- pmap_dfr(
            list(reform_candidates$AGS, reform_candidates$year),
            ~ resolve_reform_chain(..1, ..2, reform_mappings, destatis_ags) %>%
                mutate(source_year = ..2)
        )

        reform_crosswalk <- reform_details %>%
            filter(!is.na(final_ags_2021), status == "mapped") %>%
            transmute(
                AGS_hist_cw = old_ags,
                year_hist_cw = source_year,
                AGS_2021 = final_ags_2021,
                transition_share = 1.0,
                population_weight = 1.0,
                source = "gebietsreformen_chain"
            ) %>%
            distinct()
    }

    mapped_details <- reform_details %>%
        filter(!is.na(final_ags_2021), status == "mapped") %>%
        select(old_ags, final_ags_2021, hops, path, source_year, status)

    saveRDS(mapped_details, supplementary_mapping_detail_file)

    supplementary_crosswalk <- bind_rows(stable_crosswalk, reform_crosswalk) %>%
        distinct()

    saveRDS(
        supplementary_crosswalk %>%
            filter(source == "gebietsreformen_chain") %>%
            distinct(AGS_hist = AGS_hist_cw, AGS_2021, source),
        supplementary_crosswalk_file
    )

    print(paste("Supplementary stable 1:1 AGS-year mappings:", nrow(stable_crosswalk)))
    print(paste("Supplementary reform-chain AGS-year mappings:", nrow(reform_crosswalk)))

    supplementary_crosswalk
}

collapse_duplicate_source_metrics <- function(bb_data_hist) {
    duplicate_metrics <- bb_data_hist %>%
        group_by(AGS, year, data_category, technology_group, speed_mbps_gte) %>%
        summarise(n_source_records = n(), .groups = "drop") %>%
        filter(n_source_records > 1)

    if (nrow(duplicate_metrics) > 0) {
        print(paste("Collapsing", nrow(duplicate_metrics), "duplicate AGS-year-tech-speed metrics with max(value)."))
    }

    bb_data_hist %>%
        group_by(AGS, year, data_category, technology_group, speed_mbps_gte) %>%
        summarise(
            value = max(value, na.rm = TRUE),
            original_variable = paste(sort(unique(original_variable)), collapse = "; "),
            source_paket = paste(sort(unique(source_paket)), collapse = "; "),
            n_source_records = n(),
            .groups = "drop"
        )
}

weighted_mean_or_max <- function(value, weight) {
    valid_weight <- !is.na(weight) & weight > 0
    if (any(valid_weight)) {
        return(sum(value[valid_weight] * weight[valid_weight], na.rm = TRUE) /
                   sum(weight[valid_weight], na.rm = TRUE))
    }

    max(value, na.rm = TRUE)
}

# --- Main Script Logic ---
print("Starting AGS standardization to 2021 borders...")

destatis_ags <- load_destatis_ags(ags_reference_file)$AGS
master_crosswalk <- build_master_crosswalk()

print(paste("Master crosswalk built with", nrow(master_crosswalk), "rows."))
print("Validating transition-share sums by historical AGS-year...")
transition_share_validation <- master_crosswalk %>%
    group_by(AGS_hist, year_hist) %>%
    summarise(total_transition_share = sum(transition_share, na.rm = TRUE),
              n_mappings = n(),
              .groups = "drop")

problematic_shares <- transition_share_validation %>%
    filter(total_transition_share < 0.99 | total_transition_share > 1.01)

if (nrow(problematic_shares) > 0) {
    warning("Found ", nrow(problematic_shares), " AGS-year combinations with transition shares outside [0.99, 1.01].")
    print(head(problematic_shares, 50))
} else {
    print("Transition-share validation passed.")
}

if (!file.exists(input_file)) {
    stop("Input file not found. Please run 05_combine_datasets.R first: ", input_file)
}

bb_data_hist <- readRDS(input_file) %>%
    mutate(
        AGS = standardize_ags_8(AGS),
        year = as.integer(year),
        value = as.numeric(value),
        speed_mbps_gte = as.numeric(speed_mbps_gte)
    ) %>%
    filter(str_detect(AGS, valid_ags_pattern),
           !is.na(year),
           !is.na(speed_mbps_gte),
           !is.na(value),
           value >= 0,
           value <= 100)

print(paste("Loaded", nrow(bb_data_hist), "valid combined broadband rows."))

bb_data_hist <- collapse_duplicate_source_metrics(bb_data_hist)
print(paste("Rows after duplicate metric collapse:", nrow(bb_data_hist)))

crosswalk_renamed <- master_crosswalk %>%
    rename(AGS_hist_cw = AGS_hist, year_hist_cw = year_hist) %>%
    mutate(source = "destatis_population_crosswalk")

broadband_ags_years <- bb_data_hist %>% distinct(AGS, year)
crosswalk_ags_years <- crosswalk_renamed %>% distinct(AGS_hist_cw, year_hist_cw)

ags_not_in_crosswalk <- broadband_ags_years %>%
    anti_join(crosswalk_ags_years, by = c("AGS" = "AGS_hist_cw", "year" = "year_hist_cw"))

print(paste("AGS-year combinations not covered by official crosswalk:", nrow(ags_not_in_crosswalk)))

supplementary_crosswalk <- build_supplementary_crosswalk(ags_not_in_crosswalk, destatis_ags)

crosswalk_for_join <- bind_rows(crosswalk_renamed, supplementary_crosswalk) %>%
    distinct(AGS_hist_cw, year_hist_cw, AGS_2021, transition_share, population_weight, source)

joined_data <- bb_data_hist %>%
    left_join(
        crosswalk_for_join,
        by = c("AGS" = "AGS_hist_cw", "year" = "year_hist_cw"),
        relationship = "many-to-many"
    )

missing_join_info <- joined_data %>%
    filter(is.na(AGS_2021) | is.na(population_weight))

if (nrow(missing_join_info) > 0) {
    drop_row_share <- nrow(missing_join_info) / nrow(joined_data)
    drop_unit_share <- n_distinct(missing_join_info$AGS) / n_distinct(joined_data$AGS)

    unmapped_ags <- missing_join_info %>%
        distinct(AGS) %>%
        arrange(AGS)

    write_csv(unmapped_ags, unmapped_ags_file)

    print(paste("Filtering", nrow(missing_join_info), "rows with no valid 2021 AGS mapping."))
    print(paste("Affected unique historical AGS:", nrow(unmapped_ags)))
    print(paste("Row share:", round(100 * drop_row_share, 2), "%"))
    print(paste("Unit share:", round(100 * drop_unit_share, 2), "%"))

    if (drop_row_share > 0.20 || drop_unit_share > 0.20) {
        stop("More than 20% of rows or units lack a 2021 AGS mapping. Inspect ", unmapped_ags_file)
    }
} else {
    write_csv(tibble(AGS = character()), unmapped_ags_file)
    print("All rows have a valid 2021 AGS mapping.")
}

joined_data <- joined_data %>%
    filter(!is.na(AGS_2021), !is.na(population_weight)) %>%
    filter(AGS_2021 %in% destatis_ags)

print(paste("Rows retained after AGS mapping:", nrow(joined_data)))

standardized_data <- joined_data %>%
    group_by(AGS_2021, year, data_category, technology_group, speed_mbps_gte) %>%
    summarise(
        value = weighted_mean_or_max(value, population_weight),
        original_variable = paste(sort(unique(original_variable)), collapse = "; "),
        source_paket = paste(sort(unique(source_paket)), collapse = "; "),
        n_agg = n(),
        .groups = "drop"
    ) %>%
    rename(AGS = AGS_2021) %>%
    mutate(
        value = case_when(
            value < 0 & value > -1e-8 ~ 0,
            value > 100 & value < 100 + 1e-8 ~ 100,
            TRUE ~ value
        )
    )

out_of_bounds <- standardized_data %>%
    filter(value < 0 | value > 100 | is.na(value))

if (nrow(out_of_bounds) > 0) {
    print(head(out_of_bounds, 50))
    stop("Standardized data contains missing or out-of-bounds percentage values.")
}

invalid_output_ags <- standardized_data %>% filter(!AGS %in% destatis_ags)
if (nrow(invalid_output_ags) > 0) {
    print(head(invalid_output_ags, 50))
    stop("Standardized data contains AGS codes outside the Destatis 2021 reference.")
}

print(paste("Standardized data has", nrow(standardized_data), "rows."))
print(paste("Number of unique 2021 AGS:", n_distinct(standardized_data$AGS)))
print("Summary of aggregated value column:")
print(summary(standardized_data$value))
print("Year counts:")
print(standardized_data %>% count(year) %>% arrange(year), n = Inf)

saveRDS(standardized_data, file = output_file)
print(paste("Saved AGS-2021 standardized data to:", output_file))
print("--- Script Finished ---")
