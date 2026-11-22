INSTALL spatial;
LOAD spatial;

SET geometry_always_xy = true;

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS audit;

-- 1. Canonical DIY kapanewon dimension from the official DIY Geoportal layer.
-- kdcbps matches JogjaPulse kapanewon_code.
CREATE OR REPLACE TABLE staging.dim_kapanewon AS
WITH boundary_source AS (
    SELECT
        trim(kdcbps) AS kapanewon_code,
        upper(trim(namobj)) AS kapanewon_geoportal,
        upper(trim(wadmkk)) AS kab_kota_geoportal,
        ST_SetCRS(geom, 'EPSG:4326') AS geometry
    FROM ST_Read(
        'data/interim/geo/diy_kapanewon_geoportal.geojson'
    )
),
jogjapulse_names AS (
    SELECT DISTINCT
        trim(cast(kab_code AS VARCHAR)) AS kab_code,
        trim(cast(kapanewon_code AS VARCHAR)) AS kapanewon_code,
        upper(trim(kab_kota)) AS kab_kota_source,
        upper(trim(kapanewon)) AS kapanewon_source
    FROM read_csv_auto(
        'data/raw/JogjaPulse/presence_kapanewon_hourly.csv',
        header = true
    )
)
SELECT
    'ID34' AS adm1_pcode,

    concat(
        'ID',
        split_part(b.kapanewon_code, '.', 1),
        split_part(b.kapanewon_code, '.', 2)
    ) AS adm2_pcode,

    concat(
        'ID',
        replace(b.kapanewon_code, '.', '')
    ) AS adm3_pcode,

    'DAERAH ISTIMEWA YOGYAKARTA' AS provinsi,
    j.kab_kota_source,
    j.kapanewon_source,

    CASE
        WHEN j.kab_kota_source = 'GUNUNG KIDUL' THEN 'GUNUNGKIDUL'
        WHEN j.kab_kota_source = 'KOTA YOGYAKARTA' THEN 'YOGYAKARTA'
        ELSE regexp_replace(
            j.kab_kota_source,
            '[^A-Z0-9]',
            '',
            'g'
        )
    END AS kab_kota_key,

    regexp_replace(
        j.kapanewon_source,
        '[^A-Z0-9]',
        '',
        'g'
    ) AS kapanewon_key,

    b.kapanewon_code,
    b.kapanewon_geoportal,
    b.kab_kota_geoportal,

    ST_Area(
        ST_Transform(
            b.geometry,
            'EPSG:4326',
            'EPSG:32749'
        )
    ) / 1000000.0 AS area_sqkm,

    b.geometry
FROM boundary_source b
JOIN jogjapulse_names j
    USING (kapanewon_code);

-- 2. Hourly DIY mobility.
CREATE OR REPLACE TABLE staging.presence_kapanewon_hourly AS
SELECT
    try_cast(kab_code AS VARCHAR) AS kab_code,
    upper(trim(kab_kota)) AS kab_kota_source,
    upper(trim(kapanewon)) AS kapanewon_source,

    CASE
        WHEN upper(trim(kab_kota)) = 'GUNUNG KIDUL' THEN 'GUNUNGKIDUL'
        WHEN upper(trim(kab_kota)) = 'KOTA YOGYAKARTA' THEN 'YOGYAKARTA'
        ELSE regexp_replace(upper(trim(kab_kota)), '[^A-Z0-9]', '', 'g')
    END AS kab_kota_key,

    regexp_replace(upper(trim(kapanewon)), '[^A-Z0-9]', '', 'g')
        AS kapanewon_key,

    try_cast(kapanewon_code AS VARCHAR) AS kapanewon_code,
    try_cast(date AS DATE) AS activity_date,
    try_cast(hour AS INTEGER) AS hour,
    try_cast(n_maids AS BIGINT) AS n_maids,
    try_cast(n_pings AS BIGINT) AS n_pings
FROM read_csv_auto(
    'data/raw/JogjaPulse/presence_kapanewon_hourly.csv',
    header = true
);

-- 3. Daily 500m-cell mobility.
CREATE OR REPLACE TABLE staging.presence_cell_daily AS
SELECT
    cell_id,
    try_cast(x_min_utm AS DOUBLE) AS x_min_utm,
    try_cast(y_min_utm AS DOUBLE) AS y_min_utm,
    try_cast(centroid_lon AS DOUBLE) AS centroid_lon,
    try_cast(centroid_lat AS DOUBLE) AS centroid_lat,
    try_cast(date AS DATE) AS activity_date,
    try_cast(n_maids AS BIGINT) AS n_maids,
    ST_SetCRS(
        ST_Point(
            try_cast(centroid_lon AS DOUBLE),
            try_cast(centroid_lat AS DOUBLE)
        ),
        'EPSG:4326'
    ) AS centroid_geometry
FROM read_csv_auto(
    'data/raw/JogjaPulse/presence_cell500m_daily.csv',
    header = true
);

-- 4. Penetration ratios. Keep the raw ratio for later caveated use.
CREATE OR REPLACE TABLE staging.home_penetration AS
SELECT
    upper(trim(KAB_KOTA)) AS kab_kota_source,
    upper(trim(KEC_KAPN)) AS kapanewon_source,

    CASE
        WHEN upper(trim(KAB_KOTA)) = 'GUNUNG KIDUL' THEN 'GUNUNGKIDUL'
        WHEN upper(trim(KAB_KOTA)) = 'KOTA YOGYAKARTA' THEN 'YOGYAKARTA'
        ELSE regexp_replace(upper(trim(KAB_KOTA)), '[^A-Z0-9]', '', 'g')
    END AS kab_kota_key,

    regexp_replace(upper(trim(KEC_KAPN)), '[^A-Z0-9]', '', 'g')
        AS kapanewon_key,

    try_cast(n_users AS BIGINT) AS n_users,
    try_cast(pop_actual AS DOUBLE) AS population,
    try_cast(ratio AS DOUBLE) AS device_population_ratio
