# Progress and Problems

Project log: where the work stands, what was changed on top of the existing project, which decisions were taken, and what is still open. Last updated 2026-11-22.

## 1. Where we are

| Area | State |
|---|---|
| Raw data explored (JogjaPulse, UMKM, boundaries) | Done (`steps/01_eda_raw.py`) |
| Kapanewon key table | Done twice: `steps/02_build_dim_kapanewon.py` (Python, CSV) and `staging.dim_kapanewon` (SQL, DuckDB) |
| SQL data mart (`sql/01` to `sql/06`) | Runs end to end via `steps/03_run_sql.py`; output `data/warehouse/jogjapulse.duckdb` |
| Final table | `mart.diy_mobility_commerce`: 78 rows, one per kapanewon |
| Indicator design | Under review (see sections 5 and 6) |
| Reliability tiers, maps, charts | Not started |

## 2. The existing project (baseline)

Commit `0ac230f` "feat: build DIY mobility-commerce data mart foundation" (Josh Jovancio). It added:

- `sql/01` to `sql/06`: POI download, staging, UMKM QA, spatial assignment, mobility indicators, commercial context.
- `data/interim/geo/`: kapanewon boundary GeoJSON files (one is the Geoportal DIY layer, identical to `data/raw/AdminBoundary/`).
- A rewritten README that scopes the project to all 78 DIY kapanewon, with Sleman UMKM as supporting context.

## 3. Changes made on top of the existing project

### 3.1 Edits to existing files

| File | Change | Why | Result |
|---|---|---|---|
| `sql/03_umkm_quality_assurance.sql` | Omzet-mismatch rule now applies to every kapanewon (was hard-coded to Depok). Issue code `FLAG_DEPOK_OMZET_COMPONENT_MISMATCH` renamed to `FLAG_OMZET_COMPONENT_MISMATCH` | Ngemplak has a Rp 500 bn mismatch (same size as Depok) and passed as `PASS` | 2 rows flagged (Depok, Ngemplak); `PASS` 15 to 14 |
| `sql/06_commercial_context.sql` | Tourism regex `park` now matches whole words only: `(^|_)park($|_)` | `parking` POIs were counted as tourism | 48 POIs moved to `other`; tourism 1,033 to 985 |
| `sql/06_commercial_context.sql` | Added column `data_gap_note` to `mart.diy_mobility_commerce` | A missing metric means "insufficient data", not "low opportunity" | Rongkop is flagged; the other 77 kapanewon are NULL |
| `sql/05_mobility_indicators.sql` | Daily presence and cell-concentration indicators restricted to 2021-12-01 to 2022-02-28 through two variables at the top of the file (`analysis_start`, `analysis_end`) | The README already limited OD to Dec-Feb, but presence used all 151 days; Mar-Apr is unstable (rank correlation with Dec-Feb only 0.48, top-10 overlap 2 of 10) | 90 days per table; 74 of 78 kapanewon have all 90 days |
| `README.md` | Merged with the baseline README (conflict resolved); added glossary, repo structure, folder rules, setup, extra caveats, the Dec-Feb rule, the generalized omzet rule | Teammates need one entry point | Baseline content kept as written |

### 3.2 Added

- `steps/` numbered scripts: `00_extract_umkm_pdfs.py` (legacy), `01_eda_raw.py`, `02_build_dim_kapanewon.py`, `03_run_sql.py` (runs the SQL stages in order against one DuckDB file, SQL untouched).
- `src/helpers/`: `loaders.py` (read every raw file with explicit dtypes), `profiling.py`.
- `requirements.txt`, `data/raw/UMKM/README.md`, `data/raw/AdminBoundary/README.md`, this file.

### 3.3 Renamed or moved

- `data/raw/BatasWilayah/batas_kapanewon_diy.*` to `data/raw/AdminBoundary/kapanewon_boundary_diy.*`; removed `.sbn`, `.sbx` (regenerable) and `.shp.xml` (contained an internal network path).
- `src/extract_umkm_pdfs.py` to `steps/00_extract_umkm_pdfs.py`; `src/build_dim_kapanewon.py` to `steps/02_build_dim_kapanewon.py`.

## 4. Decisions taken

1. Work on the baseline's DIY-wide scope; Sleman UMKM is used as the validation case (the only place with supply-side ground truth).
2. Compare kapanewon on Dec-Feb only; Mar-Apr is robustness only.
3. Fix the QA gaps (Ngemplak) and the parking misclassification now.
4. Leave the HHI and penetration-adjustment indicators unchanged for now, and only try alternatives in a sandbox.
5. Treat Rongkop as "insufficient data" instead of a low score.
6. The baseline author could not be reached, so none of the edits above were agreed with him. His SQL was edited minimally and the changes are listed in 3.1.
7. Local deletions made earlier by the repo owner: the pipeline plan document and the reference paper PDF (not in the repo).

## 5. Sandbox trials (not applied to the repo)

### 5.1 Normalized HHI: `(HHI - 1/n) / (1 - 1/n)`

Dec-Feb data, days with at least 3 published cells (days with 2 or fewer cells were dropped: 492 of 6,909).

| | Raw HHI | Normalized HHI |
|---|---|---|
| Rank correlation with number of published cells (across kapanewon) | -0.72 | **-0.15** |
| Month-to-month rank stability (Dec-Jan, Jan-Feb, Dec-Feb) | 0.89, 0.75, 0.66 | 0.84, 0.65, 0.54 |

