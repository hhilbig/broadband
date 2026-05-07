library(tidyverse)
library(here)

# 1. Read cleaned long data ----------
input_file <- here("output", "broadband_gemeinde_combined_long_ags2021.rds")
ags_reference_file <- here("data", "ags_reference", "destatis_ags_2021.rds")
output_file_panel <- here("output", "panel_data_with_treatment.csv")
output_file_panel_public <- here("output", "panel_data_public.csv")
output_plot_avg_coverage <- here("output", "average_annual_coverage_plot.png")
output_plot_yoy <- here("output", "large_yoy_changes_plot.png")

valid_ags_pattern <- "^(0[1-9]|1[0-6])\\d{6}$"
share_cols <- c(
    "share_broadband_baseline",
    "share_gte1mbps",
    "share_gte6mbps",
    "share_gte30mbps"
)

max_or_na <- function(x) {
    if (length(x) == 0 || all(is.na(x))) {
        return(NA_real_)
    }

    max(x, na.rm = TRUE)
}

threshold_max <- function(values, speeds, threshold) {
    max_or_na(values[speeds >= threshold])
}

validate_drop <- function(n_drop, n_total, label) {
    pct_drop <- ifelse(n_total > 0, n_drop / n_total, 0)
    print(paste(label, "rows to filter:", n_drop, "of", n_total,
                paste0("(", round(100 * pct_drop, 2), "%)")))

    if (pct_drop > 0.20) {
        stop(label, " would filter more than 20% of rows. Inspect before proceeding.")
    }
}

if (!file.exists(input_file)) {
    stop("Input file not found: ", input_file, "\nPlease run 06_standardize_ags_to_2021.R first.")
}

if (!file.exists(ags_reference_file)) {
    stop("AGS reference file not found: ", ags_reference_file)
}

destatis_ags <- readRDS(ags_reference_file) %>%
    mutate(AGS = as.character(AGS)) %>%
    filter(str_detect(AGS, valid_ags_pattern)) %>%
    distinct(AGS)

bb_long_raw <- readRDS(input_file)
print(paste("Loaded", nrow(bb_long_raw), "rows and", ncol(bb_long_raw),
            "columns from", basename(input_file)))

rows_invalid_for_panel <- bb_long_raw %>%
    filter(
        is.na(AGS) |
            !str_detect(AGS, valid_ags_pattern) |
            !AGS %in% destatis_ags$AGS |
            is.na(year) |
            is.na(speed_mbps_gte) |
            is.na(value) |
            value < 0 |
            value > 100
    )

validate_drop(nrow(rows_invalid_for_panel), nrow(bb_long_raw), "Initial panel validation")

bb_long <- bb_long_raw %>%
    mutate(
        AGS = as.character(AGS),
        year = as.integer(year),
        speed_mbps_gte = as.numeric(speed_mbps_gte),
        value = as.numeric(value)
    ) %>%
    filter(
        str_detect(AGS, valid_ags_pattern),
        AGS %in% destatis_ags$AGS,
        !is.na(year),
        !is.na(speed_mbps_gte),
        !is.na(value),
        value >= 0,
        value <= 100
    )

print("--- Long-data diagnostics before panel construction ---")
print(bb_long %>%
          summarise(
              rows = n(),
              n_ags = n_distinct(AGS),
              year_min = min(year),
              year_max = max(year),
              speed_0128_rows = sum(speed_mbps_gte == 0.128, na.rm = TRUE),
              speed_0_rows = sum(speed_mbps_gte == 0, na.rm = TRUE),
              max_value = max(value, na.rm = TRUE)
          ))
print(bb_long %>% count(year) %>% arrange(year), n = Inf)

