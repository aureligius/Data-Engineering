# Crowds and Commerce

> **Project log:** decisions, tests, limitations, and open issues are recorded in [docs/project-log.md](docs/project-log.md).

## Mapping Historical Mobility-Based Market Opportunity for UMKM in Sleman

This project builds a **Sleman Mobility-Commerce Data Mart**.

The final analysis covers Sleman's 17 kapanewon. DIY-wide JogjaPulse mobility data remains in the pipeline to calculate regional baselines and measure visitors entering Sleman from other regencies/city areas.

The analysis combines historical mobility indicators with formal registered UMKM counts in F&B/accommodation and retail trade. It identifies areas for field validation; it does not forecast revenue, live demand, or guaranteed business success.

### Research question

Which Sleman kapanewon show historical mobility patterns consistent with relatively stronger opportunity for crowd-dependent UMKM, relative to registered F&B/accommodation and retail-trade UMKM supply?

### Analysis scope

| Dimension                 | Scope                                                                            |
| ------------------------- | -------------------------------------------------------------------------------- |
| Primary study area        | 17 kapanewon in Kabupaten Sleman                                                 |
| Regional mobility context | All 78 DIY kapanewon                                                             |
| Mobility analysis period  | 1 December 2021 to 28 February 2022                                              |
| Spatial resolution        | Kapanewon and published 500m × 500m cells                                        |
| Formal supply source      | Sleman F&B/accommodation and retail-trade UMKM counts                            |
| Overture POI role         | Supporting geographic context only; excluded from final supply score             |
| Intended use              | Historical descriptive opportunity screening and field-validation prioritization |

### Glossary

| Term                 | Meaning                                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------------------- |
| **Kapanewon**        | Sub-district (= kecamatan) in DIY. Hierarchy: province > 5 regencies/city > 78 kapanewon > kalurahan |
| **Kabupaten / Kota** | Regency / city. Sleman Regency contains 17 kapanewon                                                 |
| **UMKM**             | Micro, small and medium enterprises                                                                  |
| **MAID / `n_maids`** | Distinct mobile devices (not people). Not additive across places or hours                            |

### Data sources

1. **JogjaPulse mobility data** (`data/raw/JogjaPulse/`, has its own `README.md`)
   - Daily distinct-device presence by 500m grid cell
   - Hourly distinct-device presence by kapanewon
   - Home-based origin-destination visitation flows
   - Device-to-population ratio by kapanewon

2. **DIY kapanewon boundary polygons** (`data/raw/AdminBoundary/`, shapefile; same layer as `data/interim/geo/diy_kapanewon_geoportal.geojson`)
   - Required to create choropleths.
   - Required to assign 500m grid cells and commercial POIs to kapanewon.

3. **Commercial POIs from Overture** (downloaded by `sql/01_download_overture_pois.sql` into git-ignored `data/raw/external/`)
   - F&B, retail, markets, and tourism locations.
   - Used as supporting geographic context, not as a complete census of businesses or the final supply score.

4. **Sleman UMKM data** (`data/raw/UMKM/`, has its own `README.md`)
   - `rekapumkmsektorusaha.csv` provides the final formal supply measure for the 17 Sleman kapanewon.
   - `rekapdataaset.csv` is used as an ETL quality-assurance example.
   - The Sleman UMKM data is not extrapolated to all DIY.

All sources join on the **kapanewon code** (e.g. `34.04.12` = Ngaglik). UMKM only has names, so it is joined on (regency, name).

## Repo structure

```
.
├── README.md                this file
├── requirements.txt         Python dependencies
├── docs/
│   ├── project-log.md              project decisions, tests, limitations, and open issues
│   └── artifact-lifecycle.md       retained, reproducible, deprecated, and deletion-pending artifacts
├── data/
│   ├── raw/                 original data, never edited (see each folder's README)
│   ├── interim/geo/         boundary GeoJSON used by the SQL stages
│   └── curated/             Python step outputs, git-ignored, rebuilt by running steps
├── sql/                     numbered DuckDB stages, run in order
│   ├── 01_download_overture_pois.sql   download POIs (needs internet)
│   ├── 02_stage_sources.sql            stage all sources, build dim_kapanewon
│   ├── 03_umkm_quality_assurance.sql   UMKM QA tables
│   ├── 04_spatial_assignment.sql       assign cells and POIs to kapanewon
│   ├── 05_mobility_indicators.sql      mobility indicators per kapanewon
│   ├── 06_commercial_context.sql       POI categories and commercial context
│   ├── 07_opportunity_screening.sql    final Sleman opportunity mart
│   └── 08_cell_hotspots.sql            500m hotspots and the Sleman watch list (top 3)
├── steps/                   numbered Python scripts, run in order
│   ├── 00_extract_umkm_pdfs.py         optional legacy PDF -> CSV extraction
│   ├── 01_eda_raw.py                   exploration of all raw data
│   ├── 02_build_dim_kapanewon.py       kapanewon key table (JogjaPulse <-> UMKM)
│   ├── 03_run_sql.py                   runs the sql/ stages into data/warehouse/jogjapulse.duckdb
│   └── 04_sensitivity_sleman.py        sensitivity test of the Sleman opportunity score
└── src/
    ├── create_sleman_figures.py       final Sleman maps, charts, and tables
    ├── create_sleman_hotspot_maps.py  500m hotspot maps for the watch list
    └── helpers/             reusable code only, imported by steps
        ├── loaders.py              read every raw file with explicit dtypes
        └── profiling.py            profiling tables for EDA
```

