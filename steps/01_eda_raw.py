# %% [markdown]
# # 01 - Raw data EDA
# **Purpose:** inspect `data/raw/` (shape, nulls, ranges, join keys). Nothing is written.
# **Input:** all of `data/raw/`  |  **Output:** none (tables and plots only)
# **Run:** open in VS Code as a notebook (`# %%` cells), or `python steps/01_eda_raw.py`

# %%
import sys
from pathlib import Path

ROOT = Path.cwd() if (Path.cwd() / "src").exists() else Path.cwd().parent
sys.path.insert(0, str(ROOT))

import matplotlib.pyplot as plt
import pandas as pd

from src.helpers.loaders import load_all
from src.helpers.profiling import check_row_counts, numeric_summary, overview, profile

pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 40)
pd.set_option("display.max_rows", 100)

try:  # notebook: rich tables; terminal: plain print
    show = display  # type: ignore[name-defined]  # noqa: F821
except NameError:
    show = print

# %% [markdown]
# ## 1. Load data

# %%
data = load_all()
show(overview(data))

# %% [markdown]
# ## 2. Row counts vs README

# %%
expected = {
    "presence_cell_daily": 183_548,
    "presence_hourly": 230_418,
    "home_vs_pop": 78,
    "night_validation": 156,
    "tier1_summary": 2,
    "od_monthly": 9_894,
    "origin_homes": 390,
    "od_summary": 1,
}
show(check_row_counts(data, expected))

# %% [markdown]
# ## 3. JogjaPulse - hourly presence by kapanewon

# %%
hourly = data["presence_hourly"]
show(profile(hourly))
show(numeric_summary(hourly))
print("date range:", hourly.date.min().date(), "->", hourly.date.max().date(), "| days:", hourly.date.nunique())
print("kapanewon:", hourly.kapanewon_code.nunique(), "| regencies/city:", hourly.kab_kota.nunique())
print("rows with n_pings < n_maids:", int((hourly.n_pings < hourly.n_maids).sum()), "(expected 0)")

# %% [markdown]
# Missing rows are not zeros: they mean fewer than 5 devices (suppression).
# Share of published hour slots per kapanewon (max 151 days x 24 h = 3,624).

# %%
slots = 151 * 24
coverage = (hourly.groupby(["kab_kota", "kapanewon"]).size() / slots * 100).round(1).rename("published_slot_pct")
show(coverage.sort_values().head(15))

# %% [markdown]
# ### Device sample is not constant
# Daily device totals fall sharply: a sample composition change, not lower mobility.
# `n_maids` is not additive across kapanewon, so this is only a rough indicator.

# %%
daily = hourly.groupby(["date", "hour"]).n_maids.sum().groupby("date").mean()
fig, ax = plt.subplots(figsize=(11, 3.5))
daily.plot(ax=ax, lw=1)
ax.set(title="Sample size indicator per day (mean hourly n_maids summed over kapanewon)", xlabel="", ylabel="n_maids")
plt.tight_layout()
plt.show()

# %% [markdown]
# ## 4. JogjaPulse - daily presence by 500 m cell

# %%
cells = data["presence_cell_daily"]
show(profile(cells))
show(numeric_summary(cells))
print("unique cells:", cells.cell_id.nunique(), "| days:", cells.date.nunique())
per_cell_days = cells.groupby("cell_id").date.nunique()
print("days published per cell: median", per_cell_days.median(), "| cells with < 10 days:", int((per_cell_days < 10).sum()))

# %% [markdown]
# ## 5. JogjaPulse - monthly origin-destination flows

# %%
od = data["od_monthly"]
show(profile(od))
show(od.groupby("month").agg(rows=("n_maids", "size"), total_n_maids=("n_maids", "sum"), reduced=("reduced_quality", "first")))
print("intra-kapanewon rows (origin = destination):", round((od.origin_code == od.dest_code).mean() * 100, 1), "%")

