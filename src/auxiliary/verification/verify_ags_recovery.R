library(tidyverse)
library(here)

set.seed(20260709)

# --- Purpose ---
# Before/after diagnostics for the AGS recovery fixes (nearest-year crosswalk
# fallback, Berlin/Hamburg reference fix, Bezirk-to-city aggregation).
# Compares the rerun outputs against archived pre-fix copies.
#
# Set `archive_dir` to a directory containing the PRE-FIX versions of:
#   - broadband_gemeinde_combined_long_ags2021.rds
#   - panel_data_public.csv
# If the archive is missing, the before/after sections are skipped and only
# the standalone checks run.

# Point AGS_RECOVERY_ARCHIVE at a directory holding the pre-fix outputs
# (e.g. copies made before rerunning step 06). Without it, the before/after
# sections are skipped and only the standalone checks run.
archive_dir <- Sys.getenv("AGS_RECOVERY_ARCHIVE", unset = here("output", "archive", "pre_ags_fix"))

new_long <- readRDS(here("output", "broadband_gemeinde_combined_long_ags2021.rds"))
new_panel <- read_csv(here("output", "panel_data_public.csv"), show_col_types = FALSE)
fallback_detail <- readRDS(here("output", "nearest_year_fallback_mapping.rds"))

failures <- character()
note_failure <- function(msg) {
    failures <<- c(failures, msg)
    print(paste("FAIL:", msg))
}

# --- 1. Standalone panel checks ---
print("--- Standalone panel checks ---")

n_ags <- n_distinct(new_panel$AGS)
print(paste("Unique AGS in panel:", n_ags))
if (n_ags != 10994) note_failure(paste("Expected 10,994 unique AGS, got", n_ags))

city_states <- new_panel %>%
    filter(AGS %in% c("02000000", "11000000", "04011000", "04012000")) %>%
    count(AGS)
print(city_states)

hh_years <- sort(unique(as.integer(new_panel$year[new_panel$AGS == "02000000"])))
be_years <- sort(unique(as.integer(new_panel$year[new_panel$AGS == "11000000"])))
expected_years <- setdiff(2005:2021, 2009L)
# Berlin's 2010-2014 source rows are non-reporting zeros removed by the
# 2010-2014 zero fix (see verify_zero_fix.R), so Berlin legitimately lacks
# those years; Hamburg reported real values throughout.
expected_years_berlin <- setdiff(expected_years, 2010:2014)
if (!identical(hh_years, expected_years)) {
    note_failure(paste("Hamburg years:", paste(hh_years, collapse = ",")))
}
if (!identical(be_years, expected_years_berlin)) {
    note_failure(paste("Berlin years:", paste(be_years, collapse = ",")))
}

print("Berlin/Hamburg trajectories vs Bremen:")
print(
    new_panel %>%
        filter(AGS %in% c("02000000", "11000000", "04011000")) %>%
        select(AGS, year, share_broadband_baseline, share_gte30mbps) %>%
        pivot_wider(names_from = AGS,
                    values_from = c(share_broadband_baseline, share_gte30mbps)) %>%
        arrange(year),
    n = Inf
)

share_cols <- c("share_broadband_baseline", "share_gte1mbps", "share_gte6mbps", "share_gte30mbps")
cs_long <- new_panel %>%
    filter(AGS %in% c("02000000", "11000000")) %>%
    arrange(AGS, year)

for (col in share_cols) {
    vals <- cs_long[[col]]
    if (any(!is.na(vals) & (vals < 0 | vals > 100))) {
        note_failure(paste("City-state", col, "outside [0, 100]"))
    }
}

# KNOWN ISSUE: Berlin's Paket 1 rows for 2010-2014 are false zeros (the source
# records 0 across all tiers while 2008 is ~96% and 2015 is 100%). This is one
# instance of a broader non-reporting-coded-as-zero pattern in the 2010-2014
# source data (~6,300 municipalities). Flagged for a separate decision; the
# jump check below therefore excludes the 2010-2014 window for Berlin.
cs_jumps <- cs_long %>%
    group_by(AGS) %>%
    mutate(d_baseline = share_broadband_baseline - lag(share_broadband_baseline)) %>%
    filter(!is.na(d_baseline), abs(d_baseline) > 50) %>%
    filter(!(AGS == "11000000" & year %in% 2010:2015))
if (nrow(cs_jumps) > 0) {
    print(cs_jumps)
    note_failure("City-state baseline series has unexplained >50 ppt year-on-year jumps.")
}

hierarchy_violations <- new_panel %>%
    filter(
        (!is.na(share_broadband_baseline) & !is.na(share_gte1mbps) & share_broadband_baseline < share_gte1mbps - 1e-8) |
            (!is.na(share_gte1mbps) & !is.na(share_gte6mbps) & share_gte1mbps < share_gte6mbps - 1e-8) |
            (!is.na(share_gte6mbps) & !is.na(share_gte30mbps) & share_gte6mbps < share_gte30mbps - 1e-8)
    )
if (nrow(hierarchy_violations) > 0) {
    note_failure(paste("Speed-tier hierarchy violations:", nrow(hierarchy_violations)))
}

