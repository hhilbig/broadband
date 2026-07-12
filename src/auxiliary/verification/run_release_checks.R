library(tidyverse)
library(here)

set.seed(20260712)

# --- Purpose ---
# Single fail-loud release gate consolidating the invariants that every
# published version of the panel must satisfy. Run before tagging a release:
#   Rscript src/auxiliary/verification/run_release_checks.R
# It exits non-zero (via stop()) if any invariant is violated.
#
# The expected panel dimensions are the only version-specific constants. When a
# release deliberately changes them (e.g. a major version that recovers or drops
# observations), update the defaults below or override via the environment
# variables named in the getenv() calls. Every other check encodes a structural
# invariant that must hold regardless of version.

expected_rows <- as.integer(Sys.getenv("RELEASE_EXPECTED_ROWS", unset = "140232"))
expected_ags  <- as.integer(Sys.getenv("RELEASE_EXPECTED_AGS", unset = "10994"))
expected_years <- c(2005:2008, 2010:2021) # no 2009 municipality panel

valid_ags_pattern <- "^(0[1-9]|1[0-6])\\d{6}$"

share_cols <- c("share_broadband_baseline", "share_gte1mbps", "share_gte6mbps", "share_gte30mbps")
tier_cols  <- c("tier_baseline", "tier_gte1", "tier_gte6", "tier_gte30")
tier_thresholds <- c(tier_baseline = 0.128, tier_gte1 = 1, tier_gte6 = 6, tier_gte30 = 30)
tier_for_share <- c(
    share_broadband_baseline = "tier_baseline",
    share_gte1mbps = "tier_gte1",
    share_gte6mbps = "tier_gte6",
    share_gte30mbps = "tier_gte30"
)

# Expected measurement tier behind each share, by period (see README caveats).
expected_tiers <- tribble(
    ~tier_col,       ~years,      ~allowed,
    "tier_baseline", 2005:2008,   0.128,
    "tier_baseline", 2010:2017,   2,
    "tier_baseline", 2018:2021,   c(1, 2),
    "tier_gte1",     2010:2017,   2,
    "tier_gte1",     2018:2021,   c(1, 2),
    "tier_gte6",     2010:2012,   50,
    "tier_gte6",     2013:2017,   16,
    "tier_gte6",     2018:2021,   c(6, 16),
    "tier_gte30",    2010:2017,   50,
    "tier_gte30",    2018:2021,   c(30, 50)
)

failures <- character()
note_failure <- function(msg) {
    failures <<- c(failures, msg)
    print(paste("FAIL:", msg))
}
check <- function(condition, msg) {
    if (!isTRUE(condition)) note_failure(msg)
}

panel <- read_csv(here("output", "panel_data_public.csv"), show_col_types = FALSE)
ref <- readRDS(here("data", "ags_reference", "destatis_ags_2021.rds")) %>%
    mutate(AGS = as.character(AGS)) %>%
    filter(str_detect(AGS, valid_ags_pattern)) %>%
    distinct(AGS)

print(paste("Loaded panel:", nrow(panel), "rows,", ncol(panel), "columns."))

# --- 1. Schema ---
missing_cols <- setdiff(c("AGS", "year", share_cols, tier_cols, "method_change_2015"), names(panel))
check(length(missing_cols) == 0,
      paste("Missing expected columns:", paste(missing_cols, collapse = ", ")))

# --- 2. Dimensions ---
check(nrow(panel) == expected_rows,
      paste0("Row count ", nrow(panel), " != expected ", expected_rows,
             " (update RELEASE_EXPECTED_ROWS if the change is intended)."))
check(n_distinct(panel$AGS) == expected_ags,
      paste0("Distinct AGS ", n_distinct(panel$AGS), " != expected ", expected_ags,
             " (update RELEASE_EXPECTED_AGS if the change is intended)."))
check(setequal(unique(panel$year), expected_years),
      paste0("Year set mismatch. Present: ", paste(sort(unique(panel$year)), collapse = ",")))

# --- 3. AGS-year key uniqueness ---
check(!any(duplicated(panel[, c("AGS", "year")])), "AGS-year key is not unique.")

# --- 4. AGS validity and reference membership ---
check(all(str_detect(panel$AGS, valid_ags_pattern)), "Some AGS fail the 8-digit state-prefix pattern.")
not_in_ref <- setdiff(unique(panel$AGS), ref$AGS)
check(length(not_in_ref) == 0,
      paste0(length(not_in_ref), " panel AGS are absent from the Destatis 2021 reference (e.g. ",
             paste(head(not_in_ref, 5), collapse = ", "), ")."))
