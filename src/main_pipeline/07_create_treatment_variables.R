library(tidyverse)
library(here)

# 1. Read cleaned long data ----------
input_file <- here("output", "broadband_gemeinde_combined_long_ags2021.rds")
output_file_panel <- here("output", "panel_data_with_treatment.csv")
output_plot_avg_coverage <- here("output", "average_annual_coverage_plot.png")

if (!file.exists(input_file)) {
    stop(paste("Input file not found:", input_file, "\nPlease run the standardization script (06_standardize_ags_to_2021.R) first."))
}

bb_long <- readRDS(input_file)

print(paste("Loaded", nrow(bb_long), "rows and", ncol(bb_long), "columns from", basename(input_file)))

# --- Diagnostics for bb_long ---
print("--- Initial bb_long diagnostics ---")
print("Summary of 'value' column in bb_long:")
print(summary(bb_long$value))
print(paste("Number of NAs in 'value':", sum(is.na(bb_long$value))))

na_speed_rows <- sum(is.na(bb_long$speed_mbps_gte))
print(paste("Rows with NA in 'speed_mbps_gte' (will be filtered):", na_speed_rows))

value_outside_0_100 <- bb_long %>%
    filter(!is.na(value) & (value < 0 | value > 100)) %>%
    nrow()
print(paste("Rows with 'value' outside [0, 100] (will be filtered if not NA):", value_outside_0_100))

# --- ADDED DETAILED DIAGNOSTICS ---
print("--- Detailed diagnostics for bb_long (pre-filtering), by year ---")
bb_long %>%
    group_by(year) %>%
    summarise(
        total_rows = n(),
        na_speed_mbps_gte = sum(is.na(speed_mbps_gte)),
        na_value = sum(is.na(value)),
        value_lt_0 = sum(value < 0, na.rm = TRUE),
        value_gt_100 = sum(value > 100, na.rm = TRUE),
        rows_with_na_speed_or_na_value = sum(is.na(speed_mbps_gte) | is.na(value)),
        rows_with_value_out_of_range = sum(!is.na(value) & (value < 0 | value > 100)),
        valid_value_and_speed_rows = sum(!is.na(speed_mbps_gte) & !is.na(value) & value >= 0 & value <= 100),
        .groups = "drop"
    ) %>%
    arrange(year) %>%
    print(n = Inf)

print("--- Rows that will be DROPPED by initial filters (is.na(speed_mbps_gte) | is.na(value) | value < 0 | value > 100), by year ---")
bb_long %>%
    filter(is.na(speed_mbps_gte) | is.na(value) | value < 0 | value > 100) %>%
    group_by(year) %>%
    summarise(rows_to_be_dropped_by_filters = n(), .groups = "drop") %>%
    arrange(year) %>%
    print(n = Inf)

print("--- Example rows from bb_long for years 2005-2009 (pre-filtering) ---")
example_early_years_data <- bb_long %>%
    filter(year >= 2005 & year <= 2009) %>%
    arrange(year, AGS)

if (nrow(example_early_years_data) > 0) {
    print(paste("Found", nrow(example_early_years_data), "rows for 2005-2009. Showing first 20:"))
    print(head(example_early_years_data, 20))

    print("Summary of 'value' and 'speed_mbps_gte' for 2005-2009 example data:")
    print(summary(example_early_years_data %>% select(year, value, speed_mbps_gte)))

    print("Counts of NA 'value' in 2005-2009 example data, by year:")
    example_early_years_data %>%
        group_by(year) %>%
        summarise(na_value_count = sum(is.na(value))) %>%
        print()

    print("Counts of NA 'speed_mbps_gte' in 2005-2009 example data, by year:")
    example_early_years_data %>%
        group_by(year) %>%
        summarise(na_speed_count = sum(is.na(speed_mbps_gte))) %>%
        print()
} else {
    print("No data found for years 2005-2009 in bb_long to show examples.")
}
# --- END OF ADDED DETAILED DIAGNOSTICS ---

# 2. Collapse to "any technology" per speed threshold ----------
# Note: The `value` in bb_long is typically a percentage (0-100) representing coverage or households with access.
# If it's a count, this approach might need adjustment (e.g. dividing by total households).
# For this script, we assume 'value' is already a percentage share (0-100) as implied by the blueprint.

