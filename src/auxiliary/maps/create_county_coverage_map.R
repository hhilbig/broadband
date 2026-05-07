library(tidyverse)
library(readxl)
library(sf)
library(here)

panel_file <- here("output", "panel_data_public.csv")
crosswalk_file <- here("data", "muni_mergers", "ref-gemeinden-umrech-2021-2011-2020.xlsx")
county_shape_file <- here("data", "geodata", "vg250_krs_2021_simplified.gpkg")
output_file <- here("output", "county_gte30_coverage_map_2021.png")

if (!file.exists(panel_file)) {
    stop("Panel file not found: ", panel_file)
}
if (!file.exists(crosswalk_file)) {
    stop("Crosswalk file not found: ", crosswalk_file)
}
if (!file.exists(county_shape_file)) {
    stop("County shape file not found: ", county_shape_file)
}

standardize_ags_8 <- function(x) {
    str_pad(str_replace_all(as.character(x), "\\D", ""), 8, pad = "0")
}

find_col <- function(names_vec, patterns) {
    hit <- which(map_lgl(names_vec, ~ all(str_detect(str_to_lower(.x), patterns))))
    if (length(hit) == 0) {
        stop("Could not find column matching: ", paste(patterns, collapse = ", "))
    }
    names_vec[hit[1]]
}

panel_2021 <- read_csv(panel_file, col_types = cols(AGS = col_character())) %>%
    filter(year == 2021) %>%
    transmute(
        AGS = standardize_ags_8(AGS),
        county_ags = str_sub(AGS, 1, 5),
        share_gte30mbps = as.numeric(share_gte30mbps)
    ) %>%
    filter(!is.na(share_gte30mbps))

raw_pop <- read_excel(crosswalk_file, sheet = "2020")
names_raw_pop <- names(raw_pop)

ags_2020_col <- find_col(names_raw_pop, c("gemeinden", "2020"))
ags_2021_col <- find_col(names_raw_pop, c("gemeinden", "2021"))
pop_col <- find_col(names_raw_pop, c("bevölkerung", "2020"))
transition_col <- find_col(names_raw_pop, c("bevölkerungs", "schlüssel"))

population_weights <- raw_pop %>%
    transmute(
        AGS_2020 = standardize_ags_8(.data[[ags_2020_col]]),
        AGS = standardize_ags_8(.data[[ags_2021_col]]),
        transition_share = as.numeric(.data[[transition_col]]),
        population = 100 * as.numeric(.data[[pop_col]])
    ) %>%
    filter(!is.na(AGS), !is.na(population), !is.na(transition_share)) %>%
    group_by(AGS) %>%
    summarise(population_weight = sum(population * transition_share, na.rm = TRUE), .groups = "drop")

county_coverage <- panel_2021 %>%
    left_join(population_weights, by = "AGS") %>%
    group_by(county_ags) %>%
    summarise(
        share_gte30mbps = weighted.mean(share_gte30mbps, population_weight, na.rm = TRUE),
        n_municipalities = n(),
        population_weight = sum(population_weight, na.rm = TRUE),
        .groups = "drop"
    ) %>%
    filter(is.finite(share_gte30mbps))

county_shapes <- st_read(county_shape_file, quiet = TRUE) %>%
    mutate(county_ags = str_sub(as.character(AGS), 1, 5))

county_map <- county_shapes %>%
    left_join(county_coverage, by = "county_ags")

missing_counties <- county_map %>%
    st_drop_geometry() %>%
    filter(is.na(share_gte30mbps))

if (nrow(missing_counties) > 0) {
    message("Counties without mapped 2021 broadband values: ", nrow(missing_counties))
}

plot_map <- ggplot(county_map) +
    geom_sf(aes(fill = share_gte30mbps), color = "white", linewidth = 0.08) +
    scale_fill_distiller(
        palette = "YlGnBu",
        direction = 1,
        na.value = "grey90",
        limits = c(50, 100),
        breaks = c(50, 75, 90, 100),
        labels = scales::label_number(suffix = "%"),
        oob = scales::squish
    ) +
    coord_sf(datum = NA) +
    labs(
        title = "Broadband Coverage >=30 Mbps by County, 2021",
        subtitle = "Population-weighted average of municipality coverage",
        fill = NULL
    ) +
    haschaR::theme_hanno() +
    theme(
        axis.text = element_blank(),
        axis.title = element_blank(),
        axis.ticks = element_blank(),
        legend.position = "right"
    )

ggsave(output_file, plot_map, width = 9, height = 9, dpi = 300)

print(paste("Saved county map to:", output_file))
print(paste("Mapped counties:", sum(!is.na(county_map$share_gte30mbps)), "of", nrow(county_map)))
