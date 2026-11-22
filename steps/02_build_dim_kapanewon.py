"""02 - Build `dim_kapanewon`: one location key table for JogjaPulse and UMKM.

Why: UMKM only has kapanewon names (e.g. "Ngaglik") and only covers Sleman, while
JogjaPulse and the boundary file use kapanewon codes (e.g. 34.04.12). Names alone are
not unique (JETIS exists in Bantul and Yogyakarta City), so the join uses
(regency, name) for UMKM and the code everywhere else.

Input:  data/raw/JogjaPulse (hourly presence, home vs population), data/raw/UMKM
Output: data/curated/dim_kapanewon.csv  (78 rows, one per kapanewon; git-ignored)
Run:    python steps/02_build_dim_kapanewon.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import pandas as pd

from src.helpers.loaders import load_home_vs_population, load_presence_hourly, load_umkm_per_kapanewon

OUT = ROOT / "data" / "curated"
UMKM_REGENCY = "SLEMAN"  # all UMKM data is Sleman


def norm_name(value: str) -> str:
    return re.sub(r"\s+", " ", str(value)).strip().upper()


def build() -> pd.DataFrame:
    hourly = load_presence_hourly()[["kab_code", "kab_kota", "kapanewon_code", "kapanewon"]].drop_duplicates()
    pop = load_home_vs_population().rename(columns={"KAB_KOTA": "kab_kota", "KEC_KAPN": "kapanewon"})

    dim = hourly.merge(pop, on=["kab_kota", "kapanewon"], how="left", validate="1:1")
    dim["join_key"] = dim["kab_kota"].map(norm_name) + "|" + dim["kapanewon"].map(norm_name)

    umkm = load_umkm_per_kapanewon()
    umkm = umkm[umkm["Kapanewon"].notna() & (umkm["Kapanewon"] != "Total")]  # drop blank-name and total rows
    umkm_keys = set(UMKM_REGENCY + "|" + umkm["Kapanewon"].map(norm_name))
    dim["has_umkm"] = dim["join_key"].isin(umkm_keys)

    missing = umkm_keys - set(dim["join_key"])
    if missing:
        raise ValueError(f"UMKM kapanewon without a JogjaPulse match: {sorted(missing)}")
    return dim.sort_values("kapanewon_code").reset_index(drop=True)


def main() -> None:
    dim = build()
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "dim_kapanewon.csv"
    dim.to_csv(path, index=False)
    print(f"{len(dim)} kapanewon, {int(dim.has_umkm.sum())} with UMKM data -> {path}")


if __name__ == "__main__":
    main()