panel <- bb_long %>%
    filter(!is.na(speed_mbps_gte)) %>% # Ignore non-speed rows (e.g., where speed_mbps_gte is NA)
    filter(value >= 0 & value <= 100) %>% # Ensure value is a percentage, filter out anomalies if any
    # First, ensure that for a given AGS, year, and speed, we have only one value (the max)
    group_by(AGS, year, speed_mbps_gte) %>%
    summarise(coverage_at_specific_speed = max(value), .groups = "drop") %>%
    # Now, create the share columns. This is the key part.
    group_by(AGS, year) %>%
    summarise(
        # Create a baseline share variable that includes the historical >=0.128 Mbps data
        share_broadband_baseline = max(coverage_at_specific_speed[speed_mbps_gte >= 0.128], 0, na.rm = TRUE),
        # For each speed bucket, find the max coverage of any tech at or above that speed
        share_gte1mbps = max(coverage_at_specific_speed[speed_mbps_gte >= 1], 0, na.rm = TRUE),
        share_gte6mbps = max(coverage_at_specific_speed[speed_mbps_gte >= 6], 0, na.rm = TRUE),
        share_gte30mbps = max(coverage_at_specific_speed[speed_mbps_gte >= 30], 0, na.rm = TRUE)
    ) %>%
    ungroup()

# --- Enforce Hierarchical Consistency in Share Columns ---
print("--- Enforcing Hierarchical Consistency in Share Columns ---")
if (all(c("share_gte30mbps", "share_gte6mbps", "share_gte1mbps", "share_broadband_baseline") %in% names(panel))) {
    print("--- Enforcing hierarchical consistency in share columns ---")
    panel <- panel %>%
        mutate(
            share_gte6mbps = pmax(share_gte6mbps, share_gte30mbps, na.rm = TRUE),
            share_gte1mbps = pmax(share_gte1mbps, share_gte6mbps, na.rm = TRUE),
            share_broadband_baseline = pmax(share_broadband_baseline, share_gte1mbps, na.rm = TRUE)
        )
} else {
    print("Skipping hierarchical consistency check due to missing share columns.")
}
# -----------------------------------------------------------

# --- Add dummy for 2015 methodological change ---
print("--- Adding dummy variable for 2015 methodological change ---")
panel <- panel %>%
    mutate(method_change_2015 = ifelse(year == 2015, 1, 0))

print("Count of observations with method_change_2015 dummy:")
print(table(panel$method_change_2015, useNA = "ifany"))
# ----------------------------------------------------

# --- Diagnostics for panel after aggregation/widening ---
print("--- Panel (after aggregation & hierarchy enforcement) diagnostics ---")
print(paste("Panel dimensions:", nrow(panel), "rows,", ncol(panel), "columns"))

# Check for uniqueness of AGS-year combinations
if (any(duplicated(panel[, c("AGS", "year")]))) {
    warning("AGS-year combinations are NOT unique in the panel. Check aggregation logic.")
} else {
    print("AGS-year combinations are unique in the panel. OK.")
}

# Summary of share columns
print("Summary of share columns:")
if ("share_broadband_baseline" %in% names(panel)) print(summary(panel$share_broadband_baseline))
if ("share_gte1mbps" %in% names(panel)) print(summary(panel$share_gte1mbps))
if ("share_gte6mbps" %in% names(panel)) print(summary(panel$share_gte6mbps))
if ("share_gte30mbps" %in% names(panel)) print(summary(panel$share_gte30mbps))

# Max value check
max_share_val <- max(sapply(panel[grep("share_", names(panel))], max, na.rm = TRUE))
print(paste("Max value across all share columns (should be <= 100):", max_share_val))

# --- Sanity Check: Large Year-on-Year Changes in Share Columns ---
# This check helps identify potential data errors or significant events (like the 2015 change)
yoy_changes_diagnostic <- panel %>%
    arrange(AGS, year) %>%
    group_by(AGS) %>%
    mutate(
        yoy_diff_baseline = share_broadband_baseline - lag(share_broadband_baseline),
        yoy_diff_gte30 = share_gte30mbps - lag(share_gte30mbps)
    ) %>%
    ungroup()