FROM read_csv_auto(
    'data/raw/JogjaPulse/home_maids_vs_population_kapanewon.csv',
    header = true
);

-- 5. Monthly home-to-destination flows.
CREATE OR REPLACE TABLE staging.od_home_visits AS
SELECT
    month,
    try_cast(origin_kab_code AS VARCHAR) AS origin_kab_code,
    upper(trim(origin_kab_kota)) AS origin_kab_kota,
    try_cast(origin_code AS VARCHAR) AS origin_kapanewon_code,
    upper(trim(origin_kapanewon)) AS origin_kapanewon,

    try_cast(dest_kab_code AS VARCHAR) AS dest_kab_code,
    upper(trim(dest_kab_kota)) AS dest_kab_kota,
    try_cast(dest_code AS VARCHAR) AS dest_kapanewon_code,
    upper(trim(dest_kapanewon)) AS dest_kapanewon,

    try_cast(n_maids AS BIGINT) AS n_maids,
    try_cast(reduced_quality AS BOOLEAN) AS reduced_quality
FROM read_csv_auto(
    'data/raw/JogjaPulse/od_home_visits_kapanewon_monthly.csv',
    header = true
);

-- 6. OD denominators.
CREATE OR REPLACE TABLE staging.od_origin_homes AS
SELECT
    month,
    try_cast(origin_kab_code AS VARCHAR) AS origin_kab_code,
    upper(trim(origin_kab_kota)) AS origin_kab_kota,
    try_cast(origin_code AS VARCHAR) AS origin_kapanewon_code,
    upper(trim(origin_kapanewon)) AS origin_kapanewon,
    try_cast(n_homed_maids AS BIGINT) AS n_homed_maids,
    try_cast(n_homed_maids_daytime AS BIGINT) AS n_homed_maids_daytime,
    try_cast(reduced_quality AS BOOLEAN) AS reduced_quality
FROM read_csv_auto(
    'data/raw/JogjaPulse/od_origin_homes_monthly.csv',
    header = true
);

-- 7. Broad-bounding-box Overture POIs.
-- Spatially clipping POIs to DIY occurs in Step 5.
CREATE OR REPLACE TABLE staging.poi_overture_raw AS
SELECT
    poi_id,
    nullif(trim(name), '') AS name,
    nullif(trim(basic_category), '') AS basic_category,
    nullif(trim(taxonomy_primary), '') AS taxonomy_primary,
    try_cast(confidence AS DOUBLE) AS confidence,
    ST_SetCRS(geom, 'EPSG:4326') AS geometry
FROM ST_Read(
    'data/raw/external/poi/overture_places_diy_2026-11-18.geojson'
);

-- 8. Sleman UMKM source staging.
-- These remain supporting context, not DIY-wide counts.
CREATE OR REPLACE TABLE staging.umkm_sector_sleman_wide AS
SELECT *
FROM read_csv_auto(
    'data/raw/UMKM/rekapumkmsektorusaha.csv',
    header = true
);

CREATE OR REPLACE TABLE staging.umkm_assets_sleman AS
SELECT *
FROM read_csv_auto(
    'data/raw/UMKM/rekapdataaset.csv',
    header = true
);

-- 9. Source inventory.
CREATE OR REPLACE TABLE audit.source_inventory AS
SELECT 'dim_kapanewon' AS dataset, count(*) AS row_count
FROM staging.dim_kapanewon
UNION ALL
SELECT 'presence_kapanewon_hourly', count(*)
FROM staging.presence_kapanewon_hourly
UNION ALL
SELECT 'presence_cell_daily', count(*)
FROM staging.presence_cell_daily
UNION ALL
SELECT 'home_penetration', count(*)
FROM staging.home_penetration
UNION ALL
SELECT 'od_home_visits', count(*)
FROM staging.od_home_visits
UNION ALL
SELECT 'od_origin_homes', count(*)
FROM staging.od_origin_homes
UNION ALL
SELECT 'poi_overture_raw', count(*)
FROM staging.poi_overture_raw
UNION ALL
SELECT 'umkm_sector_sleman_wide', count(*)
FROM staging.umkm_sector_sleman_wide
UNION ALL
SELECT 'umkm_assets_sleman', count(*)
FROM staging.umkm_assets_sleman;

-- 10. Geographic-key coverage check.
CREATE OR REPLACE TABLE audit.kapanewon_coverage AS
WITH mobility AS (
    SELECT DISTINCT kab_kota_key, kapanewon_key
    FROM staging.presence_kapanewon_hourly
),
boundaries AS (
    SELECT DISTINCT kab_kota_key, kapanewon_key
    FROM staging.dim_kapanewon
)
SELECT
    coalesce(m.kab_kota_key, b.kab_kota_key) AS kab_kota_key,
    coalesce(m.kapanewon_key, b.kapanewon_key) AS kapanewon_key,
    m.kapanewon_key IS NOT NULL AS exists_in_mobility,
    b.kapanewon_key IS NOT NULL AS exists_in_boundaries
FROM mobility m
FULL OUTER JOIN boundaries b
    USING (kab_kota_key, kapanewon_key);