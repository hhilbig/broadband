library(tidyverse)
library(haschaR)

# Define the path to the data file
# Assumes the script is run from the project root or that the path is relative to the script's location in a way that resolves correctly.
# Adjust the path if necessary, e.g., using here::here() for better path management.
data_file_path <- "output/panel_data_with_treatment.csv"

# Load the data
tryCatch(
    {
        panel_data <- read_csv(data_file_path, show_col_types = FALSE)
    },
    error = function(e) {
        stop(paste("Error loading data file:", data_file_path, "\nOriginal error:", e$message))
    }
)

# Ensure 'year' is integer and treatment variables are numeric/integer
panel_data <- panel_data %>%
    mutate(
        year = as.integer(year),
        treat_low = as.integer(treat_low),
        treat_medium = as.integer(treat_medium),
        treat_high = as.integer(treat_high)
    )

# Function to calculate first treatment year and share of newly treated municipalities
calculate_first_treatment_share <- function(df, treatment_var_name) {
    treatment_var_sym <- sym(treatment_var_name)

    # Find the first year each AGS is treated
    first_treatment_year <- df %>%
        filter({{ treatment_var_sym }} == 1) %>%
        group_by(AGS) %>%
        summarise(first_treated_year = min(year, na.rm = TRUE), .groups = "drop") %>%
        filter(is.finite(first_treated_year)) # Ensure first_treated_year is not Inf

    # Count newly treated municipalities per year
    newly_treated_counts <- first_treatment_year %>%
        group_by(first_treated_year) %>%
        summarise(newly_treated_count = n(), .groups = "drop") %>%
        rename(year = first_treated_year)

    # Count total unique municipalities observed per year in the original panel
    total_munis_per_year <- df %>%
        group_by(year) %>%
        summarise(total_munis_in_year = n_distinct(AGS), .groups = "drop")

    # Join newly treated counts with total munis per year and calculate share
    treatment_summary <- newly_treated_counts %>%
        left_join(total_munis_per_year, by = "year") %>%
        mutate(
            share_newly_treated = ifelse(total_munis_in_year > 0, newly_treated_count / total_munis_in_year, 0),
            treatment_variable = treatment_var_name
        ) %>%
        select(year, treatment_variable, newly_treated_count, total_munis_in_year, share_newly_treated) %>%
        arrange(year)

    return(treatment_summary)
}

# Calculate for each treatment variable
treat_low_summary <- calculate_first_treatment_share(panel_data, "treat_low")
treat_medium_summary <- calculate_first_treatment_share(panel_data, "treat_medium")
treat_high_summary <- calculate_first_treatment_share(panel_data, "treat_high")

# Combine and print results
all_treatment_summary <- bind_rows(
    treat_low_summary,
    treat_medium_summary,
    treat_high_summary
)

print("Share of municipalities 'Treated' for the first time, by year and treatment variable:")
print(all_treatment_summary, n = Inf)

# --- Create and save a plot ---
plot_path <- "output/newly_treated_share_plot.png"

newly_treated_plot <- ggplot(
    all_treatment_summary,
    aes(x = year, y = share_newly_treated, group = treatment_variable, color = treatment_variable)
) +
    geom_line() +
    geom_point() +
    facet_wrap(~treatment_variable, scales = "free_y", ncol = 1) +
    labs(
        title = "Share of Municipalities Newly Treated Each Year",
        subtitle = "By treatment variable definition",
        x = "Year",
        y = "Share of Municipalities Newly Treated",
        color = "Treatment Variable"
    ) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    theme_hanno() +
    theme(legend.position = "bottom")

tryCatch(
    {
        ggsave(plot_path, newly_treated_plot, width = 8, height = 10, dpi = 300)
        cat(paste("\nPlot saved to:", normalizePath(plot_path, mustWork = FALSE), "\n"))
    },
    error = function(e) {
        cat(paste("\nError saving plot:", e$message, "\n"))
    }
)

# You might want to save this to a CSV:
# write_csv(all_treatment_summary, "output/newly_treated_municipalities_summary.csv")

cat("\nScript execution finished.\n")
cat("Summary table 'all_treatment_summary' contains the results.\n")
cat(paste("Data loaded from:", normalizePath(data_file_path, mustWork = FALSE), "\n"))
