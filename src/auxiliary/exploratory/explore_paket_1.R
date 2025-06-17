library(tidyverse)
library(readxl)

# Path to the data directory
data_dir <- "data/Paket_1"

# Get a list of Excel files, handling potential encoding issues in names
excel_files <- list.files(data_dir, pattern = "\\.xls(x?)$", full.names = TRUE)

# Function to read and glimpse a single sheet
glimpse_sheet <- function(file, sheet) {
    cat(paste("\n--- Glimpsing", basename(file), "--- Sheet:", sheet, "---\n"))

    # The filenames from the OS may have encoding issues.
    # We read the file path as is.
    df <- read_excel(file, sheet = sheet)

    glimpse(df)
}

# Iterate over each file and its sheets
for (file in excel_files) {
    try({
        sheets <- excel_sheets(file)
        for (sheet in sheets) {
            try(glimpse_sheet(file, sheet))
        }
    })
}