large_increases <- yoy_changes_diagnostic %>% filter(yoy_diff_baseline > 50 | yoy_diff_gte30 > 50)
large_decreases <- yoy_changes_diagnostic %>% filter(yoy_diff_baseline < -20 | yoy_diff_gte30 < -20)

print(paste("Found", nrow(large_increases), "instances of large (>50ppt) year-on-year increases in baseline or gte30 coverage."))
print(paste("Found", nrow(large_decreases), "instances of large (<-20ppt) year-on-year decreases."))

# Plotting the distribution of these changes by year can be insightful
plot_yoy_dist <- yoy_changes_diagnostic %>%
    select(year, yoy_diff_baseline, yoy_diff_gte30) %>%
    pivot_longer(cols = c(yoy_diff_baseline, yoy_diff_gte30), names_to = "share_type", values_to = "yoy_diff") %>%
    filter(!is.na(yoy_diff)) %>%
    ggplot(aes(x = as.factor(year), y = yoy_diff)) +
    geom_boxplot() +
    facet_wrap(~share_type, scales = "free_y") +
    labs(
        title = "Distribution of Year-on-Year Coverage Changes",
        subtitle = "The 2015 jump is clearly visible. Other years show smaller variations.",
        x = "Year",
        y = "Year-on-Year Change (Percentage Points)"
    ) +
    theme_minimal()

ggsave(here("output", "large_yoy_changes_plot.png"), plot_yoy_dist, width = 12, height = 6)
print(paste("Saved plot of year-on-year change distributions to:", here("output", "large_yoy_changes_plot.png")))

print("Panel after speed bucket aggregation and widening (first 6 rows):")
print(head(panel))

# 3. Create treatment variables ----------
panel <- panel %>%
    mutate(
        treat_low     = as.integer(share_gte1mbps >= 50), # ≥ 50 % can get 1 Mbit/s
        treat_medium  = as.integer(share_gte6mbps >= 50), # ≥ 50 % can get 6 Mbit/s
        treat_high    = as.integer(share_gte30mbps >= 50), # ≥ 50 % can get 30 Mbit/s
        log_share6    = log1p(share_gte6mbps) # continuous variant often preferred
    )

# --- Diagnostics for treatment variables ---
print("--- Treatment variable diagnostics ---")
print(paste("Panel dimensions after treatment vars:", nrow(panel), "rows,", ncol(panel), "columns"))
print("Counts for treat_low (0=No, 1=Yes):")
print(table(panel$treat_low, useNA = "ifany"))
print("Counts for treat_medium (0=No, 1=Yes):")
print(table(panel$treat_medium, useNA = "ifany"))
print("Counts for treat_high (0=No, 1=Yes):")
print(table(panel$treat_high, useNA = "ifany"))
print("Summary of log_share6:")
print(summary(panel$log_share6))
# -----------------------------------------

print("Panel after creating treatment variables (first 6 rows):")
print(head(panel))

# 4. Derive event-study timing variable ----------
# Identify the first year each AGS meets the 'treat_medium' condition
first50_6 <- panel %>%
    filter(treat_medium == 1) %>%
    group_by(AGS) %>%
    summarise(first_year50_6 = min(year, na.rm = TRUE), .groups = "drop")

panel <- panel %>%
    left_join(first50_6, by = "AGS") %>%
    mutate(
        event_time = ifelse(!is.na(first_year50_6), year - first_year50_6, NA_integer_)
    ) # Negative before adoption, 0 in adoption year, positive after. NA if never adopted.

# --- Diagnostics for event study variables ---
print("--- Event study diagnostics ---")
print(paste("Panel dimensions after event_time:", nrow(panel), "rows,", ncol(panel), "columns"))
print("Summary of first_year50_6 (year of first treat_medium=1):")
print(summary(panel$first_year50_6))
num_na_first_year <- sum(is.na(panel$first_year50_6))
print(paste("NAs in first_year50_6 (AGS never treated or no data for treatment year):", num_na_first_year))
print("Summary of event_time:")
print(summary(panel$event_time))
num_na_event_time <- sum(is.na(panel$event_time))
print(paste("NAs in event_time:", num_na_event_time))