oh = data["origin_homes"]
print("\nOD denominators per month:")
show(oh.groupby("month")[["n_homed_maids", "n_homed_maids_daytime"]].sum())

# %% [markdown]
# ## 6. JogjaPulse - population and validation

# %%
show(profile(data["home_vs_pop"]))
show(data["home_vs_pop"].sort_values("ratio", ascending=False).head(5))
show(data["night_validation"].period.value_counts())
show(data["tier1_summary"])
show(data["od_summary"])

# %% [markdown]
# ## 7. UMKM (Sleman)
# Raw as-is. Note the `Jumlah`/`Total` rows and rows with a blank name.

# %%
for name in ["umkm_per_kapanewon", "umkm_asset", "umkm_sector_by_scale"]:
    print(f"\n--- {name}  {data[name].shape}")
    show(data[name])

# %%
print("--- umkm_sector_by_kapanewon", data["umkm_sector_by_kapanewon"].shape)
show(data["umkm_sector_by_kapanewon"])

# %% [markdown]
# ## 8. Boundary (shapefile)

# %%
gdf = data["boundary"]
print("polygons:", len(gdf), "| CRS:", gdf.crs)
print("all valid:", bool(gdf.geometry.is_valid.all()), "| geometry types:", gdf.geom_type.unique().tolist())
cols = ["namobj", "kdcbps", "wadmkk"]
show(gdf[cols].groupby("wadmkk").size().rename("kapanewon"))
show(gdf[cols].head())

# %%
fig, ax = plt.subplots(figsize=(7, 7))
gdf.plot(column="wadmkk", categorical=True, legend=True, edgecolor="white", linewidth=0.4, ax=ax)
ax.set_title("DIY kapanewon boundaries (78 polygons)")
ax.set_axis_off()
plt.tight_layout()
plt.show()

# %% [markdown]
# ## 9. Can the three sources be joined?
# Checks: kapanewon codes (boundary vs JogjaPulse), UMKM names vs JogjaPulse, 500 m cells vs polygons.

# %%
shp_codes = set(gdf.kdcbps)
jp_codes = set(hourly.kapanewon_code.dropna().astype(str))
print("codes only in shapefile:", sorted(shp_codes - jp_codes))
print("codes only in JogjaPulse:", sorted(jp_codes - shp_codes))

umkm = data["umkm_per_kapanewon"]
umkm_names = set(umkm.Kapanewon.dropna().str.upper()) - {"TOTAL"}
sleman_names = set(hourly.loc[hourly.kab_kota == "SLEMAN", "kapanewon"])
print("\nUMKM kapanewon missing in JogjaPulse (Sleman):", sorted(umkm_names - sleman_names))
print("JogjaPulse Sleman kapanewon missing in UMKM:", sorted(sleman_names - umkm_names))

# Kapanewon names are NOT unique (e.g. JETIS exists in Bantul and Yogyakarta): join on code
names = hourly[["kapanewon_code", "kapanewon"]].drop_duplicates()
print("\nduplicated kapanewon names:", sorted(names[names.kapanewon.duplicated(keep=False)].kapanewon.unique()))

# %%
# 500 m cell centroids over the boundary; color = days published.
cell_pts = cells.drop_duplicates("cell_id")[["cell_id", "centroid_lon", "centroid_lat"]].set_index("cell_id")
cell_pts["days_published"] = per_cell_days
fig, ax = plt.subplots(figsize=(8, 7))
gdf.to_crs(4326).boundary.plot(ax=ax, color="grey", linewidth=0.5)
sc = ax.scatter(cell_pts.centroid_lon, cell_pts.centroid_lat, c=cell_pts.days_published, s=2, cmap="viridis")
plt.colorbar(sc, ax=ax, label="days published per cell (max 151)")
ax.set_title("JogjaPulse 500 m cells over kapanewon boundaries")
ax.set_axis_off()
plt.tight_layout()
plt.show()
