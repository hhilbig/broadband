library(tidyverse)
library(here)

# --- Configuration: File Paths ---
file_paths <- c(
    here("output", "broadband_gemeinde_combined_long.csv"),
    here("output", "broadband_gemeinde_combined_long_ags2021.csv"),
    here("output", "panel_data_with_treatment.csv")
)

# --- Function to Check Year Distribution ---
check_year_dist <- function(file_path) {
    cat(paste("\n--- Checking file:", basename(file_path), "---\n"))

    if (!file.exists(file_path)) {
        cat(paste("File not found:", file_path, "\n"))
        return(NULL)
    }

    tryCatch(
        {
            data <- read_csv(file_path, show_col_types = FALSE)

            if (!("year" %in% colnames(data))) {
                cat(paste("Column 'year' not found in file:", basename(file_path), "\n"))
                return(NULL)
            }

            cat("Year distribution:\n")
            year_table <- table(data$year, useNA = "ifany")
            print(year_table)

            min_year <- min(data$year, na.rm = TRUE)
            max_year <- max(data$year, na.rm = TRUE)
            cat(paste("Min year:", min_year, "| Max year:", max_year, "\n"))
        },
        error = function(e) {
            cat(paste("Error processing file:", basename(file_path), "\nError message:", e$message, "\n"))
        }
    )
}

# --- Iterate and Check Each File ---
cat("Starting year distribution checks...\n")

for (path in file_paths) {
    check_year_dist(path)
}

cat("\n--- All checks finished. ---\n")
