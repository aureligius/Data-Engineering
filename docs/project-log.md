# Project Log

This file records what changed, what was decided, what was tested, and what remains unresolved. Read it before changing the pipeline. Last updated 2026-11-23.

## 1. The short version

- The upstream pipeline builds one DIY-wide table with 78 rows, one per kapanewon, in `mart.diy_mobility_commerce`.
- The final opportunity mart, candidate list, maps, and conclusions cover Sleman's 17 kapanewon only.
- We fixed four problems in the existing SQL (a missed data-quality case, a wrong POI category, the time window, and the crowd-concentration score).
- The "penetration adjustment" mostly repeats population size, so it remains a sensitivity/context metric. The plain crowd-size index leads the final Sleman score.
- The second biggest is that Overture POIs are much more complete in the city than in rural areas, so POI counts cannot be compared across places without care.
- The final Sleman figure script is `src/create_sleman_figures.py`; it has generated the three final Sleman figures and two supporting CSV tables in `outputs/`.

## 2. What we started from

The project already had a first version from Josh Jovancio (commit `0ac230f`, "feat: build DIY mobility-commerce data mart foundation"). It contained:

- Six SQL stages in `sql/` (download shop and restaurant locations, load all sources, check UMKM data quality, place cells on the map, compute crowd indicators, compute commercial context). A seventh stage now builds the final Sleman opportunity mart.
- Boundary files in `data/interim/geo/`. One of them is the same Geoportal DIY layer as our `data/raw/AdminBoundary/`.
- A README that covers all 78 kapanewon in DIY, with Sleman UMKM as supporting context.

## 3. What we changed

### 3.1 Fixes to the existing files

1. **UMKM quality check missed Ngemplak** (`sql/03_umkm_quality_assurance.sql`).
   The check for "stated turnover does not match the sum of its parts" only looked at Depok. Ngemplak has the same problem (a gap of Rp 500 billion) and was marked as fine. The rule now applies to every kapanewon. Result: two kapanewon are flagged (Depok and Ngemplak). The issue code was renamed from `FLAG_DEPOK_OMZET_COMPONENT_MISMATCH` to `FLAG_OMZET_COMPONENT_MISMATCH`.

2. **Car parks were counted as tourism** (`sql/06_commercial_context.sql`).
   The word `park` also matched `parking`. It now only matches the whole word. Result: 48 car parks moved to "other", and tourism POIs went from 1,033 to 985.

3. **A missing value now says why** (`sql/06_commercial_context.sql`).
   We added a column called `data_gap_note`. If a kapanewon has no flow data or no commercial POIs, the note says so. "Missing" should read as "not enough data", not "low opportunity". Only Rongkop is flagged.

4. **Crowd indicators now use December to February only** (`sql/05_mobility_indicators.sql`).
   The README already limited visitor flows to Dec-Feb, but the crowd indicators used all five months. From March the device sample becomes much smaller and different, so rankings jump around (the ranking from Mar-Apr matches the Dec-Feb ranking only weakly, and only 2 of the top 10 kapanewon are the same). The window is set by two variables at the top of the file (`analysis_start`, `analysis_end`), so it is easy to change.

5. **A fairer crowd-concentration score** (`sql/05_mobility_indicators.sql`, new columns also in `sql/06`).
   See section 5.1. The old score is kept; the new one is added next to it.

6. **A plain crowd-size index, added next to Josh's** (`sql/05_mobility_indicators.sql`, new columns also in `sql/06`).
   Josh's index divides the daytime crowd by the share of residents who appear in the data (see 5.3). We left it exactly as it was. Next to it we added `relative_daytime_index`: the same daily comparison with the DIY median, but without that division. We also added `penetration_adjustment_flag`, which marks kapanewon where Josh's adjustment cannot be trusted (more home devices than residents, or fewer than 1,000 home devices). 15 of the 78 are flagged (11 in Gunungkidul, 3 in Yogyakarta City, 1 in Bantul). We checked that no existing column changed value.

7. **README**: merged our version with Josh's, and added a glossary, the folder structure, how to run things, and extra warnings about the data.

### 3.2 New things we added

- `steps/`: numbered scripts. `00` extracts UMKM tables from PDFs (old, optional), `01` explores the raw data, `02` builds a kapanewon key table, `03` runs all the SQL steps in order.
- `src/helpers/`: shared code (`loaders.py` reads every raw file correctly, `profiling.py` summarises tables).
- `requirements.txt`, a README for `data/raw/UMKM/`, a README for `data/raw/AdminBoundary/`, and this file.

### 3.3 Renamed or moved

- `data/raw/BatasWilayah/batas_kapanewon_diy.*` is now `data/raw/AdminBoundary/kapanewon_boundary_diy.*`. We deleted the spatial index files (they can be rebuilt) and the ArcGIS metadata file (it contained an internal network path).
- The two Python scripts that used to be in `src/` now live in `steps/`.