# Sanity Checks
check1 <- panel %>%
    filter(treat_medium == 1 & is.na(first_year50_6)) %>%
    nrow()
if (check1 == 0) {
    print("Sanity Check 1: All rows with treat_medium=1 have a non-NA first_year50_6. OK.")
} else {
    print(paste("ERROR Sanity Check 1: Found", check1, "rows with treat_medium=1 but NA first_year50_6."))
}

check2 <- panel %>%
    filter(!is.na(first_year50_6) & year == first_year50_6 & event_time != 0) %>%
    nrow()
if (check2 == 0) {
    print("Sanity Check 2: For all rows where year == first_year50_6, event_time is 0. OK.")
} else {
    print(paste("ERROR Sanity Check 2: Found", check2, "rows where year == first_year50_6 but event_time is not 0."))
}

check3 <- panel %>%
    filter(is.na(first_year50_6) & !is.na(event_time)) %>%
    nrow()
if (check3 == 0) {
    print("Sanity Check 3: If first_year50_6 is NA, event_time is also NA. OK.")
} else {
    print(paste("ERROR Sanity Check 3: Found", check3, "rows where first_year50_6 is NA but event_time is not NA."))
}
# -------------------------------------------

print("Final panel structure with event_time (first 20 rows):")
print(head(panel, 20))

print("Overall summary of the final panel data:")
summary(panel)

# Save the final panel dataset
write_csv(panel, output_file_panel)
print(paste("Saved final panel data to:", output_file_panel))

# 5. Create and save public version of the dataset ----------
print("--- Creating and saving public version of the panel data ---")
output_file_panel_public <- here("output", "panel_data_public.csv")

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
# ----------------------------------------------------

print("--- Script Finished ---")

# --- Generate and Save Average Annual Coverage Plot ---
print("--- Generating Average Annual Coverage Plot ---")

# Define the share columns to plot
share_cols_to_plot <- c("share_broadband_baseline", "share_gte1mbps", "share_gte6mbps", "share_gte30mbps")

# Check which of the expected columns are actually in the panel
existing_share_cols <- intersect(share_cols_to_plot, names(panel))

if (length(existing_share_cols) > 0) {
    avg_coverage_data <- panel %>%
        select(year, all_of(existing_share_cols)) %>%
        pivot_longer(
            cols = all_of(existing_share_cols),
            names_to = "share_type",
            values_to = "coverage"
        ) %>%
        group_by(year, share_type) %>%
        summarise(
            mean_coverage = mean(coverage, na.rm = TRUE),
            .groups = "drop"
        ) %>%
        mutate(
            share_type = factor(share_type, levels = share_cols_to_plot) # Ensure consistent order in plot
        )

    avg_coverage_plot <- ggplot(avg_coverage_data, aes(x = year, y = mean_coverage, color = share_type)) +
        geom_line(linewidth = 1) +
        geom_point(size = 2) +
        labs(
            title = "Average Annual Broadband Coverage by Share Type",
            subtitle = "Mean coverage across all municipalities",
            x = "Year",
            y = "Mean Coverage (%)",
            color = "Share Type"
        ) +
        scale_y_continuous(labels = scales::percent) +
        theme_minimal() +
        theme(legend.position = "bottom")

    ggsave(output_plot_avg_coverage, plot = avg_coverage_plot, width = 10, height = 6)
    print(paste("Saved average annual coverage plot to:", output_plot_avg_coverage))
} else {
    print("Skipping average annual coverage plot as no share columns were found.")
}

# Rationales from blueprint for thresholds:
# Threshold  | Rationale
# ≥ 1 Mbit/s | Minimal functional web browsing & early Facebook/Twitter (circa 2006).
# ≥ 6 Mbit/s | Stable video calls/live streams—captures the interaction and video push after ~2010.
# ≥ 30 Mbit/s| EU Digital Agenda 2020 benchmark for "Next-Gen Access"; robustness check for very high speeds.
