library(tidyverse)
library(here)

# 1. Read cleaned long data ----------
input_file <- here("output", "broadband_gemeinde_combined_long_ags2021.csv")
output_file_panel <- here("output", "panel_data_with_treatment.csv")
output_plot_avg_coverage <- here("output", "average_annual_coverage_plot.png")

if (!file.exists(input_file)) {
    stop(paste("Input file not found:", input_file, "\nPlease run combine_datasets.R first."))
}

bb_long <- read_csv(input_file,
    col_types = cols(
        AGS = col_character(),
        year = col_integer(),
        data_category = col_character(), # Added based on actual combined file structure
        technology_group = col_character(), # Added based on actual combined file structure
        speed_mbps_gte = col_integer(),
        value = col_double(),
        original_variable = col_character(), # Added
        source_paket = col_character() # Added
    )
)

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
    group_by(AGS, year, speed_mbps_gte) %>%
    # Take the maximum reported coverage for any specific technology at that speed, AGS, and year
    summarise(coverage_at_specific_speed = max(value, na.rm = TRUE), .groups = "drop") %>%
    # Define speed buckets. This is where we aggregate coverage across different specific speeds into broader buckets.
    # For example, if a municipality has 50% coverage at 30Mbit/s and 60% at 50Mbit/s,
    # both fall into "≥30" bucket. We then want the max coverage for that bucket.
    mutate(speed_bucket = case_when(
        speed_mbps_gte >= 1 & speed_mbps_gte < 6 ~ "gte1",
        speed_mbps_gte >= 6 & speed_mbps_gte < 30 ~ "gte6",
        speed_mbps_gte >= 30 ~ "gte30",
        TRUE ~ NA_character_
    )) %>%
    filter(!is.na(speed_bucket)) %>%
    # Now, for each AGS, year, and speed_bucket, find the maximum coverage achieved.
    # This correctly handles cases where multiple speed_mbps_gte values fall into the same bucket.
    # For example, if AGS X in Year Y has 70% for 30Mbps and 60% for 50Mbps,
    # both are in bucket '≥30'. The share for '≥30' for AGS X in Year Y will be max(70, 60) = 70%.
    group_by(AGS, year, speed_bucket) %>%
    summarise(share = max(coverage_at_specific_speed, na.rm = TRUE), .groups = "drop") %>%
    # Handle cases where max results in -Inf if all values were NA in a group
    mutate(share = ifelse(is.infinite(share) | is.na(share), 0, share)) %>%
    pivot_wider(
        names_from = speed_bucket,
        names_glue = "share_{speed_bucket}mbps",
        values_from = share, # ensure this is specified
        values_fill = 0
    ) # ensure this fills for the correct column if using list

# Ensure all expected share columns exist, even if no data fell into a bucket for any AGS/year combo
# (pivot_wider with values_fill should handle this, but this is an explicit check/addition)
expected_share_cols <- c("share_gte1mbps", "share_gte6mbps", "share_gte30mbps")
for (col_name in expected_share_cols) {
    if (!col_name %in% names(panel)) {
        panel[[col_name]] <- 0
    }
}

