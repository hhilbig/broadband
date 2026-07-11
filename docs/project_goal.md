# Project Goal

This project harmonizes historical Breitbandatlas data into a municipality-level panel of broadband availability in Germany.

The pipeline preserves a long-format intermediate file with municipality-year-technology-speed observations (`output/broadband_gemeinde_combined_long_ags2021.rds`). The public release is a wide municipality-year panel (`output/panel_data_public.csv`) with one row per municipality-year.

Municipality identifiers use 8-digit AGS codes standardized to Destatis 2021 boundaries. The public data preserve as much usable speed-tier information as the source files allow while documenting the main limitations: no 2009 municipality panel, early years with only baseline DSL coverage, changing speed-tier menus (the share columns are measured at stricter tiers than their names suggest before 2018; see the `tier_*` columns), only reporting municipalities in 2010-2014, a 2015 provider change, and a small share of historical AGS codes that cannot be mapped defensibly to 2021 boundaries.