ref_absent <- setdiff(ref$AGS, unique(panel$AGS))
check(length(ref_absent) == 0,
      paste0(length(ref_absent), " reference AGS never appear in the panel (e.g. ",
             paste(head(ref_absent, 5), collapse = ", "), ")."))

# --- 5. Share bounds ---
for (sc in share_cols) {
    oob <- panel %>% filter(!is.na(.data[[sc]]) & (.data[[sc]] < 0 | .data[[sc]] > 100))
    check(nrow(oob) == 0, paste0(sc, " has ", nrow(oob), " values outside [0, 100]."))
}

# --- 6. Speed-tier hierarchy (where both adjacent tiers observed) ---
hier <- panel %>%
    filter(
        (!is.na(share_broadband_baseline) & !is.na(share_gte1mbps) & share_broadband_baseline < share_gte1mbps) |
            (!is.na(share_gte1mbps) & !is.na(share_gte6mbps) & share_gte1mbps < share_gte6mbps) |
            (!is.na(share_gte6mbps) & !is.na(share_gte30mbps) & share_gte6mbps < share_gte30mbps)
    )
check(nrow(hier) == 0, paste0(nrow(hier), " rows violate baseline >= gte1 >= gte6 >= gte30."))

# --- 7. Tier columns: NA-alignment, threshold floor, expected composition ---
for (sc in names(tier_for_share)) {
    tc <- tier_for_share[[sc]]
    check(all(is.na(panel[[sc]]) == is.na(panel[[tc]])),
          paste0(tc, " is not missing exactly when ", sc, " is missing."))
    check(!any(panel[[tc]] < tier_thresholds[[tc]], na.rm = TRUE),
          paste0(tc, " contains tiers below its named threshold."))
}
for (i in seq_len(nrow(expected_tiers))) {
    tc <- expected_tiers$tier_col[i]
    yrs <- expected_tiers$years[[i]]
    allowed <- expected_tiers$allowed[[i]]
    obs <- panel %>% filter(year %in% yrs) %>% pull(.data[[tc]])
    obs <- obs[!is.na(obs)]
    bad <- setdiff(unique(obs), allowed)
    check(length(bad) == 0,
          paste0(tc, " in ", min(yrs), "-", max(yrs), " has unexpected tiers: ",
                 paste(bad, collapse = ", "), " (allowed: ", paste(allowed, collapse = ", "), ")."))
}

# --- 8. Baseline coverage present in every year; higher tiers only NA in 2005-2008 ---
check(!any(is.na(panel$share_broadband_baseline)), "share_broadband_baseline has missing values.")
early_only_na <- panel %>%
    filter(year >= 2010, if_any(all_of(c("share_gte1mbps", "share_gte6mbps", "share_gte30mbps")), is.na))
check(nrow(early_only_na) == 0,
      paste0(nrow(early_only_na), " post-2010 rows have a missing higher-tier share (expected only in 2005-2008)."))

# --- 9. method_change_2015 dummy ---
check(all(panel$method_change_2015 == as.integer(panel$year == 2015L)),
      "method_change_2015 is not 1 exactly in 2015.")

# --- 10. No all-tier-zero municipality-years remain in 2010-2014 (zero fix) ---
remaining_zero <- panel %>%
    filter(year %in% 2010:2014, share_gte1mbps == 0,
           is.na(share_gte6mbps) | share_gte6mbps == 0,
           is.na(share_gte30mbps) | share_gte30mbps == 0)
check(nrow(remaining_zero) == 0,
      paste0(nrow(remaining_zero), " all-tier-zero municipality-years remain in 2010-2014."))

# --- Report ---
print("--- Tier composition by year ---")
print(panel %>%
          group_by(year) %>%
          summarise(across(all_of(tier_cols), ~ paste(sort(unique(.x)), collapse = ",")),
                    n = n(), .groups = "drop") %>%
          arrange(year), n = Inf)

if (length(failures) > 0) {
    stop("run_release_checks found ", length(failures), " failure(s):\n  ",
         paste(failures, collapse = "\n  "))
}
print(paste("--- All release checks passed:", nrow(panel), "rows,",
            n_distinct(panel$AGS), "municipalities,",
            length(unique(panel$year)), "years ---"))
