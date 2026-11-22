CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS audit;

-- 1. Convert the Sleman UMKM sector table from wide to long format.
-- Only crowd-dependent sectors are used in the opportunity screen.
CREATE OR REPLACE TABLE mart.sleman_umkm_crowd_sectors AS
SELECT
    'SLEMAN' AS kab_kota_key,
    regexp_replace(
        upper(trim(kapanewon_source)),
        '[^A-Z0-9]',
        '',
        'g'
    ) AS kapanewon_key,

    CASE
        WHEN "Sektor Usaha" =
            'Penyediaan Akomodasi dan Makan Minum'
            THEN 'fnb_accommodation'

        WHEN "Sektor Usaha" =
            'Perdagangan Besar dan Eceran, Reparasi Mobil dan Sepeda Motor'
            THEN 'retail_trade'
    END AS sector_group,

    try_cast(umkm_units AS BIGINT) AS umkm_units
FROM (
    UNPIVOT staging.umkm_sector_sleman_wide
    ON
        "Moyudan",
        "Gamping",
        "Sleman",
        "Tempel",
        "Turi",
        "Seyegan",
        "Godean",
        "Mlati",
        "Kalasan",
        "Ngemplak",
        "Cangkringan",
        "Minggir",
        "Depok",
        "Berbah",
        "Prambanan",
        "Ngaglik",
        "Pakem"
    INTO
        NAME kapanewon_source
        VALUE umkm_units
)
WHERE "Sektor Usaha" IN (
    'Penyediaan Akomodasi dan Makan Minum',
    'Perdagangan Besar dan Eceran, Reparasi Mobil dan Sepeda Motor'
);

-- 2. Formal commercial supply for every Sleman kapanewon.
CREATE OR REPLACE TABLE mart.sleman_umkm_supply AS
SELECT
    k.adm1_pcode,
    k.adm2_pcode,
    k.adm3_pcode,
    k.kab_kota_source AS kab_kota,
    k.kapanewon_source AS kapanewon,
    k.kab_kota_key,
    k.kapanewon_key,
    k.area_sqkm,

    coalesce(sum(s.umkm_units) FILTER (
        WHERE s.sector_group = 'fnb_accommodation'
    ), 0) AS fnb_accommodation_umkm,

    coalesce(sum(s.umkm_units) FILTER (
        WHERE s.sector_group = 'retail_trade'
    ), 0) AS retail_trade_umkm,

    coalesce(sum(s.umkm_units), 0) AS crowd_driven_umkm
FROM staging.dim_kapanewon k
LEFT JOIN mart.sleman_umkm_crowd_sectors s
    USING (kab_kota_key, kapanewon_key)
WHERE k.kab_kota_key = 'SLEMAN'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;

-- 3. Join formal UMKM supply to historical mobility indicators.
CREATE OR REPLACE TABLE mart.sleman_mobility_commerce AS
SELECT
    m.adm1_pcode,
    m.adm2_pcode,
    m.adm3_pcode,
    m.kab_kota,
    m.kapanewon,
    m.kab_kota_key,
    m.kapanewon_key,

    m.relative_daytime_index,
    m.relative_adjusted_daytime_index,
    m.penetration_adjustment_flag,
    m.day_night_ratio,
    m.weekend_weekday_surge,
    m.mean_external_origin_normalised_inflow_index,
    m.median_cell_presence_hhi_normalized,
    m.usable_concentration_days,
    m.data_gap_note,

    s.area_sqkm,
    s.fnb_accommodation_umkm,
    s.retail_trade_umkm,
    s.crowd_driven_umkm,

    s.crowd_driven_umkm / nullif(s.area_sqkm, 0)
        AS crowd_driven_umkm_per_sqkm,

    -- POIs remain context only; they are not used in the score.
    m.high_confidence_commercial_pois,
    m.high_confidence_commercial_pois_per_sqkm
FROM mart.diy_mobility_commerce m
JOIN mart.sleman_umkm_supply s
    USING (
        adm1_pcode,
        adm2_pcode,
        adm3_pcode,
        kab_kota_key,
        kapanewon_key
    )
WHERE m.kab_kota_key = 'SLEMAN';

