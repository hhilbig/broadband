# Harmonized historical broadband data for German municipalities

This project cleans, harmonizes, and combines historical broadband availability data for German municipalities ("Gemeinden") from 2005 to 2021, creating a panel dataset suitable for longitudinal analysis.

## Key features

- **Municipality-level panel**: The final output is a panel dataset where each row represents a municipality-year observation.
- **Harmonized borders**: All municipal boundaries have been standardized to their 2021 borders to ensure consistency over time. The dataset therefore accounts for mergers and administrative reforms that have occured prior to 2021.

## Data provenance and quality

This dataset is a best-effort attempt to harmonize data from various historical sources provided by the Breitbandatlas. Users should be aware of the following:

- **Limited documentation**: The historical broadband data comes from multiple providers and periods. According to direct correspondence with the Bundesnetzagentur, detailed information on how the original data was compiled, processed, or defined is not available. The Bundesnetzagentur cannot answer many technical questions about earlier data. Some relevant documentation may be found in archived reports, but many specifics remain unclear. The repo contains some reports on the data in [](./docs/breitband_reports/)
- **Inconsistent sources**: Changes in data providers, reporting standards, and variable definitions likely lead to inconsistencies in the data.
- **The "2015 jump"**: There is a visible jump in coverage metrics between 2014 and 2015, likely due to a change in data provider and methodology (e.g., switch from *infas* to *Nexiga* for the household base). A dummy variable (`method_change_2015`) is included in the final dataset to flag this.

## Project resources

- **Data processing pipeline**: For a complete overview of the cleaning, harmonization, and variable creation process, see the detailed documentation: **[Data Processing Pipeline](./docs/data_processing_pipeline.md)**.
- **Final dataset**: The final, analysis-ready panel dataset can be found here: **[panel_data_with_treatment.csv](./output/panel_data_with_treatment.csv)**.

---

## Data source and attribution

Source: Breitbandatlas | Gigabit-Grundbuch (<https://gigabitgrundbuch.bund.de>)

Please note: As required by the Bundesnetzagentur, the source must be cited, and any changes or interpretations (including this harmonized dataset) must be clearly indicated as the result of independent processing and coding decisions. The data is provided "as is" and may contain gaps or ambiguities due to the limited information available from the original sources.
