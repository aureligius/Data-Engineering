INSTALL spatial;
INSTALL httpfs;

LOAD spatial;
LOAD httpfs;

SET geometry_always_xy = true;
SET s3_region = 'us-west-2';

COPY (
    SELECT
        id AS poi_id,
        names.primary AS name,
        basic_category,
        taxonomy.primary AS taxonomy_primary,
        confidence,
        geometry
    FROM read_parquet(
        's3://overturemaps-us-west-2/release/2026-11-18.0/theme=places/type=place/*',
        filename = true,
        hive_partitioning = true
    )
    WHERE bbox.xmin BETWEEN 109.95 AND 110.95
      AND bbox.ymin BETWEEN -8.25 AND -7.50
)
TO 'data/raw/external/poi/overture_places_diy_2026-11-18.geojson'
WITH (
    FORMAT GDAL,
    DRIVER 'GeoJSON',
    SRS 'EPSG:4326'
);