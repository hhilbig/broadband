# Breitbandatlas – what it is, how the data get in, and how they come back out

| Aspect | Key points |
|--------|------------|
| **Purpose & operator** | The Breitbandatlas (BBA) is the public-facing pillar of Germany’s *Gigabit‑Grundbuch*, run by the Bundesnetzagentur’s Zentrale Informationsstelle des Bundes (ZIS). It visualises the technically **possible** fixed‑line and mobile broadband supply for the whole country. |
| **Legal basis & obligations** | Since the 1 December 2021 Telekommunikationsgesetz (TKG) reform, network operators can be **obliged** to deliver supply data (§ 78 (1) 2, § 80 TKG). Deliveries are mandatory twice a year (30 June & 31 Dec) and must arrive within two weeks. |
| **Update rhythm** | Public data now appear with roughly a **six‑month lag** (e.g. fixed‑line: “data‑as‑of 30 Jun 2024”, mobile: “Aug 2024”). |
| **Processing workflow** | 1. Operators upload either **address‑level tables** or **polygons** via a secured portal. 2. ZIS normalises, geocodes and intersects them with supplementary geodata (official BKG layers, Nexiga addresses, admin boundaries, traffic links). 3. A national **100 m × 100 m raster** is generated; for each cell the *maximum* available bandwidth per technology/bandwidth‑class is stored. 4. The raster is aggregated to administrative areas (Bund → Land → Kreis → Gemeinde) and thematic layers (households, schools, businesses, traffic routes etc.). |
| **Broadband dimensions** | *Fixed line* → bandwidth classes ≥ 10, 16, 30, 50, 100, 200, 400, 1000 Mbit/s; technologies FTTB, FTTH, FTTB/H, FTTC, HFC, other. *Mobile* → 2G, 4G, 5G DSS, 5G NSA/SA per operator (Telefónica, Telekom, Vodafone). |
| **Public data products** | *Interactive map* (tile cache + client charts); *WMS service*; a **Download section** offering Excel “Breitbandverfügbarkeit” tables, 100 m rasters (CSV/Geopackage), Shapefiles, PNG maps, and detailed methodology PDFs. |
| **Input data structure (operators → ZIS)** | **Address lists** (CSV/XLSX, UTF‑8): required columns `strasse, hnr, plz, ort, technologie, download, upload`; optional `lat, lon, hnr_z, ortsteil, nutzungstyp`. **Polygons** (Shapefile, GeoJSON, KML) carry geometry only; tech/bandwidth is entered via a portal form. Allowed projections: EPSG 4326/3857/25832/25833; single file ≤ 20 MB. |
| **Output data structure (public downloads)** | **Excel tables**: one worksheet per theme, rows = admin units, columns = bandwidth × technology × user‑group combinations, plus infrastructure stats. **Raster files**: 100 m grid with fields `dl_class`, `ul_class`, `tech_code`, `provider`, `coverage_%` etc. **Administrative summaries** mirror the raster but hold percentage‑of‑households indicators. |
| **Quality safeguards** | Automatic validation (schema, CRS, mandatory fields) plus manual plausibility checks; geocoder fallback if coordinates are missing; discrepancies flagged back to provider (see *Methodenbericht* chapter 3). |

## Practical implications for researchers

* **Spatial granularity:** 100 m raster → robust for micro‑spatial analysis but *not* address‑exact.  
* **Temporal coverage:** historic fixed‑line series back to December 2018; mobile series start with 5G roll‑out (2021/22).  
* **Combine with other data:** the WMS endpoint can be loaded into GIS; raster CSV/GPKG fit well with census micro‑cells or traffic networks.  
* **Licensing:** Free for commercial & non‑commercial use, attribution “Breitbandatlas | Gigabit‑Grundbuch”.
