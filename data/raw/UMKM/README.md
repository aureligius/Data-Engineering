# UMKM (micro, small and medium enterprises) - Sleman

Business recap for the 17 kapanewon of Sleman Regency. Files are kept exactly as received.

| File | Grain | Content |
|---|---|---|
| `rekapumkmperkapanewon.csv` | kapanewon | Business count by scale (Mikro Lv1-5, Kecil, Menengah) |
| `rekapdataaset.csv` | kapanewon | Labor (male/female), assets, turnover (total and by scale), counts by scale |
| `rekapumkmsektorusaha.csv` | sector x kapanewon (wide) | Business count by sector |
| `rekapdataskalaumkm.csv` | sector x scale | Business count by sector and scale |

## Known quirks (found in EDA)

- `Jumlah` / `Total` rows are mixed into the data; drop them before aggregating.
- A row with a blank kapanewon or sector name (`No` = 1) holds unassigned records; do not drop silently.
- Small count differences between files (e.g. Gamping and Berbah Mikro Lv1 off by 1).
- `Total Omset` for Depok and Ngemplak is larger than the sum of per-scale turnover.
- Implausible labor and asset values (e.g. Gamping female labor 62,435 vs male 3,003; Depok assets Rp 6.1 trillion). Treat labor, asset and turnover columns with caution; business counts are the cleaner signal.
- **The reference year is not stated in the files.** Confirm it before comparing with mobility data (Dec 2021 - Apr 2022).
