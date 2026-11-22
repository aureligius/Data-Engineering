# Batas wilayah kapanewon DIY

`batas_kapanewon_diy.*` adalah shapefile poligon batas kapanewon (kecamatan) se-Daerah Istimewa Yogyakarta.

| | |
|---|---|
| Layer asal | `DIY_34_ADMINISTRASIKEC_AR` (Geoportal Pemerintah DIY) |
| Isi | 78 poligon kapanewon (Gunungkidul 18, Bantul 17, Sleman 17, Kota Yogyakarta 14, Kulon Progo 12) |
| CRS | SRGI2013 UTM zona 49S (EPSG:9489) |
| Dibuat | 2 September 2024 (BAPPEDA DIY) |
| Skala | 1 : 50.000 (KUGI BA03050040, Permendagri 72/2019) |
| Sumber batas | Dokumen RTRW tiap daerah, 2019–2021 (lihat kolom `remark`) |

Kolom yang dipakai: `kdcbps` (kode BPS kapanewon, contoh `34.03.07`, sama dengan `kapanewon_code` di JogjaPulse), `namobj` (nama), `wadmkk` (kabupaten/kota). Kolom lain sebagian besar kosong.

File `.sbn`, `.sbx` (indeks spasial yang bisa dibuat ulang) dan `.shp.xml` (metadata ArcGIS yang memuat path jaringan internal) sengaja dihapus. Shapefile tetap lengkap tanpa file-file itu.

Sumber katalog layer: "Daftar Ketersediaan Data Geospasial DPTR DIY". Cek lisensi/ketentuan penggunaan data Geoportal DIY sebelum redistribusi.