# --- Enforce Hierarchical Consistency in Share Columns ---
print("--- Enforcing Hierarchical Consistency in Share Columns ---")
if (all(expected_share_cols %in% names(panel))) {
    # Track adjustments
    adjusted_gte6 <- sum(panel$share_gte6mbps < panel$share_gte30mbps & !is.na(panel$share_gte6mbps) & !is.na(panel$share_gte30mbps), na.rm = TRUE)
    panel <- panel %>%
        mutate(share_gte6mbps = pmax(share_gte6mbps, share_gte30mbps, na.rm = TRUE))
    print(paste("Adjusted", adjusted_gte6, "rows for share_gte6mbps to be at least share_gte30mbps."))

    # After share_gte6mbps is adjusted, use it to adjust share_gte1mbps
    adjusted_gte1 <- sum(panel$share_gte1mbps < panel$share_gte6mbps & !is.na(panel$share_gte1mbps) & !is.na(panel$share_gte6mbps), na.rm = TRUE)
    panel <- panel %>%
        mutate(share_gte1mbps = pmax(share_gte1mbps, share_gte6mbps, na.rm = TRUE))
    print(paste("Adjusted", adjusted_gte1, "rows for share_gte1mbps to be at least share_gte6mbps (after gte6 was potentially adjusted by gte30)."))

    # Re-summarize share columns after adjustment
    print("Summary of share columns after hierarchical adjustment:")
    if ("share_gte1mbps" %in% names(panel)) print(summary(panel$share_gte1mbps))
    if ("share_gte6mbps" %in% names(panel)) print(summary(panel$share_gte6mbps))
    if ("share_gte30mbps" %in% names(panel)) print(summary(panel$share_gte30mbps))
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

duplicate_ags_year <- panel %>%
    count(AGS, year) %>%
    filter(n > 1) %>%
    nrow()
if (duplicate_ags_year == 0) {
    print("AGS-year combinations are unique in the panel. OK.")
} else {
    print(paste("ERROR: Found", duplicate_ags_year, "duplicate AGS-year combinations in the panel."))
}

print("Summary of share columns:")
if ("share_gte1mbps" %in% names(panel)) print(summary(panel$share_gte1mbps))
if ("share_gte6mbps" %in% names(panel)) print(summary(panel$share_gte6mbps))
if ("share_gte30mbps" %in% names(panel)) print(summary(panel$share_gte30mbps))
print(paste("Max value across all share columns (should be <= 100):"))
print(max(select(panel, starts_with("share_")), na.rm = TRUE))

# --- Sanity Check: Large year-on-year changes in shares ---
print("--- Sanity Check: Large Year-on-Year Changes in Share Columns ---")
if (nrow(panel) > 0 && all(c("AGS", "year", expected_share_cols) %in% names(panel))) {
    yoy_changes <- panel %>%
        arrange(AGS, year) %>%
        group_by(AGS) %>%
        mutate(
            lag_year = lag(year, 1),
            lag_share1 = lag(share_gte1mbps, 1),
            lag_share6 = lag(share_gte6mbps, 1),
            lag_share30 = lag(share_gte30mbps, 1),
            diff_share1 = share_gte1mbps - lag_share1,
            diff_share6 = share_gte6mbps - lag_share6,
            diff_share30 = share_gte30mbps - lag_share30
        ) %>%
        ungroup() %>%
        filter(year == lag_year + 1) # Only consider consecutive years

    large_increase_threshold <- 50
    significant_decrease_threshold <- -20 # Represents a drop of 20ppt or more

    # Check for Large Increases
    flagged_increases <- yoy_changes %>%
        filter(
            (diff_share1 > large_increase_threshold & !is.na(diff_share1)) |
                (diff_share6 > large_increase_threshold & !is.na(diff_share6)) |
                (diff_share30 > large_increase_threshold & !is.na(diff_share30))
        ) %>%
        select(AGS, year, lag_year, starts_with("share_"), starts_with("lag_share"), starts_with("diff_share"))

    if (nrow(flagged_increases) > 0) {
        print(paste("WARNING: Found", nrow(flagged_increases), "instances of large year-on-year INCREASES ( >", large_increase_threshold, "ppt) in coverage shares."))
        print("Sample of flagged INCREASES (first 10 rows):")
        print(head(flagged_increases, 10))
    } else {
        print(paste("Sanity Check for large YoY INCREASES (>", large_increase_threshold, "ppt): No such increases detected. OK."))
    }

    # Check for Significant Decreases
    flagged_decreases <- yoy_changes %>%
        filter(
            (diff_share1 < significant_decrease_threshold & !is.na(diff_share1)) |
                (diff_share6 < significant_decrease_threshold & !is.na(diff_share6)) |
                (diff_share30 < significant_decrease_threshold & !is.na(diff_share30))
        ) %>%
        select(AGS, year, lag_year, starts_with("share_"), starts_with("lag_share"), starts_with("diff_share"))

    if (nrow(flagged_decreases) > 0) {
        print(paste("WARNING: Found", nrow(flagged_decreases), "instances of significant year-on-year DECREASES ( <", significant_decrease_threshold, "ppt) in coverage shares."))
        print("Sample of flagged DECREASES (first 10 rows):")
        print(head(flagged_decreases, 10))
    } else {
        print(paste("Sanity Check for significant YoY DECREASES (<", significant_decrease_threshold, "ppt): No such decreases detected. OK."))
    }
} else {
    print("Skipping YoY change check due to empty panel or missing columns.")
}
# -------------------------------------------------------------

# --- Summarize and Plot Large Year-on-Year Changes by Year ---
print("--- Summarizing and Plotting Large Year-on-Year Changes by Year ---")
if (exists("flagged_increases") && exists("flagged_decreases") && nrow(yoy_changes) > 0) {
    counts_large_increases_by_year <- flagged_increases %>%
        group_by(year) %>%
        summarise(count_increases = n(), .groups = "drop")

    counts_significant_decreases_by_year <- flagged_decreases %>%
        group_by(year) %>%
        summarise(count_decreases = n(), .groups = "drop")

    # Combine counts for plotting
    # The yoy_summary_for_plot and pivot_longer logic was problematic and not used.
    # yoy_plot_data is created directly and more robustly below.

    yoy_plot_data <- bind_rows(
        flagged_increases %>% count(year, name = "count") %>% mutate(change_type = paste0("Large Increase (>", large_increase_threshold, "ppt)")),
        flagged_decreases %>% count(year, name = "count") %>% mutate(change_type = paste0("Significant Decrease (<", significant_decrease_threshold, "ppt)"))
    ) %>%
        filter(!is.na(year)) # Ensure year is not NA

    if (nrow(yoy_plot_data) > 0) {
        print("Summary of Large/Significant YoY Changes by Year:")
        print(yoy_plot_data %>% arrange(year, change_type) %>% print(n = Inf))

        yoy_changes_plot <- ggplot(yoy_plot_data, aes(x = factor(year), y = count, fill = change_type)) +
            geom_bar(stat = "identity", position = position_dodge(preserve = "single")) +
            scale_fill_manual(
                values = setNames(
                    c("tomato3", "steelblue"),
                    c(paste0("Large Increase (>", large_increase_threshold, "ppt)"), paste0("Significant Decrease (<", significant_decrease_threshold, "ppt)"))
                )
            ) +
            labs(
                title = "Count of Municipalities with Large Year-on-Year Coverage Changes",
                x = "Year of Change (Change from Year-1 to Year)",
                y = "Number of Municipalities Affected",
                fill = "Type of Change"
            ) +
            theme_minimal(base_size = 14) +
            theme(
                axis.text.x = element_text(angle = 45, hjust = 1),
                legend.position = "bottom",
                plot.title = element_text(hjust = 0.5)
            )

        plot_yoy_output_file <- here("output", "large_yoy_changes_plot.png")
        ggsave(plot_yoy_output_file, plot = yoy_changes_plot, width = 10, height = 7, dpi = 300)
        print(paste("Saved plot of large YoY changes to:", plot_yoy_output_file))
    } else {
        print("No large YoY changes were flagged, skipping plot.")
    }
} else {
    print("Skipping summary/plot of large YoY changes as no flagged data frames exist or yoy_changes is empty.")
}
# ----------------------------------------------------------------

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

print("--- Script Finished ---")

# --- Generate and Save Average Annual Coverage Plot ---
print("--- Generating Average Annual Coverage Plot ---")

if (nrow(panel) > 0 && all(c("year", expected_share_cols) %in% names(panel))) {
    avg_coverage_by_year <- panel %>%
        group_by(year) %>%
        summarise(
            avg_share_gte1mbps = mean(share_gte1mbps, na.rm = TRUE),
            avg_share_gte6mbps = mean(share_gte6mbps, na.rm = TRUE),
            avg_share_gte30mbps = mean(share_gte30mbps, na.rm = TRUE),
            .groups = "drop"
        ) %>%
        pivot_longer(
            cols = starts_with("avg_share_"),
            names_to = "share_category_raw",
            values_to = "mean_share"
        ) %>%
        mutate(
            share_category = factor(
                str_replace(share_category_raw, "avg_share_gte", "≥"),
                levels = c("≥1mbps", "≥6mbps", "≥30mbps") # Ensure correct order in legend
            )
        )

    print("--- Average Coverage by Year and Speed Category ---")
    print(
        avg_coverage_by_year %>%
            select(year, share_category, mean_share) %>%
            arrange(year, share_category) %>%
            mutate(mean_share = round(mean_share, 2)) %>%
            pivot_wider(names_from = share_category, values_from = mean_share) %>%
            print(n = Inf) # Print all rows
    )
    print("---------------------------------------------------")

    coverage_plot <- ggplot(avg_coverage_by_year, aes(x = year, y = mean_share, color = share_category, group = share_category)) +
        geom_line(linewidth = 1) +
        geom_point(size = 2) +
        scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 10), labels = function(x) paste0(x, "%")) +
        scale_x_continuous(breaks = scales::pretty_breaks(n = length(unique(avg_coverage_by_year$year)))) +
        labs(
            title = "Average Broadband Coverage Share Over Time",
            subtitle = "Across all municipalities, by minimum speed threshold",
            x = "Year",
            y = "Average Coverage Share (% of Households)",
            color = "Speed Threshold"
        ) +
        theme_minimal(base_size = 14) +
        theme(
            legend.position = "bottom",
            plot.title = element_text(hjust = 0.5),
            plot.subtitle = element_text(hjust = 0.5)
        )

    plot_output_file <- output_plot_avg_coverage
    ggsave(plot_output_file, plot = coverage_plot, width = 10, height = 7, dpi = 300)
    print(paste("Saved average annual coverage plot to:", plot_output_file))
} else {
    print("Skipping plot generation due to empty panel or missing columns.")
}
# ------------------------------------------------------

# Rationales from blueprint for thresholds:
# Threshold  | Rationale
# ≥ 1 Mbit/s | Minimal functional web browsing & early Facebook/Twitter (circa 2006).
# ≥ 6 Mbit/s | Stable video calls/live streams—captures the interaction and video push after ~2010.
# ≥ 30 Mbit/s| EU Digital Agenda 2020 benchmark for "Next-Gen Access"; robustness check for very high speeds.
