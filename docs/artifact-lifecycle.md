# Artifact Lifecycle

This document records what the final Sleman pipeline needs, what can be regenerated, and what is pending deletion. It is a cleanup plan, not authorization to delete files.

## Retain

| Artifact | Reason |
|---|---|
| `data/raw/JogjaPulse/` | Immutable historical mobility source used for all upstream indicators. |
| `data/raw/UMKM/` | Immutable Sleman formal-UMKM source and ETL-QA source. |
| `data/raw/AdminBoundary/` | Canonical official DIY Geoportal shapefile source. |
| `data/interim/geo/diy_kapanewon_geoportal.geojson` | WGS84 derived boundary consumed by DuckDB spatial SQL. |
| `sql/01_download_overture_pois.sql` through `sql/07_opportunity_screening.sql` | Reproducible SQL pipeline. Stage 07 is the final Sleman opportunity mart. |
| `steps/01_eda_raw.py` through `steps/03_run_sql.py` | Reproducible EDA, key-check, and pipeline-run workflow. |
| `src/helpers/` | Shared read-only loading and profiling helpers. |
| `src/create_sleman_figures.py` | Canonical final-figure generator. |
| `README.md`, `docs/project-log.md`, and this file | Current project documentation. |

## Regenerate; do not commit

| Artifact | How it is recreated |
|---|---|
| `data/raw/external/poi/overture_places_diy_2026-11-18.geojson` | Run `python steps/03_run_sql.py 01`; requires internet. |
| `data/warehouse/jogjapulse.duckdb` | Run `python steps/03_run_sql.py`. |
| `data/curated/dim_kapanewon.csv` | Run `python steps/02_build_dim_kapanewon.py`. |
| `audit.sleman_sensitivity_*` (in the warehouse) and `outputs/tables/sleman_sensitivity_*.csv` | Run `python steps/04_sensitivity_sleman.py` after stage 07. |
| `outputs/figures/sleman_*.png` | Run `python src/create_sleman_figures.py`. |
| `outputs/tables/sleman_*.csv` | Run `python src/create_sleman_figures.py`. |

The warehouse, POI download and `data/curated/` are git-ignored (reproducible or large). `outputs/` (figures and tables, about 2 MB) is **not** git-ignored, so the team can look at the results on GitHub; regenerate and commit them again whenever the pipeline changes.

## Pending deletion after final verification

| Artifact | Why it is obsolete |
|---|---|
| `data/raw/BatasWilayah/` | Local duplicate of the canonical boundary source now stored in `data/raw/AdminBoundary/`. |
| `data/warehouse/diy_mobility_commerce.duckdb` | Older local warehouse superseded by `data/warehouse/jogjapulse.duckdb`. |
| `outputs/figures/01_diy_*.png` through `outputs/figures/05_*.png` | Superseded by the final Sleman figures. |
| `outputs/tables/diy_market_opportunity.csv` | Superseded by `outputs/tables/sleman_market_opportunity.csv`. |
| `outputs/tables/high_mobility_low_supply_candidates.csv` | Superseded by `outputs/tables/sleman_opportunity_candidates.csv`. |

Before deleting the pending artifacts, run:

```powershell
python .\steps\03_run_sql.py
python .\src\create_sleman_figures.py
```

Then confirm that the final mart has 17 rows:

```powershell
duckdb .\data\warehouse\jogjapulse.duckdb -c "SELECT count(*) AS sleman_kapanewon FROM mart.sleman_market_opportunity;"
```

Expected result: `17`.

## Historical but retained files

| Artifact | Status |
|---|---|
| `data/interim/geo/diy_kapanewon.geojson` and `.qmd` | Older HDX-derived boundary output. Retained temporarily as historical provenance; not used by the final SQL pipeline. |
| `steps/00_extract_umkm_pdfs.py` | Legacy optional extractor. The original UMKM PDFs are unavailable in this workspace; the project uses the supplied CSV extracts. |

Do not remove these historical files until the team agrees that provenance is sufficiently documented elsewhere.
