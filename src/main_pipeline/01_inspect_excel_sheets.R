library(readxl)
library(stringr)
library(dplyr)
library(here)

# Helper function to find AGS column (adapted from clean_data.R)
find_ags_column_name <- function(col_names) {
    col_names_lower <- tolower(col_names)
    # Patterns for AGS: "ags", "gemeindeschluessel", "gemeindeschlüssel", "gem"
    ags_patterns <- c("^ags$", "^gemeindeschluessel$", "^gemeindeschlüssel$", "^gem$")
    for (pattern in ags_patterns) {
        match_idx <- str_which(col_names_lower, pattern)
        if (length(match_idx) > 0) {
            return(col_names[match_idx[1]]) # Return the original case name
        }
    }
    return(NA)
}

# Main function to inspect Excel files
inspect_excel_sheets <- function(target_dirs) {
    all_excel_files <- character(0)
    for (target_dir in target_dirs) {
        files_in_dir <- list.files(
            path = target_dir,
            pattern = "\\.(xls|xlsx)$",
            recursive = TRUE,
            full.names = TRUE
        )
        # Exclude temporary Excel files (starting with ~$)
        files_in_dir <- files_in_dir[!str_starts(basename(files_in_dir), "~\\$")]
        all_excel_files <- c(all_excel_files, files_in_dir)
    }

    if (length(all_excel_files) == 0) {
        print("No Excel files found in the target directories.")
        return(invisible(NULL))
    }

    print(paste("Found", length(all_excel_files), "Excel files to inspect."))

    inspection_results <- list()

    for (file_path in all_excel_files) {
        print(paste("--- Inspecting File:", file_path, "---"))
        tryCatch(
            {
                sheet_names <- excel_sheets(file_path)
                if (length(sheet_names) == 0) {
                    print("  No sheets found in this file.")
                    next
                }
                print(paste("  Sheets found:", paste(sheet_names, collapse = ", ")))

                for (sheet_name in sheet_names) {
                    print(paste("    -- Analyzing Sheet:", sheet_name, "--"))
                    header_data <- read_excel(file_path, sheet = sheet_name, n_max = 5) # Read only a few rows for header
                    col_names <- colnames(header_data)

                    ags_col <- find_ags_column_name(col_names)
                    ags_found <- !is.na(ags_col)

                    print(paste("      AGS Column Found:", ifelse(ags_found, "Yes", "No")))
                    if (ags_found) {
                        print(paste("      Identified AGS Column Name:", ags_col))
                    }
                    print("      All Column Names:")
                    print(paste("        ", col_names))

                    inspection_results[[length(inspection_results) + 1]] <- tibble(
                        file_path = file_path,
                        sheet_name = sheet_name,
                        ags_column_found = ags_found,
                        identified_ags_column = ifelse(ags_found, ags_col, NA_character_),
                        all_columns = list(col_names)
                    )
                }
            },
            error = function(e) {
                # Construct error message carefully, as sheet_name might not be defined
                # if the error happens before or during sheet_names <- excel_sheets(file_path)
                base_error_msg <- paste("  Error processing file:", basename(file_path))
                current_sheet_name <- NULL
                if (exists("sheet_name", inherits = FALSE) && !is.null(sheet_name)) {
                    current_sheet_name <- sheet_name
                }

                if (!is.null(current_sheet_name)) {
                    print(paste0(base_error_msg, ", Sheet: ", current_sheet_name, ", Error: ", e$message))
                } else {
                    print(paste0(base_error_msg, ", Error: ", e$message))
                }
            }
        )
    }

    if (length(inspection_results) > 0) {
        final_summary_df <- bind_rows(inspection_results)
        output_file <- here("output", "excel_sheet_inspection_summary.csv")
        if (!dir.exists(here("output"))) {
            dir.create(here("output"))
        }
        write.csv(final_summary_df %>% select(-all_columns), output_file, row.names = FALSE) # Store summary without list column

        # For easier viewing of columns in console, save a text file too
        output_txt_file <- here("output", "excel_sheet_inspection_details.txt")
        sink(output_txt_file)
        for (i in 1:nrow(final_summary_df)) {
            cat(paste("File:", final_summary_df$file_path[i], "\n"))
            cat(paste("Sheet:", final_summary_df$sheet_name[i], "\n"))
            cat(paste("AGS Column Found:", final_summary_df$ags_column_found[i], "\n"))
            if (final_summary_df$ags_column_found[i]) {
                cat(paste("Identified AGS Column:", final_summary_df$identified_ags_column[i], "\n"))
            }
            cat("All Columns:\n")
            # Format columns for better readability
            col_output <- paste0("  - ", unlist(final_summary_df$all_columns[i]))
            cat(paste(col_output, collapse = "\n"), "\n")
            cat("---\n")
        }
        sink()
        print(paste("Saved detailed inspection report to:", output_txt_file))
        print(paste("Saved summary CSV to:", output_file))
        return(final_summary_df)
    } else {
        print("No sheets were processed for inspection.")
        return(invisible(NULL))
    }
}

# --- Main Execution ---
# Define the directories to scan (Paket_1 and Paket_2)
target_data_dirs <- c(
    here("data", "Paket_1"),
    here("data", "Paket_2")
)

print(paste("Starting Excel sheet inspection for directories:", paste(target_data_dirs, collapse = ", ")))
inspection_summary <- inspect_excel_sheets(target_data_dirs)

if (!is.null(inspection_summary)) {
    print("--- Inspection Summary ---")
    # Print a concise summary to the console
    print(
        inspection_summary %>%
            select(file_path, sheet_name, ags_column_found, identified_ags_column) %>%
            filter(ags_column_found == TRUE) %>%
            head(20) # Show first 20 relevant sheets
    )
    print(paste("Total sheets with AGS found:", sum(inspection_summary$ags_column_found)))
} else {
    print("Inspection did not yield any results.")
}

print("Excel sheet inspection script finished.")
