# Kapanewon boundaries (DIY)

`kapanewon_boundary_diy.*` is a shapefile of kapanewon (sub-district) polygons for the Special Region of Yogyakarta.

| | |
|---|---|
| Source layer | `DIY_34_ADMINISTRASIKEC_AR` (Geoportal Pemerintah DIY) |
| Content | 78 kapanewon polygons (Gunungkidul 18, Bantul 17, Sleman 17, Yogyakarta City 14, Kulon Progo 12) |
| CRS | SRGI2013 UTM zone 49S (EPSG:9489) |
| Created | 2 September 2024 (BAPPEDA DIY) |
| Scale | 1:50,000 (KUGI BA03050040, Permendagri 72/2019) |
| Boundary basis | Regional spatial plans (RTRW), 2019-2021 (see `remark` column) |

Columns used: `kdcbps` (BPS kapanewon code, e.g. `34.03.07`, same as `kapanewon_code` in JogjaPulse), `namobj` (name), `wadmkk` (regency/city). Most other columns are empty.

Removed on purpose: `.sbn`/`.sbx` (regenerable spatial index) and `.shp.xml` (ArcGIS metadata containing an internal network path). The shapefile is complete without them.

Check the Geoportal DIY terms of use before redistributing.