# 2. Collapse to "any technology" per speed threshold ----------
panel <- bb_long %>%
    group_by(AGS, year, speed_mbps_gte) %>%
    summarise(coverage_at_specific_speed = max(value, na.rm = TRUE), .groups = "drop") %>%
    group_by(AGS, year) %>%
    summarise(
        share_broadband_baseline = threshold_max(coverage_at_specific_speed, speed_mbps_gte, 0.128),
        share_gte1mbps = threshold_max(coverage_at_specific_speed, speed_mbps_gte, 1),
        share_gte6mbps = threshold_max(coverage_at_specific_speed, speed_mbps_gte, 6),
        share_gte30mbps = threshold_max(coverage_at_specific_speed, speed_mbps_gte, 30),
        .groups = "drop"
    ) %>%
    mutate(method_change_2015 = if_else(year == 2015L, 1L, 0L))

if (any(duplicated(panel[, c("AGS", "year")]))) {
    stop("AGS-year combinations are not unique in the panel.")
}

share_out_of_bounds <- panel %>%
    filter(if_any(all_of(share_cols), ~ !is.na(.x) & (.x < 0 | .x > 100)))

if (nrow(share_out_of_bounds) > 0) {
    print(head(share_out_of_bounds, 50))
    stop("Panel share columns contain out-of-bounds values.")
}

hierarchy_violations <- panel %>%
    filter(
        (!is.na(share_broadband_baseline) & !is.na(share_gte1mbps) & share_broadband_baseline < share_gte1mbps) |
            (!is.na(share_gte1mbps) & !is.na(share_gte6mbps) & share_gte1mbps < share_gte6mbps) |
            (!is.na(share_gte6mbps) & !is.na(share_gte30mbps) & share_gte6mbps < share_gte30mbps)
    )

if (nrow(hierarchy_violations) > 0) {
    print(head(hierarchy_violations, 50))
    stop("Panel share columns violate speed-tier hierarchy.")
}

print("--- Panel diagnostics after speed bucket aggregation ---")
print(paste("Panel dimensions:", nrow(panel), "rows,", ncol(panel), "columns"))
print(panel %>%
          summarise(
              n_ags = n_distinct(AGS),
              n_years = n_distinct(year),
              across(all_of(share_cols), list(na = ~ sum(is.na(.x)),
                                              mean = ~ mean(.x, na.rm = TRUE),
                                              max = ~ max(.x, na.rm = TRUE)))
          ))
print(panel %>%
          group_by(year) %>%
          summarise(across(all_of(share_cols), ~ sum(is.na(.x))), .groups = "drop") %>%
          arrange(year),
      n = Inf)

panel_gaps <- panel %>%
    count(AGS, name = "n_years_observed") %>%
    filter(n_years_observed < n_distinct(panel$year))

print(paste("AGS with at least one missing year in the observed panel:", nrow(panel_gaps)))

# 3. Create treatment variables ----------
panel <- panel %>%
    mutate(
        treat_low = case_when(
            is.na(share_gte1mbps) ~ NA_integer_,
            share_gte1mbps >= 50 ~ 1L,
            TRUE ~ 0L
        ),
        treat_medium = case_when(
            is.na(share_gte6mbps) ~ NA_integer_,
            share_gte6mbps >= 50 ~ 1L,
            TRUE ~ 0L
        ),
        treat_high = case_when(
            is.na(share_gte30mbps) ~ NA_integer_,
            share_gte30mbps >= 50 ~ 1L,
            TRUE ~ 0L
        ),
        log_share6 = if_else(is.na(share_gte6mbps), NA_real_, log1p(share_gte6mbps))
    )

first50_6 <- panel %>%
    filter(treat_medium == 1L) %>%
    group_by(AGS) %>%
    summarise(first_year50_6 = min(year), .groups = "drop")

panel <- panel %>%
    left_join(first50_6, by = "AGS") %>%
    mutate(event_time = if_else(!is.na(first_year50_6), year - first_year50_6, NA_integer_))

print("--- Treatment diagnostics ---")
print("Counts for treat_low:")
print(table(panel$treat_low, useNA = "ifany"))
print("Counts for treat_medium:")
print(table(panel$treat_medium, useNA = "ifany"))
print("Counts for treat_high:")
print(table(panel$treat_high, useNA = "ifany"))
print("Summary of event_time:")
print(summary(panel$event_time))

