library(tidyverse)
library(here)

# --- Configuration ---
# Use the public dataset for descriptions
data_file_path <- here("output", "panel_data_public.csv")
output_dir <- here("output", "descriptives")

# Create output directory if it doesn't exist
if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
}

# --- Load Data ---
panel_data <- read_csv(data_file_path, show_col_types = FALSE)

share_cols <- c(
    "share_broadband_baseline",
    "share_gte1mbps",
    "share_gte6mbps",
    "share_gte30mbps"
)

share_labels <- c(
    share_broadband_baseline = "Basic access",
    share_gte1mbps = ">=1 Mbps",
    share_gte6mbps = ">=6 Mbps",
    share_gte30mbps = ">=30 Mbps"
)

break_labels <- tibble(
    year = c(2010, 2015),
    text_x = c(2009.85, 2014.85),
    label = c("definition break", "method break")
)

# --- Plot 1: Year-over-Year Change in Mean Coverage ---
yoy_changes <- panel_data %>%
    group_by(year) %>%
    summarise(
        avg_baseline = mean(share_broadband_baseline, na.rm = TRUE),
        avg_gte6 = mean(share_gte6mbps, na.rm = TRUE),
        avg_gte30 = mean(share_gte30mbps, na.rm = TRUE)
    ) %>%
    arrange(year) %>%
    mutate(
        yoy_change_baseline = avg_baseline - lag(avg_baseline),
        yoy_change_gte6 = avg_gte6 - lag(avg_gte6),
        yoy_change_gte30 = avg_gte30 - lag(avg_gte30)
    ) %>%
    pivot_longer(
        cols = starts_with("yoy_change_"),
        names_to = "speed_tier",
        values_to = "yoy_change",
        names_prefix = "yoy_change_"
    )

plot_yoy <- ggplot(yoy_changes, aes(x = year, y = yoy_change, color = speed_tier)) +
    geom_line(linewidth = 1) +
    geom_point(size = 2) +
    geom_vline(xintercept = 2015, linetype = "dashed", color = "red") +
    annotate("text", x = 2015.5, y = max(yoy_changes$yoy_change, na.rm = TRUE), label = "2015 Break", hjust = 0, size = 3) +
    labs(
        title = "Year-over-Year Change in Mean Broadband Coverage",
        subtitle = "The structural break in 2015 is clearly visible across all speed tiers.",
        x = "Year",
        y = "Change in Mean Coverage (Percentage Points)",
        color = "Speed Tier"
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")

ggsave(here(output_dir, "yoy_coverage_change_plot.png"), plot_yoy, width = 10, height = 6)
print("--- Data for: Year-over-Year Change in Mean Coverage ---")
print(yoy_changes, n = Inf)

# --- Plot 2: Distribution of Coverage Levels ---
coverage_long <- panel_data %>%
    select(year, all_of(share_cols)) %>%
    pivot_longer(
        cols = -year,
        names_to = "speed_tier",
        values_to = "coverage",
        names_prefix = "share_"
    ) %>%
    mutate(
        speed_tier = recode(
            speed_tier,
            broadband_baseline = "Basic access",
            gte1mbps = ">=1 Mbps",
            gte6mbps = ">=6 Mbps",
            gte30mbps = ">=30 Mbps"
        )
    )

plot_dist <- ggplot(coverage_long, aes(x = coverage, fill = speed_tier)) +
    geom_histogram(binwidth = 5, position = "identity", alpha = 0.7) +
    facet_wrap(~speed_tier, scales = "free_y") +
    labs(
        title = "Distribution of Municipality-Level Broadband Coverage",
        subtitle = "Shows high concentration at 0% and near 100% coverage.",
        x = "Coverage Share (%)",
        y = "Count of Municipality-Year Observations"
    ) +
    theme_minimal() +
    theme(legend.position = "none")

ggsave(here(output_dir, "coverage_distribution_plot.png"), plot_dist, width = 10, height = 6)
print("--- Data for: Distribution of Coverage Levels (Summary) ---")
print(coverage_long %>% group_by(speed_tier) %>% summarise(
    mean = mean(coverage, na.rm = TRUE),
    median = median(coverage, na.rm = TRUE),
    min = min(coverage, na.rm = TRUE),
    max = max(coverage, na.rm = TRUE),
    n_obs = n()
))


# --- Plot 3: Average Annual Coverage (from main pipeline) ---
avg_coverage_data <- panel_data %>%
    select(year, all_of(share_cols)) %>%
    pivot_longer(
        cols = -year,
        names_to = "speed_tier",
        values_to = "coverage"
    ) %>%
    group_by(year, speed_tier) %>%
    summarise(mean_coverage = mean(coverage, na.rm = TRUE), .groups = "drop") %>%
    filter(is.finite(mean_coverage)) %>%
    mutate(speed_tier = factor(speed_tier, levels = share_cols, labels = share_labels))

avg_coverage_plot <- ggplot(avg_coverage_data, aes(x = year, y = mean_coverage, color = speed_tier)) +
    geom_vline(
        data = break_labels,
        aes(xintercept = year),
        inherit.aes = FALSE,
        linetype = "dashed",
        linewidth = 0.4,
        color = "grey45"
    ) +
    geom_text(
        data = break_labels,
        aes(x = text_x, y = 101, label = label),
        inherit.aes = FALSE,
        angle = 90,
        hjust = 1,
        vjust = 0.5,
        size = 3.2,
        color = "grey25"
    ) +
    geom_line(linewidth = 1) +
    geom_point(size = 2) +
    labs(
        title = "Average Annual Broadband Coverage in German Municipalities",
        x = "Year",
        y = "Mean Coverage (%)",
        color = NULL,
        caption = "Basic access: >=0.128 Mbps in 2005-2008; >=1 Mbps from 2010 onward."
    ) +
    scale_y_continuous(
        limits = c(0, 105),
        breaks = seq(0, 100, 25),
        labels = scales::label_number(suffix = "%")
    ) +
    scale_x_continuous(breaks = c(2005, 2010, 2015, 2020)) +
    scale_color_manual(values = setNames(RColorBrewer::brewer.pal(5, "YlGnBu")[2:5], share_labels)) +
    haschaR::theme_hanno() +
    theme(legend.position = "bottom")

ggsave(here(output_dir, "average_annual_coverage_plot.png"), avg_coverage_plot, width = 10, height = 6)
print("--- Data for: Average Annual Coverage by Speed Tier ---")
print(avg_coverage_data, n = Inf)


print("Descriptive plots have been generated and saved to 'output/descriptives'.")