- Rankings agree reasonably (Spearman 0.74, top-10 overlap 8 of 10).
- It removes most of the dependence on cell count, but it is somewhat less stable between months (the stable part of raw HHI was partly the cell-count effect).
- Most concentrated: Nglipar, Samigaluh, Gondomanan (all with only 4 to 8 cells), then Seyegan and Pakem (about 24 to 31 cells). Seyegan and Pakem contain the bursty hotspot cells in problem 3.
- Verdict: better than raw HHI, but still needs a minimum number of cells and protection against bursty cells.

### 5.2 Option B: within-area ratios (`day_night_ratio`, `weekend_weekday_surge`) instead of the penetration adjustment

Rank stability between months (Dec-Jan, Jan-Feb, Dec-Feb):

| Indicator | Stability |
|---|---|
| Raw daytime presence | 0.97, 0.97, 0.91 |
| Penetration-adjusted index (current) | 0.82, 0.76, 0.55 |
| Day/night ratio | 0.76, 0.44, 0.35 |
| Weekend/weekday surge | 0.53, 0.52, 0.58 |

- The within-area ratios are **less stable** than the adjusted index: a ratio of two small numbers (about 10 daytime vs 6 night devices in rural kapanewon) is noisy.
- Day/night ratio measures the shape of the day (when devices are seen), not crowd size, and it also reflects app-usage rhythm. Medians by regency: Kulon Progo 2.91, Bantul 2.66, Sleman 2.59, Yogyakarta 2.29, Gunungkidul 2.19. Its extremes are dominated by small-sample rural kapanewon.
- Useful reading: Gondomanan has day/night = 1.00 (devices present day and night, a visitor/hotel profile).
- Verdict: **option B is not a good main indicator** (this revises the earlier recommendation). Keep it as a descriptive complement, together with a size measure and reliability flags.

## 6. Remaining problems

1. **Penetration adjustment still active** (`sql/05`, sections 2, 3 and 6). Daytime presence is divided by the device-to-population ratio (0.009 to 2.25), so one device stands for about 107 people in Tepus and 0.44 in Gondomanan. Rank correlation of the adjusted index with raw presence is only 0.44 (Dec-Feb). Visitor-heavy areas (Gondomanan, ratio 2.25) score lowest. Raw presence is almost the same ranking as `n_users` (0.98). Options A (no adjustment), C (guarded adjustment) or a hybrid are still undecided; B alone is ruled out by 5.2.
2. **HHI depends on the number of published cells** (-0.72 across kapanewon). Normalized HHI helps (5.1) but is not applied.
3. **Bursty hotspot cells are not filtered.** Three cells peak on the same day (2021-12-11: 6,459, 5,554 and 3,022 devices); a Cangkringan cell peaks at 7,899 on 2022-02-06; a Kalasan cell appears on 5 days at about 958. Cause unknown (event or data artifact). They distort concentration indicators.
4. **Overture POI coverage is uneven.** Compared with Sleman UMKM F&B counts, POIs cover 142% in Depok but 4 to 5% in Tempel, Seyegan, Moyudan and Minggir (about 34% overall; Depok's 142% uses all confidence levels, about 48% with confidence >= 0.7). Counts partly measure how well a place is mapped. Cleaning cannot fix this; it needs a design decision (relative context only, or calibration with Sleman UMKM).
5. **POI category cleanup pending.** The F&B group mixes about 15,000 food-service POIs, about 3,800 lodging and about 1,200 food retail/other (`grocery_store` 838, `health_food_store` 179, `food_beverage_distributor` 107); `park_and_ride` (1) is still tourism; 134 duplicates (same name within 50 m, 0.2%); 66% of F&B POIs fall below the 0.7 confidence cut.
6. **Rongkop has no external OD metric and no high-confidence commercial POI** (tiny sample: 95 home devices in Dec; 45.9% of hourly slots published). Flagged in `data_gap_note`; maps and rankings must show "insufficient data".
7. **35 cells (0.6%) are not assigned to any kapanewon** (`ST_Intersects` has no nearest-polygon rule in `sql/04`; they lie 13 to 322 m outside).
8. **UMKM QA is thin.** The labor rule is Gamping-specific and only catches female > 5x male; labor and asset values (for example Depok assets Rp 6.1 trillion) are unverified against the source.
9. **UMKM reference year is not stated** in the files.
10. **Licenses and terms are unchecked**: Overture (release 2026-11-18.0), JogjaPulse (the README still has a license placeholder) and Geoportal DIY.
11. **Duplication**: two copies of the boundary (`data/raw/AdminBoundary/` and `data/interim/geo/`), two kapanewon key tables (Python and SQL), and two numbering systems (`steps/` and `sql/`).
12. **Scope disagreement not settled**: the original plan was Sleman-only; the baseline README is DIY-wide.
13. **No reliability tiers per kapanewon yet** (hourly-slot coverage, device counts, number of cells). Gunungkidul is the weakest (median 83.5% of hourly slots published in Dec-Feb, minimum 33%).
14. **Stage 01 needs internet and takes about 8 minutes**; its output is git-ignored, so every teammate has to run it once.
15. **Housekeeping**: the merge from `origin/main` and all edits listed in section 3 are not committed yet.

## 7. Open decisions

- Penetration indicator: option A, C, hybrid, or keep as is (problem 1).
- Add normalized HHI as a new column, with a minimum cell count and a bursty-cell guard (problems 2 and 3).
- How to treat POI coverage bias (problem 4) and whether to apply the category cleanup (problem 5).
- Final project scope (problem 12) and who owns the key table and boundary (problem 11).