## 4. Decisions so far

1. Process all of DIY for regional mobility context, but make Sleman's 17 kapanewon the final opportunity scope because only Sleman has formal sector-level UMKM counts.
2. Compare kapanewon using Dec-Feb only. March and April are only a sanity check.
3. Fix the clear mistakes now (Ngemplak, car parks).
4. Do not remove Josh's "penetration adjustment". Keep it with warning flags as a sensitivity/context metric; use the plain crowd-size index as the final score's primary crowd component.
5. Show Rongkop as "not enough data", not as a low score.
6. Josh could not be reached, so none of the edits above were agreed with him. We kept the edits small and listed them all in section 3.1 so he can review them.

## 5. Things we tried

### 5.1 Crowd-concentration score (HHI): fixed and applied

**What it is.** For each kapanewon and day, HHI says how concentrated the crowd is. Close to 0 means people are spread over many 500 m cells. Close to 1 means almost everyone is in one cell.

**What was wrong.** The data publisher hides every cell-day with fewer than 5 devices (for privacy). So some cells disappear from the data, and fewer cells mean a higher score even if people spread out the same way. In March and April, when the sample shrinks, the average score jumped from about 0.25 to 0.64 mostly because of this.

**The fix.** We subtract the lowest score that is possible for that number of cells, and we take the middle value (median) across days so a few odd days do not dominate. Days with fewer than 3 visible cells are skipped.

**Result** (all kapanewon, Dec-Feb):

| | Old score | New score |
|---|---|---|
| Does the score follow the number of visible cells? (-1 to 1, closer to 0 is better) | -0.78 | **-0.11** |

Examples, new score (old score): Nglipar 0.63 (0.73), Seyegan 0.41 (0.38), Pakem 0.41 (0.36), Gondomanan 0.40 (0.59), Tepus 0.15 (0.53), Depok 0.02 (0.04). Tepus and Gondomanan drop a lot because they only have 3 to 4 visible cells, which made the old score look high. Seyegan and Pakem stay high, so their crowd really is concentrated in a few places.

**Still true.** Two kapanewon (Pakualaman with about 2 cells and Ngampilan with 1) have too few visible cells, so they get no score. Scores for kapanewon with only a handful of cells are still shaky. The old column is still there if anyone needs it.

### 5.2 Using day/night and weekend ratios instead of the adjustment: not used

Idea: compare daytime with night-time in the same kapanewon, so we would not need the population adjustment.

We checked whether each indicator gives a similar ranking month after month (1 means identical):

| Indicator | Dec vs Jan | Jan vs Feb | Dec vs Feb |
|---|---|---|---|
| Raw daytime crowd | 0.97 | 0.97 | 0.91 |
| Current adjusted index | 0.82 | 0.76 | 0.55 |
| Day/night ratio | 0.76 | 0.44 | 0.35 |
| Weekend/weekday ratio | 0.53 | 0.52 | 0.58 |

The ratios are less steady than the current index, because in small rural kapanewon they divide two tiny numbers (around 10 devices in the day and 6 at night). They also describe the shape of the day, not how big the crowd is. We keep them as extra description, not as the main score. One useful reading: Gondomanan has a day/night ratio of 1.00, which means people are there all day and all night (visitors and hotels).

*Note: these trial numbers treat the two kapanewon called Jetis (one in Bantul, one in Yogyakarta City) as one, so they are approximate.*

### 5.3 The penetration adjustment: what we found

**How it works.** Josh's index divides the daytime crowd by the share of residents who show up in the data (devices that live in the kapanewon divided by its official population). The idea is to even out places where fewer people use the apps.

**What we found** (December to February):

- **It is almost the same as population size.** The index equals the population times "daytime crowd per home device", and it follows the population ranking closely (0.89, where 1 means identical).
- **Random noise is not the main problem.** The share of residents is measured from at least 256 devices, so its error is at most about 6%. The real problem is the assumption that people seen in the daytime are as visible as the residents. It fails in Gondomanan, where more devices live than the official population, so the adjustment shrinks its crowd and the busiest visitor area ends up last.
- **Putting a limit on the adjustment changes almost nothing.** The top 10 stays the same. Dividing by home devices instead of population is unstable from month to month and does not follow business counts.
- **Without any adjustment the ranking is steadier** from month to month (0.96, 0.96, 0.90, against 0.80, 0.88, 0.56 for the adjusted index). The catch is that it follows where app users live (0.98 with the number of home devices).
- **In Sleman, population alone follows the number of food-and-drink businesses better (0.86) than any crowd indicator (0.76 to 0.78).** So every crowd indicator partly measures "how big the place is". The useful signal for opportunity is the gap between crowd and businesses, plus the visitor signals Josh already built (visitors from other regencies, day/night, weekend).

**What we did.** We kept Josh's index and added the plain index and the warning flag (section 3.1, item 6). They give different top lists:

- Plain index: Depok, Ngaglik, Banguntapan, Gamping, Kasihan, Mlati, Umbulharjo, Seyegan.
- Josh's index: Banguntapan, Depok, Sewon, Mlati, Kasihan, Gamping, Ngaglik, Kalasan.
- Gondomanan scores 0.06 in Josh's index and 1.9 in the plain one.

## 6. Problems still open

1. **The "penetration adjustment" mostly repeats population size** (details in 5.3). It remains available with a warning flag (15 DIY kapanewon flagged), but `relative_daytime_index` now leads the final Sleman score. The adjusted index is a sensitivity/context metric only.
2. **Some cells spike on a single day, and we do not know why.** Three cells peak on the same day (2021-12-11, with 3,000 to 6,500 devices each), one cell in Cangkringan peaks at 7,899 on 2022-02-06, and one cell in Kalasan shows about 958 devices on 5 days only. It could be an event or a data glitch. They are not filtered out yet.
3. **Overture POIs are much more complete in the city than in the countryside.** Compared with the UMKM food-and-drink counts in Sleman, POIs cover about 48% in Depok (high-confidence only) but only 4 to 5% in Tempel, Seyegan, Moyudan and Minggir. A difference in POI counts therefore says as much about how well a place is mapped as about how many businesses it has. Cleaning cannot fix this. We need to decide how far to trust POI counts.
4. **POI categories are mixed.** The food-and-drink group includes about 3,800 hotels and lodgings and about 1,200 food shops (such as `grocery_store`, 838). One `park_and_ride` is still counted as tourism. There are 134 duplicates (same name within 50 m, 0.2%). About two thirds of food-and-drink POIs fall under our confidence cut-off of 0.7.
5. **Rongkop has no visitor-flow score and no commercial POIs** (only 95 devices live there in December, and only 46% of its hourly data is published). It is flagged in `data_gap_note`. Maps and rankings must show "not enough data".
6. **Pakualaman and Ngampilan have no concentration score**, because they have fewer than 3 visible cells.
7. **35 map cells (0.6%) are not assigned to a kapanewon.** Their centre points sit 13 to 322 m outside every boundary. A "nearest boundary" rule would fix it.
8. **UMKM quality checks are thin.** The labour check only looks at Gamping and only catches women above 5 times men. Labour and asset numbers (for example Depok assets of Rp 6.1 trillion) have not been checked with the source.
9. **We do not know the year of the UMKM data.**
10. **Licenses are not checked** for Overture, JogjaPulse (its README still has a placeholder) and Geoportal DIY.
11. **Duplicated work:** two copies of the boundary (`data/raw/AdminBoundary/` and `data/interim/geo/`), two kapanewon key tables (Python and SQL), and two numbering systems (`steps/` and `sql/`).
12. **Scope resolved:** DIY remains the upstream mobility context, while Sleman is the final opportunity scope. Documentation and final outputs must use this distinction consistently.
13. **No reliability labels yet.** Maps and rankings should show how much data stands behind each kapanewon (hourly coverage, number of devices, number of cells). Gunungkidul is the weakest: its median kapanewon has 83.5% of hourly data published and the lowest has 33%.
14. **The POI download needs internet and takes about 8 minutes.** Its output is not in Git, so everybody has to run it once.

## 7. Decisions we still need

- Whether to apply further POI category cleanup for the optional geographic-context maps (problems 3 and 4).
- Whether to filter the single-day spike cells (problem 2).
- Whether to retire the old DIY-wide figure script and duplicate raw boundary folder after the final Sleman figures are verified.

## 8. Final scope decision: Sleman

The final opportunity mart, candidate list, maps, and conclusions cover Sleman's 17 kapanewon.

DIY-wide mobility processing remains necessary because it provides:

- daily regional baselines for mobility normalization;
- external-origin visitor inflows into Sleman; and
- broader spatial context for interpreting Sleman activity.

The final supply metric uses registered Sleman F&B/accommodation and retail-trade UMKM counts from `rekapumkmsektorusaha.csv`. Overture POIs remain available as supporting geographic context but are excluded from the final supply-gap score because urban and rural mapping coverage differs substantially.

The primary crowd-size metric is `relative_daytime_index`. The penetration-adjusted `relative_adjusted_daytime_index` remains available with `penetration_adjustment_flag` for sensitivity checks and interpretation, but is not used as the primary final ranking input.

## 9. Cleanup decision

The canonical warehouse is `data/warehouse/jogjapulse.duckdb`; the canonical boundary source is `data/raw/AdminBoundary/`; and the canonical final visualization script is `src/create_sleman_figures.py`.

The old DIY-wide warehouse, figures, tables, and local duplicate boundary folder are pending deletion only after the final Sleman pipeline has been rebuilt and checked. The exact retained, regenerable, historical, and deletion-pending artifacts are listed in `docs/artifact-lifecycle.md`.
