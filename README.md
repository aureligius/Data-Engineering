# Crowds and Commerce: Mapping Mobility-Based Market Opportunity for UMKM in Sleman

Where are the crowds in Sleman, and which kapanewon (sub-districts) have many people but few businesses?
This repo combines mobile-device mobility data (**JogjaPulse**), small-business counts (**UMKM**) and
**administrative boundaries**, joined at the kapanewon level, to explore market opportunity for UMKM.

## Glossary

| Term | Meaning |
|---|---|
| **Kapanewon** | Sub-district (= kecamatan) in DIY. Hierarchy: province > 5 regencies/city > 78 kapanewon > kalurahan |
| **Kabupaten / Kota** | Regency / city. Sleman Regency contains 17 kapanewon |
| **UMKM** | Micro, small and medium enterprises |
| **MAID / `n_maids`** | Distinct mobile devices (not people). Not additive across places or hours |

## Data sources (`data/raw/`, read-only)

| Folder | What it is | Role |
|---|---|---|
| `JogjaPulse/` | Aggregated device presence and origin-destination flows for DIY, Dec 2021 - Apr 2022 (UGM, Zenodo). Has its own `README.md` | **Demand**: when and where people gather and move |
| `UMKM/` | Business recap by kapanewon, sector and scale, **Sleman only** | **Supply**: how many businesses, of what kind |
| `AdminBoundary/` | Shapefile with 78 kapanewon polygons | **Location**: maps, and assigns 500 m cells to kapanewon |

All three join on the **kapanewon code** (e.g. `34.04.12` = Ngaglik). UMKM only has names, so `steps/02_build_dim_kapanewon.py` builds the bridge table.

## Repo structure

```
.
├── README.md                this file
├── requirements.txt         Python dependencies
├── data/
│   ├── raw/                 original data, never edited (see each folder's README)
│   └── curated/             step outputs, git-ignored, regenerate by running steps
├── steps/                   numbered scripts, run in order (see below)
│   ├── 00_extract_umkm_pdfs.py     optional legacy PDF -> CSV extraction
│   ├── 01_eda_raw.py               exploration of all raw data
│   └── 02_build_dim_kapanewon.py   kapanewon key table (JogjaPulse <-> UMKM)
└── src/
    └── helpers/             reusable code only, imported by steps
        ├── loaders.py              read every raw file with explicit dtypes
        └── profiling.py            profiling tables for EDA
```

### How the folders work

- **`steps/`** - the work, in order. A file `NN_name.py` is one step; the number is the run order.
  Each starts with a header stating its **purpose, input, output and how to run it**.
  To add a step, take the next number (e.g. `03_clean_presence.py`) and write that header.
  EDA-style steps use `# %%` cells, so VS Code opens them as notebooks; they also run as plain scripts.
- **`src/helpers/`** - reusable building blocks that steps import. Helpers never run on their own:
  no `main()`, no file writes at import time, no step-specific logic. If code is used by only one step, keep it in that step.
- **`data/raw/`** is immutable. **`data/curated/`** only holds step outputs and is git-ignored, so anyone can rebuild it.
- Steps add the repo root to `sys.path`, so always import helpers as `from src.helpers.loaders import ...`.

## Setup and run

```bash
python -m venv .venv
.venv\Scripts\activate            # Windows (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt

python steps/01_eda_raw.py         # or open the file in VS Code and run cell by cell
python steps/02_build_dim_kapanewon.py
```

## Data caveats (read before analysing)

- **The device sample shrinks over time** (mean distinct devices/day falls from about 87k in Dec 2021 to about 9k in Apr 2022, per the JogjaPulse README), and its composition shifts by area. Compare kapanewon using **Dec - Feb** only; treat Mar - Apr as robustness checks.
- **A missing row is not zero**: it means fewer than 5 devices (suppression).
- **Kapanewon names are not unique** (JETIS exists in Bantul and Yogyakarta City). Join on the code.
- **UMKM labor, asset and turnover columns contain outliers**; business counts are the cleaner signal. The UMKM reference year is not stated in the files.
- Check the JogjaPulse license (Zenodo) and Geoportal DIY terms before redistributing the data.

## Status

| Step | State |
|---|---|
| 00 PDF extraction | legacy, optional |
| 01 Raw EDA | done |
| 02 `dim_kapanewon` | done |
| Next | Sleman-focused EDA, assign cells to kapanewon, curated tables, maps and charts |