# --- 2. Fallback mapping summaries ---
print("--- Nearest-year fallback summaries ---")
print(
    fallback_detail %>%
        distinct(AGS_hist_cw, year_hist_cw, donor_year) %>%
        mutate(state = substr(AGS_hist_cw, 1, 2)) %>%
        count(state, name = "n_pairs") %>%
        arrange(desc(n_pairs)),
    n = Inf
)
print("Donor-year distance distribution (data year vs donor sheet):")
print(
    fallback_detail %>%
        distinct(AGS_hist_cw, year_hist_cw, donor_year) %>%
        count(year_dist = donor_year - year_hist_cw)
)

# --- 3. Before/after comparisons ---
old_long_path <- file.path(archive_dir, "broadband_gemeinde_combined_long_ags2021.rds")
old_panel_path <- file.path(archive_dir, "panel_data_public.csv")

if (file.exists(old_long_path) && file.exists(old_panel_path)) {
    old_long <- readRDS(old_long_path)
    old_panel <- read_csv(old_panel_path, show_col_types = FALSE)

    print("--- Before/after: panel dimensions ---")
    print(paste("Panel rows:", nrow(old_panel), "->", nrow(new_panel)))
    print(paste("Unique AGS:", n_distinct(old_panel$AGS), "->", n_distinct(new_panel$AGS)))

    print("--- Before/after: municipalities per state-year (changes only) ---")
    state_year_counts <- bind_rows(
        old_panel %>% mutate(version = "old"),
        new_panel %>% mutate(version = "new")
    ) %>%
        mutate(state = substr(AGS, 1, 2)) %>%
        count(version, state, year) %>%
        pivot_wider(names_from = version, values_from = n, values_fill = 0) %>%
        mutate(delta = new - old)

    print(state_year_counts %>% filter(delta != 0) %>% arrange(state, year), n = Inf)

    # The 2010-2014 non-reporting zero fix intentionally removes municipality-
    # years in that window (see verify_zero_fix.R), so the loss check is scoped
    # to the years untouched by that fix.
    lost_units <- state_year_counts %>% filter(delta < 0, !year %in% 2010:2014)
    if (nrow(lost_units) > 0) {
        print(lost_units, n = Inf)
        note_failure("Some state-years LOST municipalities relative to the pre-fix panel.")
    }

    print("--- Before/after: value changes in pre-existing panel cells ---")
    cell_compare <- old_panel %>%
        select(AGS, year, all_of(share_cols)) %>%
        inner_join(
            new_panel %>% select(AGS, year, all_of(share_cols)),
            by = c("AGS", "year"),
            suffix = c("_old", "_new")
        )

    for (col in share_cols) {
        deltas <- abs(cell_compare[[paste0(col, "_new")]] - cell_compare[[paste0(col, "_old")]])
        deltas <- deltas[!is.na(deltas)]
        n_changed <- sum(deltas > 1e-8)
        n_big <- sum(deltas > 10)
        print(paste0(col, ": ", n_changed, " of ", length(deltas),
                     " pre-existing cells changed; ", n_big, " moved by >10 ppt; max |delta| = ",
                     round(max(c(deltas, 0)), 2), " ppt"))
    }

    big_movers <- cell_compare %>%
        mutate(d_baseline = abs(share_broadband_baseline_new - share_broadband_baseline_old)) %>%
        filter(!is.na(d_baseline), d_baseline > 10) %>%
        mutate(state = substr(AGS, 1, 2)) %>%
        arrange(desc(d_baseline))

    print(paste("Pre-existing cells with baseline moving >10 ppt:", nrow(big_movers)))
    if (nrow(big_movers) > 0) {
        print(big_movers %>% count(state, year), n = Inf)
        print(head(big_movers %>% select(AGS, year, share_broadband_baseline_old,
                                         share_broadband_baseline_new, d_baseline), 25))
    }

    print("--- Before/after: mixed-cell diagnostic (recovered vs previously published) ---")
    # Cells in the standardized long data whose aggregation now includes
    # nearest-year fallback contributors, compared to the pre-fix value.
    fallback_keys <- fallback_detail %>% distinct(AGS_2021, year = year_hist_cw)
    mixed_cells <- new_long %>%
        semi_join(fallback_keys, by = c("AGS" = "AGS_2021", "year")) %>%
        inner_join(
            old_long %>% select(AGS, year, data_category, technology_group, speed_mbps_gte,
                                value_old = value, n_agg_old = n_agg),
            by = c("AGS", "year", "data_category", "technology_group", "speed_mbps_gte")
        ) %>%
        mutate(delta = value - value_old, state = substr(AGS, 1, 2))

    print("Mixed-cell |delta| summary by state and year (cells existing before AND after):")
    print(
        mixed_cells %>%
            group_by(state, year) %>%
            summarise(
                n_cells = n(),
                mean_abs_delta = round(mean(abs(delta)), 2),
                p95_abs_delta = round(quantile(abs(delta), 0.95), 2),
                max_abs_delta = round(max(abs(delta)), 2),
                .groups = "drop"
            ) %>%
            filter(max_abs_delta > 0.01) %>%
            arrange(desc(max_abs_delta)),
        n = 40
    )
} else {
    print(paste("Archive not found at", archive_dir, "- skipping before/after sections."))
}

# --- Result ---
if (length(failures) > 0) {
    stop("verify_ags_recovery found ", length(failures), " failure(s): ",
         paste(failures, collapse = " | "))
}
print("--- All recovery verification checks passed ---")
