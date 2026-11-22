# Crowds and Commerce

## Mapping Mobility-Based Market Opportunity for UMKM in DIY

### Project type

This project builds a **DIY Mobility-Commerce Data Mart**: a subject-oriented analytical data store for mapping historical mobility-based market opportunity for UMKM across Daerah Istimewa Yogyakarta (DIY).

The analysis covers all 78 DIY kapanewon. It uses historical aggregated mobile-device mobility signals and commercial-location context to identify areas with relatively strong crowd-dependent commercial potential.

This is not an enterprise-wide data warehouse. It does not estimate live or future 2026 demand.

### Research question

Which DIY kapanewon show historical mobility patterns consistent with relatively stronger market opportunity for crowd-dependent UMKM?

### Analysis scope

| Dimension | Scope |
|---|---|
| Study area | All 78 kapanewon across DIY |
| Mobility period | 1 December 2021 to 30 April 2022 |
| Reliable OD period | December 2021 to February 2022 only |
| Spatial resolution | Kapanewon and published 500m × 500m grid cells |
| Commercial context | F&B, retail, markets, and tourism POIs |
| Sleman UMKM role | Supporting sector context and ETL quality-assurance example |
| Intended use | Historical descriptive opportunity mapping |

### Data sources

1. **JogjaPulse mobility data**
   - Daily distinct-device presence by 500m grid cell
   - Hourly distinct-device presence by kapanewon
   - Home-based origin-destination visitation flows
   - Device-to-population ratio by kapanewon

2. **DIY kapanewon boundary polygons**
   - Required to create choropleths.
   - Required to assign 500m grid cells and commercial POIs to kapanewon.

3. **Commercial POIs from OSM or Overture**
   - F&B, retail, markets, and tourism locations.
   - Used as commercial context, not a complete census of businesses.

4. **Sleman UMKM data**
   - `rekapumkmsektorusaha.csv` provides local sector context for the 17 Sleman kapanewon.
   - `rekapdataaset.csv` is used as an ETL quality-assurance example.
   - The Sleman UMKM data is not extrapolated to all DIY.

### Opportunity indicators

- Penetration-adjusted daytime crowd proxy
- Day-to-night crowd ratio
- Weekend-to-weekday crowd surge
- External-origin-normalized OD inflow
- 500m cell-presence concentration
- Commercial-POI density and composition

### Mobility-data rules

- `n_maids` represents distinct observed devices, not people.
- Never sum `n_maids` across cells, hours, dates, or OD destinations.
- A missing/suppressed record means fewer than five devices, not zero.
- Normalize counts within each date before comparing dates because the observed-device sample changes over time.
- Use within-day ratios, daily normalized shares, ranks, and appropriately weighted averages.
- Use `n_pings` only as a device-activity/data-volume measure, not as a people count.
- Restrict OD metrics to December 2021–February 2022 where `reduced_quality = False`.

### UMKM data-quality rules

- Quarantine the blank row in `rekapdataaset.csv`.
- Flag Gamping's labor anomaly.
- Flag Depok's omzet-component mismatch.
- Preserve source values and QA flags; do not silently alter source records.

### Explicit non-claims

This project does not claim to measure:

- Live or future demand
- Actual population or exact visitor totals
- Individual movements
- UMKM revenue or business performance
- Causal effects of mobility on business outcomes
- Complete coverage of informal businesses or commercial POIs

### Planned outputs

1. DIY normalized mobility choropleth
2. DIY commercial-context choropleth
3. DIY mobility-opportunity ranking and map
4. Day-to-night and weekend-surge analysis
5. External OD inflow analysis
6. 500m cell-presence concentration analysis
7. Sleman UMKM ETL QA report
8. Reproducible DuckDB, SQL, and Python pipeline