"""Bangun dim_kapanewon: kunci lokasi tunggal yang menyatukan JogjaPulse dan UMKM.

UMKM hanya punya nama kapanewon (mis. "Ngaglik") dan hanya untuk Kabupaten Sleman.
JogjaPulse punya kapanewon_code (mis. 34.04.10) untuk 78 kapanewon se-DIY.
Join memakai (kab_kota = 'SLEMAN', UPPER(nama)) agar kapanewon "SLEMAN" tidak
tertukar dengan Kabupaten SLEMAN.

Output: data/curated/dim_kapanewon.csv  (satu baris per kapanewon, 78 baris)
"""
from pathlib import Path
import re

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
OUT = ROOT / "data" / "curated"

UMKM_KAB = "SLEMAN"  # seluruh data UMKM adalah Kabupaten Sleman


def norm_name(value: str) -> str:
    return re.sub(r"\s+", " ", str(value)).strip().upper()


def build() -> pd.DataFrame:
    hourly = pd.read_csv(
        RAW / "JogjaPulse" / "presence_kapanewon_hourly.csv",
        dtype={"kab_code": str, "kapanewon_code": str},
        usecols=["kab_code", "kab_kota", "kapanewon_code", "kapanewon"],
    ).drop_duplicates()

    pop = pd.read_csv(RAW / "JogjaPulse" / "home_maids_vs_population_kapanewon.csv")
    pop = pop.rename(columns={"KAB_KOTA": "kab_kota", "KEC_KAPN": "kapanewon"})

    dim = hourly.merge(pop, on=["kab_kota", "kapanewon"], how="left", validate="1:1")
    dim["join_key"] = dim["kab_kota"].map(norm_name) + "|" + dim["kapanewon"].map(norm_name)

    # kapanewon yang punya data UMKM (sumber: file per-kapanewon, baris data saja)
    umkm = pd.read_csv(RAW / "UMKM" / "rekapumkmperkapanewon.csv")
    umkm = umkm[umkm["Kapanewon"].notna() & (umkm["Kapanewon"] != "Total")]
    umkm_keys = set(UMKM_KAB + "|" + umkm["Kapanewon"].map(norm_name))
    dim["has_umkm"] = dim["join_key"].isin(umkm_keys)

    missing = umkm_keys - set(dim["join_key"])
    if missing:
        raise ValueError(f"Kapanewon UMKM tanpa pasangan di JogjaPulse: {sorted(missing)}")
    return dim.sort_values("kapanewon_code").reset_index(drop=True)


def main() -> None:
    dim = build()
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "dim_kapanewon.csv"
    dim.to_csv(path, index=False)
    print(f"{len(dim)} kapanewon, {int(dim.has_umkm.sum())} punya data UMKM -> {path}")


if __name__ == "__main__":
    main()
