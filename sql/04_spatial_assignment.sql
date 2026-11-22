LOAD spatial;

CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS audit;

-- 1. One record per published 500m grid cell.
CREATE OR REPLACE TABLE mart.dim_cell AS
SELECT DISTINCT
    cell_id,
    x_min_utm,
    y_min_utm,
    centroid_lon,
    centroid_lat,
    centroid_geometry
FROM staging.presence_cell_daily;

-- 2. Assign each cell centroid to one DIY kapanewon.
-- ST_Intersects also handles centroids exactly on a boundary.
-- If a rare boundary tie occurs, retain one deterministic candidate.
CREATE OR REPLACE TABLE mart.bridge_cell_kapanewon AS
WITH candidates AS (
    SELECT
        c.cell_id,
        k.adm1_pcode,
        k.adm2_pcode,
        k.adm3_pcode,
        k.kab_kota_key,
        k.kapanewon_key,
        k.kab_kota_source,
        k.kapanewon_source,
        row_number() OVER (
            PARTITION BY c.cell_id
            ORDER BY k.adm3_pcode
        ) AS assignment_rank
    FROM mart.dim_cell c
    JOIN staging.dim_kapanewon k
      ON ST_Intersects(c.centroid_geometry, k.geometry)
)
SELECT
    cell_id,
    adm1_pcode,
    adm2_pcode,
    adm3_pcode,
    kab_kota_key,
    kapanewon_key,
    kab_kota_source,
    kapanewon_source
FROM candidates
WHERE assignment_rank = 1;

-- 3. Attach the spatial assignment to every published cell-day record.
-- n_maids remains a distinct-device observation; it is not aggregated here.
CREATE OR REPLACE TABLE mart.presence_cell_daily_assigned AS
SELECT
    p.cell_id,
    b.adm1_pcode,
    b.adm2_pcode,
    b.adm3_pcode,
    b.kab_kota_key,
    b.kapanewon_key,
    p.activity_date,
    p.n_maids
FROM staging.presence_cell_daily p
JOIN mart.bridge_cell_kapanewon b
  USING (cell_id);

-- 4. Assign Overture POIs to DIY kapanewon polygons.
-- This spatially clips the broad download rectangle to actual DIY.
CREATE OR REPLACE TABLE mart.poi_kapanewon AS
WITH candidates AS (
    SELECT
        p.poi_id,
        p.name,
        p.basic_category,
        p.taxonomy_primary,
        p.confidence,
        k.adm1_pcode,
        k.adm2_pcode,
        k.adm3_pcode,
        k.kab_kota_key,
        k.kapanewon_key,
        k.kab_kota_source,
        k.kapanewon_source,
        row_number() OVER (
            PARTITION BY p.poi_id
            ORDER BY k.adm3_pcode
        ) AS assignment_rank
    FROM staging.poi_overture_raw p
    JOIN staging.dim_kapanewon k
      ON ST_Intersects(p.geometry, k.geometry)
)
SELECT
    poi_id,
    name,
    basic_category,
    taxonomy_primary,
    confidence,
    adm1_pcode,
    adm2_pcode,
    adm3_pcode,
    kab_kota_key,
    kapanewon_key,
    kab_kota_source,
    kapanewon_source
FROM candidates
WHERE assignment_rank = 1;

-- 5. Audit the grid-cell assignment.
CREATE OR REPLACE TABLE audit.cell_assignment_summary AS
SELECT
    (SELECT count(*) FROM mart.dim_cell) AS published_cells,
    (SELECT count(*) FROM mart.bridge_cell_kapanewon) AS assigned_cells,
    (SELECT count(*) FROM mart.dim_cell)
      - (SELECT count(*) FROM mart.bridge_cell_kapanewon)
      AS unassigned_cells,
    (SELECT count(*) FROM mart.presence_cell_daily_assigned)
      AS assigned_cell_day_rows;

-- 6. Audit the POI clip and assignment.
CREATE OR REPLACE TABLE audit.poi_assignment_summary AS
SELECT
    (SELECT count(*) FROM staging.poi_overture_raw) AS bbox_pois,
    (SELECT count(*) FROM mart.poi_kapanewon) AS pois_inside_diy,
    (SELECT count(*) FROM staging.poi_overture_raw)
      - (SELECT count(*) FROM mart.poi_kapanewon)
      AS pois_outside_diy_bbox,
    (SELECT count(DISTINCT poi_id) FROM mart.poi_kapanewon)
      AS unique_pois_inside_diy;