if (panel %>% filter(treat_medium == 1L & is.na(first_year50_6)) %>% nrow() > 0) {
    stop("Rows with treat_medium == 1 have missing first_year50_6.")
}

if (panel %>% filter(is.na(first_year50_6) & !is.na(event_time)) %>% nrow() > 0) {
    stop("Rows with missing first_year50_6 have non-missing event_time.")
}

# 4. Save panel outputs ----------
write_csv(panel, output_file_panel)
print(paste("Saved final panel data to:", output_file_panel))

panel_public <- panel %>%
    select(
        AGS,
        year,
        share_broadband_baseline,
        share_gte1mbps,
        share_gte6mbps,
        share_gte30mbps,
        method_change_2015
    )

write_csv(panel_public, output_file_panel_public)
print(paste("Saved public panel data to:", output_file_panel_public))

# 5. Generate diagnostic plots ----------
yoy_changes_diagnostic <- panel %>%
    arrange(AGS, year) %>%
    group_by(AGS) %>%
    mutate(
        yoy_diff_baseline = share_broadband_baseline - lag(share_broadband_baseline),
        yoy_diff_gte30 = share_gte30mbps - lag(share_gte30mbps)
    ) %>%
    ungroup()

large_increases <- yoy_changes_diagnostic %>%
    filter(yoy_diff_baseline > 50 | yoy_diff_gte30 > 50)
large_decreases <- yoy_changes_diagnostic %>%
    filter(yoy_diff_baseline < -20 | yoy_diff_gte30 < -20)

print(paste("Large (>50ppt) year-on-year increases:", nrow(large_increases)))
print(paste("Large (<-20ppt) year-on-year decreases:", nrow(large_decreases)))

plot_yoy_dist <- yoy_changes_diagnostic %>%
    select(year, yoy_diff_baseline, yoy_diff_gte30) %>%
    pivot_longer(
        cols = c(yoy_diff_baseline, yoy_diff_gte30),
        names_to = "share_type",
        values_to = "yoy_diff"
    ) %>%
    filter(!is.na(yoy_diff)) %>%
    ggplot(aes(x = as.factor(year), y = yoy_diff)) +
    geom_boxplot() +
    facet_wrap(~share_type, scales = "free_y") +
    labs(
        title = "Distribution of Year-on-Year Coverage Changes",
        x = "Year",
        y = "Year-on-Year Change (Percentage Points)"
    ) +
    theme_minimal()

ggsave(output_plot_yoy, plot_yoy_dist, width = 12, height = 6)
print(paste("Saved year-on-year change plot to:", output_plot_yoy))

avg_coverage_data <- panel %>%
    select(year, all_of(share_cols)) %>%
    pivot_longer(
        cols = all_of(share_cols),
        names_to = "share_type",
        values_to = "coverage"
    ) %>%
    group_by(year, share_type) %>%
    summarise(mean_coverage = mean(coverage, na.rm = TRUE), .groups = "drop") %>%
    filter(is.finite(mean_coverage)) %>%
    mutate(share_type = factor(share_type, levels = share_cols))

avg_coverage_plot <- ggplot(avg_coverage_data, aes(x = year, y = mean_coverage, color = share_type)) +
    geom_line(linewidth = 1) +
    geom_point(size = 2) +
    labs(
        title = "Average Annual Broadband Coverage by Share Type",
        x = "Year",
        y = "Mean Coverage (%)",
        color = "Share Type"
    ) +
    scale_y_continuous(labels = scales::label_number(suffix = "%")) +
    theme_minimal() +
    theme(legend.position = "bottom")

ggsave(output_plot_avg_coverage, plot = avg_coverage_plot, width = 10, height = 6)
print(paste("Saved average annual coverage plot to:", output_plot_avg_coverage))

print("--- Script Finished ---")
