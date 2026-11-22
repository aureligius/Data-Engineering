CREATE SCHEMA IF NOT EXISTS qa;

CREATE OR REPLACE TABLE qa.umkm_assets_profile AS
WITH typed AS (
    SELECT
        try_cast("No" AS INTEGER) AS source_row_number,
        nullif(trim("Kapanewon"), '') AS kapanewon,

        try_cast("Tenaga Kerja L" AS BIGINT) AS labor_male,
        try_cast("Tenaga Kerja P" AS BIGINT) AS labor_female,

        try_cast("Total Aset (Rp.)" AS BIGINT) AS total_assets_rp,
        try_cast("Total Omset (Rp.)" AS BIGINT) AS stated_omzet_rp,

        try_cast("Omset UMKM Mikro Lv1 (Rp.)" AS BIGINT) AS omzet_micro_1_rp,
        try_cast("Omset UMKM Mikro Lv2 (Rp.)" AS BIGINT) AS omzet_micro_2_rp,
        try_cast("Omset UMKM Mikro Lv3 (Rp.)" AS BIGINT) AS omzet_micro_3_rp,
        try_cast("Omset UMKM Mikro Lv4 (Rp.)" AS BIGINT) AS omzet_micro_4_rp,
        try_cast("Omset UMKM Mikro Lv5 (Rp.)" AS BIGINT) AS omzet_micro_5_rp,
        try_cast("Omset UMKM Kecil (Rp.)" AS BIGINT) AS omzet_small_rp,
        try_cast("Omset UMKM Menengah (Rp.)" AS BIGINT) AS omzet_medium_rp,

        try_cast("Jumlah Mikro Lv1" AS BIGINT) AS micro_1_count,
        try_cast("Jumlah Mikro Lv2" AS BIGINT) AS micro_2_count,
        try_cast("Jumlah Mikro Lv3" AS BIGINT) AS micro_3_count,
        try_cast("Jumlah Mikro Lv4" AS BIGINT) AS micro_4_count,
        try_cast("Jumlah Mikro Lv5" AS BIGINT) AS micro_5_count,
        try_cast("Jumlah Kecil" AS BIGINT) AS small_count,
        try_cast("Jumlah Menengah" AS BIGINT) AS medium_count
    FROM staging.umkm_assets_sleman
),
calculated AS (
    SELECT
        *,
        omzet_micro_1_rp
        + omzet_micro_2_rp
        + omzet_micro_3_rp
        + omzet_micro_4_rp
        + omzet_micro_5_rp
        + omzet_small_rp
        + omzet_medium_rp AS component_omzet_rp,

        labor_female::DOUBLE / nullif(labor_male, 0)
            AS female_to_male_labor_ratio
    FROM typed
)
SELECT
    *,
    stated_omzet_rp - component_omzet_rp AS omzet_component_delta_rp,

    CASE
        WHEN kapanewon IS NULL
            THEN 'QUARANTINED'
        WHEN upper(kapanewon) = 'JUMLAH'
            THEN 'EXCLUDED_AGGREGATE'
        WHEN upper(kapanewon) = 'GAMPING'
             AND female_to_male_labor_ratio > 5
            THEN 'FLAGGED_LABOR_OUTLIER'
        WHEN upper(kapanewon) = 'DEPOK'
             AND abs(stated_omzet_rp - component_omzet_rp) > 1
            THEN 'FLAGGED_OMZET_MISMATCH'
        ELSE 'PASS'
    END AS qa_status
FROM calculated;

CREATE OR REPLACE TABLE qa.umkm_assets_issues AS
SELECT
    source_row_number,
    coalesce(kapanewon, '[blank]') AS kapanewon,
    'QUARANTINE_BLANK_KAPANEWON' AS issue_code,
    'Row has no kapanewon and cannot be spatially assigned.' AS issue_detail
FROM qa.umkm_assets_profile
WHERE kapanewon IS NULL

UNION ALL

SELECT
    source_row_number,
    kapanewon,
    'FLAG_GAMPING_LABOR_OUTLIER' AS issue_code,
    'Female-to-male labor ratio is '
        || round(female_to_male_labor_ratio, 2)::VARCHAR
        || 'x; review source value before use.' AS issue_detail
FROM qa.umkm_assets_profile
WHERE upper(kapanewon) = 'GAMPING'
  AND female_to_male_labor_ratio > 5

UNION ALL

SELECT
    source_row_number,
    kapanewon,
    'FLAG_DEPOK_OMZET_COMPONENT_MISMATCH' AS issue_code,
    'Stated omzet differs from summed omzet components by Rp'
        || omzet_component_delta_rp::VARCHAR
        || '.' AS issue_detail
FROM qa.umkm_assets_profile
WHERE upper(kapanewon) = 'DEPOK'
  AND abs(omzet_component_delta_rp) > 1;

CREATE OR REPLACE TABLE qa.umkm_assets_usable AS
SELECT *
FROM qa.umkm_assets_profile
WHERE qa_status NOT IN ('QUARANTINED', 'EXCLUDED_AGGREGATE');

CREATE OR REPLACE TABLE qa.umkm_qa_summary AS
SELECT
    qa_status,
    count(*) AS row_count
FROM qa.umkm_assets_profile
GROUP BY qa_status
ORDER BY qa_status;