-- 4. Rank only complete Sleman records.
CREATE OR REPLACE TABLE mart.sleman_opportunity_scored AS
WITH eligible AS (
    SELECT
        *,
        percent_rank() OVER (
            ORDER BY relative_daytime_index
        ) AS daytime_activity_percentile,

        percent_rank() OVER (
            ORDER BY day_night_ratio
        ) AS day_night_percentile,

        percent_rank() OVER (
            ORDER BY weekend_weekday_surge
        ) AS weekend_surge_percentile,

        percent_rank() OVER (
            ORDER BY mean_external_origin_normalised_inflow_index
        ) AS external_inflow_percentile,

        percent_rank() OVER (
            ORDER BY median_cell_presence_hhi_normalized
        ) AS crowd_concentration_percentile,

        percent_rank() OVER (
            ORDER BY crowd_driven_umkm_per_sqkm
        ) AS formal_supply_density_percentile
    FROM mart.sleman_mobility_commerce
    WHERE data_gap_note IS NULL
      AND relative_daytime_index IS NOT NULL
      AND day_night_ratio IS NOT NULL
      AND weekend_weekday_surge IS NOT NULL
      AND mean_external_origin_normalised_inflow_index IS NOT NULL
      AND median_cell_presence_hhi_normalized IS NOT NULL
),
scored AS (
    SELECT
        *,
        (
            0.40 * daytime_activity_percentile
            + 0.20 * day_night_percentile
            + 0.15 * weekend_surge_percentile
            + 0.15 * external_inflow_percentile
            + 0.10 * crowd_concentration_percentile
        ) AS mobility_demand_score,

        1.0 - formal_supply_density_percentile
            AS relative_umkm_supply_gap_score
    FROM eligible
),
ranked AS (
    SELECT
        *,
        mobility_demand_score * relative_umkm_supply_gap_score
            AS opportunity_screening_score,

        ntile(4) OVER (
            ORDER BY mobility_demand_score
        ) AS mobility_demand_quartile,

        ntile(4) OVER (
            ORDER BY crowd_driven_umkm_per_sqkm
        ) AS formal_supply_density_quartile
    FROM scored
)
SELECT
    *,
    CASE
        WHEN mobility_demand_quartile = 4
         AND formal_supply_density_quartile = 1
            THEN 'HIGH_MOBILITY_LOW_UMKM_SUPPLY'

        WHEN mobility_demand_quartile = 4
         AND formal_supply_density_quartile >= 3
            THEN 'HIGH_MOBILITY_HIGH_UMKM_SUPPLY'

        WHEN mobility_demand_quartile <= 2
         AND formal_supply_density_quartile = 1
            THEN 'LOW_MOBILITY_LOW_UMKM_SUPPLY'

        WHEN mobility_demand_quartile <= 2
         AND formal_supply_density_quartile >= 3
            THEN 'LOW_MOBILITY_HIGH_UMKM_SUPPLY'

        ELSE 'MIXED_CONTEXT'
    END AS opportunity_quadrant
FROM ranked;

-- 5. Map-ready final mart.
CREATE OR REPLACE TABLE mart.sleman_market_opportunity AS
SELECT
    s.*,
    k.geometry
FROM mart.sleman_opportunity_scored s
JOIN staging.dim_kapanewon k
    USING (
        adm1_pcode,
        adm2_pcode,
        adm3_pcode,
        kab_kota_key,
        kapanewon_key
    );

-- 6. Final candidates for field validation.
CREATE OR REPLACE TABLE mart.sleman_opportunity_candidates AS
SELECT *
FROM mart.sleman_market_opportunity
WHERE opportunity_quadrant = 'HIGH_MOBILITY_LOW_UMKM_SUPPLY'
ORDER BY
    opportunity_screening_score DESC,
    mobility_demand_score DESC;

-- 7. QA summary.
CREATE OR REPLACE TABLE audit.sleman_opportunity_summary AS
SELECT
    opportunity_quadrant,
    count(*) AS kapanewon_count,
    round(avg(mobility_demand_score), 3) AS mean_mobility_score,
    round(avg(crowd_driven_umkm_per_sqkm), 2) AS mean_umkm_per_sqkm
FROM mart.sleman_market_opportunity
GROUP BY 1
ORDER BY 1;