CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS audit;

-- Historical grid-hotspot analysis:
-- - Dec 2021-Feb 2022 only
-- - Daily values are normalized by that day's DIY median published cell presence
-- - Each cell is summarized using a median, not a sum
-- - A cell needs at least 30 published days to be eligible for hotspot classification

CREATE OR REPLACE TABLE mart.daily_cell_relative_activity AS
WITH diy_daily_baseline AS (
    SELECT
        activity_date,
        median(n_maids::DOUBLE) AS diy_median_cell_presence
    FROM staging.presence_cell_daily
    WHERE activity_date BETWEEN DATE '2021-12-01' AND DATE '2022-02-28'
    GROUP BY activity_date
)
SELECT
    p.cell_id,
    p.adm3_pcode,
    p.kab_kota_key,
    p.kapanewon_key,
    p.activity_date,
    p.n_maids::DOUBLE AS cell_presence,
    b.diy_median_cell_presence,
    p.n_maids::DOUBLE / nullif(b.diy_median_cell_presence, 0)
        AS relative_cell_activity_index
FROM mart.presence_cell_daily_assigned p
JOIN diy_daily_baseline b
    USING (activity_date)
WHERE p.activity_date BETWEEN DATE '2021-12-01' AND DATE '2022-02-28';

CREATE OR REPLACE TABLE mart.sleman_cell_hotspots AS
WITH cell_summary AS (
    SELECT
        d.cell_id,
        d.adm3_pcode,
        d.kab_kota_key,
        d.kapanewon_key,

        count(*) AS published_days,
        median(d.cell_presence) AS median_cell_presence,
        median(d.relative_cell_activity_index)
            AS median_relative_cell_activity_index
    FROM mart.daily_cell_relative_activity d
    WHERE d.kab_kota_key = 'SLEMAN'
    GROUP BY 1, 2, 3, 4
),
with_geometry AS (
    SELECT
        s.*,
        c.x_min_utm,
        c.y_min_utm,
        c.centroid_lon,
        c.centroid_lat,

        CASE
            WHEN s.published_days >= 30 THEN true
            ELSE false
        END AS is_hotspot_eligible
    FROM cell_summary s
    JOIN mart.dim_cell c
        USING (cell_id)
),
threshold AS (
    SELECT
        quantile_cont(
            median_relative_cell_activity_index,
            0.90
        ) AS high_activity_threshold
    FROM with_geometry
    WHERE is_hotspot_eligible
)
SELECT
    g.*,
    t.high_activity_threshold,

    CASE
        WHEN NOT g.is_hotspot_eligible
            THEN 'INSUFFICIENT_EVIDENCE'

        WHEN g.median_relative_cell_activity_index
             >= t.high_activity_threshold
            THEN 'HIGH_ACTIVITY_HOTSPOT'

        ELSE 'OTHER_ELIGIBLE_CELL'
    END AS hotspot_class
FROM with_geometry g
CROSS JOIN threshold t;

-- Watch list: the top kapanewon by opportunity_screening_score (stage 07).
-- Hotspots are mapped for the whole watch list, not only the single quadrant
-- "candidate", because the candidate rule is fragile with 17 kapanewon
-- (see docs/project-log.md, section 5.4). is_quadrant_candidate keeps that
-- rule visible.
SET VARIABLE watchlist_size = 3;

CREATE OR REPLACE TABLE mart.sleman_opportunity_watchlist AS
SELECT
    row_number() OVER (
        ORDER BY opportunity_screening_score DESC,
                 mobility_demand_score DESC
    ) AS watchlist_rank,
    adm3_pcode,
    kab_kota_key,
    kapanewon_key,
    kapanewon,
    mobility_demand_score,
    relative_umkm_supply_gap_score,
    opportunity_screening_score,
    opportunity_quadrant,
    opportunity_quadrant = 'HIGH_MOBILITY_LOW_UMKM_SUPPLY'
        AS is_quadrant_candidate
FROM mart.sleman_opportunity_scored
QUALIFY watchlist_rank <= getvariable('watchlist_size')
ORDER BY watchlist_rank;

-- Replaced by mart.sleman_watchlist_cell_hotspots.
DROP TABLE IF EXISTS mart.sleman_candidate_cell_hotspots;

CREATE OR REPLACE TABLE mart.sleman_watchlist_cell_hotspots AS
SELECT
    w.watchlist_rank,
    w.kapanewon,
    h.*,
    w.mobility_demand_score,
    w.opportunity_screening_score,
    w.opportunity_quadrant,
    w.is_quadrant_candidate
FROM mart.sleman_cell_hotspots h
JOIN mart.sleman_opportunity_watchlist w
    USING (adm3_pcode, kab_kota_key, kapanewon_key)
WHERE h.hotspot_class = 'HIGH_ACTIVITY_HOTSPOT'
ORDER BY
    w.watchlist_rank,
    h.median_relative_cell_activity_index DESC;

CREATE OR REPLACE TABLE audit.sleman_cell_hotspot_summary AS
SELECT
    hotspot_class,
    count(*) AS cell_count,
    round(avg(published_days), 1) AS mean_published_days,
    round(
        avg(median_relative_cell_activity_index),
        2
    ) AS mean_relative_activity_index
FROM mart.sleman_cell_hotspots
GROUP BY 1
ORDER BY 1;

CREATE OR REPLACE TABLE audit.sleman_hotspots_by_kapanewon AS
SELECT
    k.kapanewon_source AS kapanewon,
    count(*) AS published_cells,
    count(*) FILTER (
        WHERE h.is_hotspot_eligible
    ) AS eligible_cells,
    count(*) FILTER (
        WHERE h.hotspot_class = 'HIGH_ACTIVITY_HOTSPOT'
    ) AS high_activity_hotspots,
    round(
        max(h.median_relative_cell_activity_index),
        2
    ) AS highest_cell_activity_index
FROM mart.sleman_cell_hotspots h
JOIN staging.dim_kapanewon k
    USING (adm3_pcode, kab_kota_key, kapanewon_key)
GROUP BY 1
ORDER BY high_activity_hotspots DESC, highest_cell_activity_index DESC;