### How the folders work

- **`sql/`** - the DuckDB data-mart build. `NN_name.sql` is one stage; the number is the run order. Stages create schemas (`staging`, `qa`, `mart`, `audit`) inside one DuckDB database file (`*.duckdb` is git-ignored).
- **`steps/`** - Python work, in order. `NN_name.py` is one step; the number is the run order.
  Each starts with a header stating its **purpose, input, output and how to run it**.
  To add a step, take the next number (e.g. `03_...py`) and write that header.
  EDA-style steps use `# %%` cells, so VS Code opens them as notebooks; they also run as plain scripts.
- **`src/helpers/`** - reusable building blocks that steps import. Helpers never run on their own:
  no `main()`, no file writes at import time, no step-specific logic. If code is used by only one step, keep it in that step.
- **`data/raw/`** is immutable. **`data/curated/`** only holds Python step outputs and is git-ignored, so anyone can rebuild it.
- Steps add the repo root to `sys.path`, so always import helpers as `from src.helpers.loaders import ...`.

## Setup and run

```bash
python -m venv .venv
.venv\Scripts\activate            # Windows (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt

python steps/01_eda_raw.py         # or open the file in VS Code and run cell by cell
python steps/02_build_dim_kapanewon.py
```

Build the data mart (all `sql/` stages, in order, into `data/warehouse/jogjapulse.duckdb`):

```bash
python steps/03_run_sql.py          # all stages; stage 01 downloads POIs from S3 (needs internet, about 8 min)
python steps/03_run_sql.py 02 03    # or only selected stages
python steps/03_run_sql.py 07       # rebuild the final Sleman opportunity mart after stages 01-06 exist
python steps/04_sensitivity_sleman.py  # how stable is the Sleman ranking when weights change (needs stage 07)
python src/create_sleman_figures.py # final Sleman maps, charts, and tables
python src/create_sleman_hotspot_maps.py  # 500m hotspot maps for the watch list (needs stage 08)
```

The DuckDB `spatial` and `httpfs` extensions are installed automatically on first run.

## Opportunity indicators

- Daytime crowd-size index without a population adjustment (`relative_daytime_index`)
- Penetration-adjusted daytime crowd proxy as a sensitivity/context measure
- Day-to-night crowd ratio
- Weekend-to-weekday crowd surge
- External-origin-normalized OD inflow
- 500m cell-presence concentration
- Registered F&B/accommodation UMKM supply
- Registered retail-trade UMKM supply

## Mobility-data rules

- `n_maids` represents distinct observed devices, not people.
- Never sum `n_maids` across cells, hours, dates, or OD destinations.
- A missing/suppressed record means fewer than five devices, not zero.
- Normalize counts within each date before comparing dates because the observed-device sample changes over time.
- Use within-day ratios, daily normalized shares, ranks, and appropriately weighted averages.
- Use `n_pings` only as a device-activity/data-volume measure, not as a people count.
- Restrict OD metrics to December 2021–February 2022 where `reduced_quality = False`.
- Restrict the daily presence indicators (including cell concentration) to the same December 2021–February 2022 window (set at the top of `sql/05_mobility_indicators.sql`).
- Use `relative_daytime_index` as the primary crowd-size metric. Keep `relative_adjusted_daytime_index` and `penetration_adjustment_flag` as sensitivity/context fields, not as the primary ranking input.

## UMKM data-quality rules

- Quarantine the blank row in `rekapdataaset.csv`.
- Flag Gamping's labor anomaly.
- Flag omzet-component mismatches in any kapanewon (currently Depok and Ngemplak).
- Preserve source values and QA flags; do not silently alter source records.

## Additional caveats from EDA

- **The device sample shrinks over time** (mean distinct devices/day falls from about 87k in Dec 2021 to about 9k in Apr 2022, per the JogjaPulse README) and its composition also shifts by area, so normalizing by the daily total is not enough: some kapanewon's share of DIY activity jumps between months. Compare kapanewon using Dec - Feb; treat Mar - Apr as robustness checks.
- **Kapanewon names are not unique** (JETIS exists in Bantul and Yogyakarta City). Join on the code.
- **Hotspot cells can be bursty**: some 500 m cells show thousands of devices on a single day. Filter by days published and prefer medians.
- The UMKM reference year is not stated in the files.
- Check the JogjaPulse license (Zenodo) and Geoportal DIY terms before redistributing the data.

## Explicit non-claims

This project does not claim to measure:

- Live or future demand
- Actual population or exact visitor totals
- Individual movements
- UMKM revenue or business performance
- Causal effects of mobility on business outcomes
- Complete coverage of informal businesses or commercial POIs

## Planned outputs

1. Sleman historical mobility and formal-UMKM-supply quadrant map
2. Sleman mobility-demand versus registered UMKM supply chart
3. Sleman mobility-opportunity candidate ranking and map
4. Day-to-night and weekend-surge analysis
5. External OD inflow analysis
6. Sleman 500m cell-presence concentration analysis
7. Sleman UMKM ETL QA report
8. Reproducible DuckDB, SQL, and Python pipeline

## Artifact lifecycle

The retained source, derived, generated, and deletion-pending artifacts are listed in [docs/artifact-lifecycle.md](docs/artifact-lifecycle.md). Do not delete an artifact until the final Sleman pipeline and figures have been rebuilt successfully from the retained inputs.
