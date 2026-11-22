"""Raw data readers (data/raw/). Read-only: no cleaning, no writes.

Each loader returns the file as-is with explicit dtypes (codes as string,
dates as datetime). Cleaning and reshaping belong to a later stage.

Example:
    from src.helpers.loaders import load_all
    data = load_all()
"""
from __future__ import annotations

from pathlib import Path

import geopandas as gpd
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "raw"
JOGJAPULSE = RAW / "JogjaPulse"
UMKM = RAW / "UMKM"
BOUNDARY = RAW / "AdminBoundary" / "kapanewon_boundary_diy.shp"

# Region codes must be strings: "34.01" would otherwise parse as float
_CODE_COLS = {
    "kab_code": "string",
    "kapanewon_code": "string",
    "origin_kab_code": "string",
    "origin_code": "string",
    "dest_kab_code": "string",
    "dest_code": "string",
}


def _read(path: Path, *, parse_dates: list[str] | None = None, dtype: dict | None = None) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")
    return pd.read_csv(path, dtype=dtype, parse_dates=parse_dates or [], encoding="utf-8")


# ---------------------------------------------------------------- JogjaPulse
def load_presence_hourly() -> pd.DataFrame:
    """Devices and pings per kapanewon x date x hour."""
    return _read(JOGJAPULSE / "presence_kapanewon_hourly.csv", parse_dates=["date"], dtype=_CODE_COLS)


def load_presence_cell_daily() -> pd.DataFrame:
    """Devices per 500 m cell x date."""
    return _read(JOGJAPULSE / "presence_cell500m_daily.csv", parse_dates=["date"], dtype={"cell_id": "string"})


def load_od_monthly() -> pd.DataFrame:
    """Monthly origin-destination flows (month x origin x destination)."""
    return _read(JOGJAPULSE / "od_home_visits_kapanewon_monthly.csv", dtype={**_CODE_COLS, "month": "string"})


def load_origin_homes() -> pd.DataFrame:
    """OD denominators: devices homed in each origin kapanewon per month."""
    return _read(JOGJAPULSE / "od_origin_homes_monthly.csv", dtype={**_CODE_COLS, "month": "string"})


def load_home_vs_population() -> pd.DataFrame:
    """Home-estimated devices vs official population (`pop_actual`)."""
    return _read(JOGJAPULSE / "home_maids_vs_population_kapanewon.csv")


def load_night_validation() -> pd.DataFrame:
    """Night-time presence per kapanewon, 2 periods."""
    return _read(JOGJAPULSE / "validation_night_presence_kapanewon.csv")


def load_tier1_summary() -> pd.DataFrame:
    """Suppression stats for the presence products."""
    return _read(JOGJAPULSE / "tier1_summary.csv")


def load_od_summary() -> pd.DataFrame:
    """Suppression stats for the OD product."""
    return _read(JOGJAPULSE / "od_summary.csv")


# ---------------------------------------------------------------- UMKM
# Read as-is, incl. 'Jumlah'/'Total' and blank-name rows (checked during EDA).
def load_umkm_per_kapanewon() -> pd.DataFrame:
    """Business count per kapanewon x scale."""
    return _read(UMKM / "rekapumkmperkapanewon.csv")


def load_umkm_asset() -> pd.DataFrame:
    """Labor, assets, turnover and counts per kapanewon."""
    return _read(UMKM / "rekapdataaset.csv")


def load_umkm_sector_by_kapanewon() -> pd.DataFrame:
    """Business count per sector (rows) x kapanewon (columns, wide)."""
    return _read(UMKM / "rekapumkmsektorusaha.csv")


def load_umkm_sector_by_scale() -> pd.DataFrame:
    """Business count per sector x scale."""
    return _read(UMKM / "rekapdataskalaumkm.csv")


# ---------------------------------------------------------------- Boundary
def load_boundary() -> gpd.GeoDataFrame:
    """78 kapanewon polygons in the native CRS (SRGI2013 UTM 49S, EPSG:9489)."""
    if not BOUNDARY.exists():
        raise FileNotFoundError(f"Shapefile not found: {BOUNDARY}")
    return gpd.read_file(BOUNDARY, engine="pyogrio")


# ---------------------------------------------------------------- All
def load_all() -> dict[str, pd.DataFrame | gpd.GeoDataFrame]:
    """Load every raw dataset into a {name: DataFrame} dict."""
    return {
        "presence_hourly": load_presence_hourly(),
        "presence_cell_daily": load_presence_cell_daily(),
        "od_monthly": load_od_monthly(),
        "origin_homes": load_origin_homes(),
        "home_vs_pop": load_home_vs_population(),
        "night_validation": load_night_validation(),
        "tier1_summary": load_tier1_summary(),
        "od_summary": load_od_summary(),
        "umkm_per_kapanewon": load_umkm_per_kapanewon(),
        "umkm_asset": load_umkm_asset(),
        "umkm_sector_by_kapanewon": load_umkm_sector_by_kapanewon(),
        "umkm_sector_by_scale": load_umkm_sector_by_scale(),
        "boundary": load_boundary(),
    }
