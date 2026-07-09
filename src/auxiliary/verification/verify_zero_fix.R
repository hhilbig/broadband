library(tidyverse)
library(here)

set.seed(20260710)

# --- Purpose ---
# Diagnostics for the 2010-2014 non-reporting zero fix: municipality-years with
# exactly 0 across ALL speed tiers in 2010-2014 are treated as non-reporting
# and removed in step 06. This script verifies the fix and re-estimates how
# much of the apparent 2015 methodological break the false zeros explained.
#
# Set `archive_dir` to a directory containing the PRE-ZERO-FIX
# panel_data_public.csv. If absent, before/after sections are skipped.

# Point ZERO_FIX_ARCHIVE at a directory holding the pre-zero-fix
# panel_data_public.csv. Without it, before/after sections are skipped.
archive_dir <- Sys.getenv("ZERO_FIX_ARCHIVE", unset = here("output", "archive", "pre_zero_fix"))

new_panel <- read_csv(here("output", "panel_data_public.csv"), show_col_types = FALSE)
audit <- read_csv(here("output", "nonreporting_zero_blocks.csv"), show_col_types = FALSE)

failures <- character()
note_failure <- function(msg) {
    failures <<- c(failures, msg)
    print(paste("FAIL:", msg))
}

# --- 1. No all-tier-zero municipality-years remain in 2010-2014 ---
remaining_zero <- new_panel %>%
    filter(year %in% 2010:2014,
           share_gte1mbps == 0,
           is.na(share_gte6mbps) | share_gte6mbps == 0,
           is.na(share_gte30mbps) | share_gte30mbps == 0)

print(paste("All-tier-zero municipality-years remaining in 2010-2014 panel:", nrow(remaining_zero)))
if (nrow(remaining_zero) > 0) {
    # A 2021-boundary municipality can aggregate several historical units; a
    # residual zero can only appear if ALL its constituents were zero, which
    # the source-level rule should have removed. Investigate any survivor.
    print(head(remaining_zero, 20))
    note_failure("All-tier-zero municipality-years remain in 2010-2014.")
}

# --- 2. 2015+ flagged cases are retained, true high-tier zeros preserved ---
flagged_kept <- audit %>% filter(!dropped)
print(paste("Flagged-but-kept 2015+ all-tier-zero municipality-years:", nrow(flagged_kept)))

zero_2015_panel <- new_panel %>% filter(year >= 2015, share_gte1mbps == 0)
print(paste("Panel municipality-years at gte1 == 0 in 2015+:", nrow(zero_2015_panel)))
if (nrow(zero_2015_panel) == 0 && nrow(flagged_kept) > 0) {
    note_failure("2015+ all-tier-zero cases were dropped although the rule keeps them.")
}

high_tier_true_zeros <- new_panel %>%
    filter(year %in% 2010:2014, share_gte1mbps > 80, share_gte30mbps == 0)
print(paste("Preserved true high-tier zeros in 2010-2014 (gte1 > 80 & gte30 == 0):",
            nrow(high_tier_true_zeros)))
if (nrow(high_tier_true_zeros) == 0) {
    note_failure("No high-tier true zeros left in 2010-2014 - the filter removed too much.")
}

# --- 3. Reporter counts 2010-2014 ---
print("Municipalities per year (reporters only after the fix):")
print(new_panel %>% filter(year %in% 2008:2016) %>% count(year), n = 10)

# --- 4. Berlin sanity ---
berlin_years <- sort(unique(as.integer(new_panel$year[new_panel$AGS == "11000000"])))
print(paste("Berlin years:", paste(berlin_years, collapse = ",")))
if (any(berlin_years %in% 2010:2014)) {
    note_failure("Berlin still has 2010-2014 rows despite the all-zero block.")
}
if (!all(c(2005:2008, 2015:2021) %in% berlin_years)) {
    note_failure("Berlin is missing expected years outside the non-reporting window.")
}

# --- 5. Before/after annual means and 2015-break re-estimate ---
old_panel_path <- file.path(archive_dir, "panel_data_public.csv")

if (file.exists(old_panel_path)) {
    old_panel <- read_csv(old_panel_path, show_col_types = FALSE)

    print("--- Before/after annual unweighted means (baseline / gte1 / gte30) ---")
    mean_table <- bind_rows(
        old_panel %>% mutate(version = "before"),
        new_panel %>% mutate(version = "after")
    ) %>%
        filter(year >= 2010) %>%
        group_by(version, year) %>%
        summarise(
            n = n(),
            baseline = round(mean(share_broadband_baseline, na.rm = TRUE), 1),
            gte1 = round(mean(share_gte1mbps, na.rm = TRUE), 1),
            gte30 = round(mean(share_gte30mbps, na.rm = TRUE), 1),
            .groups = "drop"
        ) %>%
        pivot_wider(names_from = version, values_from = c(n, baseline, gte1, gte30)) %>%
        arrange(year)
    print(mean_table, n = 20)

    print("--- 2015 break decomposition (share_broadband_baseline) ---")
    jump_before <- old_panel %>%
        filter(year %in% c(2014, 2015)) %>%
        group_by(year) %>%
        summarise(m = mean(share_broadband_baseline, na.rm = TRUE)) %>%
        summarise(jump = diff(m)) %>%
        pull(jump)

    jump_after <- new_panel %>%
        filter(year %in% c(2014, 2015)) %>%
        group_by(year) %>%
        summarise(m = mean(share_broadband_baseline, na.rm = TRUE)) %>%
        summarise(jump = diff(m)) %>%
        pull(jump)

    within_jump <- new_panel %>%
        filter(year %in% c(2014, 2015)) %>%
        select(AGS, year, share_broadband_baseline) %>%
        pivot_wider(names_from = year, values_from = share_broadband_baseline,
                    names_prefix = "y") %>%
        filter(!is.na(y2014), !is.na(y2015)) %>%
        summarise(n = n(), jump = mean(y2015 - y2014))

    print(paste("Unweighted mean jump 2014->2015 BEFORE fix:", round(jump_before, 1), "ppt"))
    print(paste("Unweighted mean jump 2014->2015 AFTER fix (reporters vs full 2015):",
                round(jump_after, 1), "ppt"))
    print(paste("WITHIN-municipality mean jump 2014->2015 (n =", within_jump$n,
                "observed in both years):", round(within_jump$jump, 1), "ppt"))
    print(paste("Share of the pre-fix jump attributable to false zeros:",
                round(100 * (jump_before - within_jump$jump) / jump_before), "%"))
} else {
    print(paste("Archive not found at", archive_dir, "- skipping before/after sections."))
}

# --- Result ---
if (length(failures) > 0) {
    stop("verify_zero_fix found ", length(failures), " failure(s): ",
         paste(failures, collapse = " | "))
}
print("--- All zero-fix verification checks passed ---")
