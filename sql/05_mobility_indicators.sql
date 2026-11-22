CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS audit;

-- Analysis window for the daily presence indicators: Dec 2021 - Feb 2022.
-- Mar-Apr 2022 is excluded: the observed-device sample shrinks and shifts by area there
-- (rank correlation with Dec-Feb only 0.48), and published cells per day collapse.
SET VARIABLE analysis_start = DATE '2021-12-01';
SET VARIABLE analysis_end = DATE '2022-02-28';

-- 1. Daily daytime and night-time presence.
-- These are means of published hourly observations, never sums of n_maids.
CREATE OR REPLACE TABLE mart.daily_kapanewon_presence AS
SELECT
    kab_kota_key,
    kapanewon_key,
    activity_date,

    avg(n_maids) FILTER (
        WHERE hour BETWEEN 9 AND 17
    ) AS daytime_presence_mean,

    avg(n_maids) FILTER (
        WHERE hour BETWEEN 0 AND 5
    ) AS nighttime_presence_mean,

    count(*) FILTER (
        WHERE hour BETWEEN 9 AND 17
    ) AS daytime_published_slots,

    count(*) FILTER (
        WHERE hour BETWEEN 0 AND 5
    ) AS nighttime_published_slots
FROM staging.presence_kapanewon_hourly
WHERE activity_date BETWEEN getvariable('analysis_start')
                        AND getvariable('analysis_end')
GROUP BY 1, 2, 3;

-- 2. Penetration-adjusted daily values.
-- The ratio is a representativeness adjustment, not a population estimate.
CREATE OR REPLACE TABLE mart.daily_kapanewon_adjusted AS
SELECT
    d.*,
    p.device_population_ratio,

    d.daytime_presence_mean
        / nullif(p.device_population_ratio, 0)
        AS penetration_adjusted_daytime,

    d.nighttime_presence_mean
        / nullif(p.device_population_ratio, 0)
        AS penetration_adjusted_nighttime,

    d.daytime_presence_mean
        / nullif(d.nighttime_presence_mean, 0)
        AS daily_day_night_ratio
FROM mart.daily_kapanewon_presence d
LEFT JOIN staging.home_penetration p
    USING (kab_kota_key, kapanewon_key);

-- 3. Normalise each date by the median adjusted daytime value
-- across published DIY kapanewon observations on that same date.
--
-- A median is deliberately used rather than a sum: distinct-device counts
-- are not additive across administrative areas.
CREATE OR REPLACE TABLE mart.daily_kapanewon_normalized AS
WITH daily_baseline AS (
    SELECT
        activity_date,
        median(penetration_adjusted_daytime)
            AS diy_daily_median_adjusted_daytime
    FROM mart.daily_kapanewon_adjusted
    WHERE penetration_adjusted_daytime IS NOT NULL
    GROUP BY activity_date
)
SELECT
    d.*,
    b.diy_daily_median_adjusted_daytime,

    d.penetration_adjusted_daytime
        / nullif(b.diy_daily_median_adjusted_daytime, 0)
        AS relative_adjusted_daytime_index,

    CASE
        WHEN dayofweek(d.activity_date) IN (0, 6) THEN 'weekend'
        ELSE 'weekday'
    END AS day_type
FROM mart.daily_kapanewon_adjusted d
JOIN daily_baseline b
    USING (activity_date);

-- 4. External visitor-pressure index.
--
-- This uses December 2021-February 2022 only and excludes reduced-quality OD
-- records. It sums origin-normalised visitation shares, not visitor totals.
CREATE OR REPLACE TABLE mart.external_od_inflow_monthly AS
WITH valid_flows AS (
    SELECT
        o.month,
        regexp_replace(
            upper(trim(o.dest_kab_kota)),
            '[^A-Z0-9]',
            '',
            'g'
        ) AS kab_kota_key,

        regexp_replace(
            upper(trim(o.dest_kapanewon)),
            '[^A-Z0-9]',
            '',
            'g'
        ) AS kapanewon_key,

        o.origin_kab_code,
        o.origin_kapanewon_code,
        o.n_maids,
        d.n_homed_maids_daytime
    FROM staging.od_home_visits o
    JOIN staging.od_origin_homes d
      ON o.month = d.month
     AND o.origin_kapanewon_code = d.origin_kapanewon_code
    WHERE o.month IN ('2021-12', '2022-01', '2022-02')
      AND o.reduced_quality = false
      AND d.reduced_quality = false
      AND upper(trim(o.dest_kab_kota)) <> upper(trim(o.origin_kab_kota))
)
SELECT
    month,
    kab_kota_key,
    kapanewon_key,

    sum(
        n_maids::DOUBLE / nullif(n_homed_maids_daytime, 0)
    ) AS external_origin_normalised_inflow_index,

    count(*) AS published_external_origin_destination_rows,
    count(DISTINCT origin_kapanewon_code) AS external_origins_observed
FROM valid_flows
GROUP BY 1, 2, 3;

-- 5. Cell-presence concentration.
--
-- HHI is a scale-free concentration statistic based on relative published
-- cell-presence weights; it is not interpreted as a total device count.
CREATE OR REPLACE TABLE mart.daily_cell_presence_concentration AS
WITH cell_day_weights AS (
    SELECT
        adm3_pcode,
        kab_kota_key,
        kapanewon_key,
        activity_date,
        n_maids::DOUBLE AS cell_presence
    FROM mart.presence_cell_daily_assigned
    WHERE activity_date BETWEEN getvariable('analysis_start')
                            AND getvariable('analysis_end')
),
daily_concentration AS (
    SELECT
        adm3_pcode,
        kab_kota_key,
        kapanewon_key,
        activity_date,
        count(*) AS published_cells,
        sum(power(cell_presence, 2))
            / nullif(power(sum(cell_presence), 2), 0)
            AS cell_presence_hhi,

        -- Normalised HHI = (HHI - 1/n) / (1 - 1/n), where n = published cells that day.
        -- The raw HHI can never go below 1/n, so it rises whenever suppression removes
        -- cells. Subtracting that floor makes days with different n comparable.
        -- Days with fewer than 3 published cells are left NULL (too few cells to judge).
        CASE
            WHEN count(*) >= 3 THEN
                (
                    sum(power(cell_presence, 2))
                        / nullif(power(sum(cell_presence), 2), 0)
                    - 1.0 / count(*)
                ) / (1.0 - 1.0 / count(*))
        END AS cell_presence_hhi_normalized
    FROM cell_day_weights
    GROUP BY 1, 2, 3, 4
)
SELECT *
FROM daily_concentration;

-- 6. One mobility-indicator record for each DIY kapanewon.
CREATE OR REPLACE TABLE mart.mobility_kapanewon AS
WITH presence_summary AS (
    SELECT
        kab_kota_key,
        kapanewon_key,

        avg(relative_adjusted_daytime_index)
            AS relative_adjusted_daytime_index,

        sum(daytime_presence_mean * daytime_published_slots)
            / nullif(sum(daytime_published_slots), 0)
            AS raw_daytime_presence_mean,

        sum(nighttime_presence_mean * nighttime_published_slots)
            / nullif(sum(nighttime_published_slots), 0)
            AS raw_nighttime_presence_mean,

        (
            sum(daytime_presence_mean * daytime_published_slots)
                / nullif(sum(daytime_published_slots), 0)
        )
        /
        nullif(
            (
                sum(nighttime_presence_mean * nighttime_published_slots)
                    / nullif(sum(nighttime_published_slots), 0)
            ),
            0
        ) AS day_night_ratio,

        avg(relative_adjusted_daytime_index)
            FILTER (WHERE day_type = 'weekend')
            / nullif(
                avg(relative_adjusted_daytime_index)
                    FILTER (WHERE day_type = 'weekday'),
                0
            ) AS weekend_weekday_surge,

        

        

        avg(daytime_published_slots)
            AS mean_daytime_published_slots,

        avg(nighttime_published_slots)
            AS mean_nighttime_published_slots,

        count(*) AS observed_days
    FROM mart.daily_kapanewon_normalized
    GROUP BY 1, 2
),
od_summary AS (
    SELECT
        kab_kota_key,
        kapanewon_key,
        avg(external_origin_normalised_inflow_index)
            AS mean_external_origin_normalised_inflow_index,
        avg(external_origins_observed)
            AS mean_external_origins_observed,
        count(*) AS valid_od_months
    FROM mart.external_od_inflow_monthly
    GROUP BY 1, 2
),
concentration_summary AS (
    SELECT
        kab_kota_key,
        kapanewon_key,
        avg(cell_presence_hhi)
            AS mean_cell_presence_hhi,

        -- Median across days, so a few odd days (for example one-day spikes) do not dominate.
        median(cell_presence_hhi_normalized)
            AS median_cell_presence_hhi_normalized,
        count(cell_presence_hhi_normalized)
            AS usable_concentration_days,

        avg(published_cells)
            AS mean_published_cells_per_day,
        count(*) AS observed_cell_days
    FROM mart.daily_cell_presence_concentration
    GROUP BY 1, 2
)
SELECT
    k.adm1_pcode,
    k.adm2_pcode,
    k.adm3_pcode,
    k.kab_kota_source AS kab_kota,
    k.kapanewon_source AS kapanewon,
    k.kab_kota_key,
    k.kapanewon_key,

    p.relative_adjusted_daytime_index,
    p.day_night_ratio,
    p.weekend_weekday_surge,
    p.raw_daytime_presence_mean,
    p.raw_nighttime_presence_mean,
    p.mean_daytime_published_slots,
    p.mean_nighttime_published_slots,
    p.observed_days,

    o.mean_external_origin_normalised_inflow_index,
    o.mean_external_origins_observed,
    o.valid_od_months,

    c.mean_cell_presence_hhi,
    c.median_cell_presence_hhi_normalized,
    c.usable_concentration_days,
    c.mean_published_cells_per_day,
    c.observed_cell_days
FROM staging.dim_kapanewon k
LEFT JOIN presence_summary p
    USING (kab_kota_key, kapanewon_key)
LEFT JOIN od_summary o
    USING (kab_kota_key, kapanewon_key)
LEFT JOIN concentration_summary c
    USING (kab_kota_key, kapanewon_key);

-- 7. Completeness audit.
CREATE OR REPLACE TABLE audit.mobility_indicator_completeness AS
SELECT
    count(*) AS total_kapanewon,
    count(*) FILTER (
        WHERE relative_adjusted_daytime_index IS NOT NULL
    ) AS kapanewon_with_presence_metric,
    count(*) FILTER (
        WHERE day_night_ratio IS NOT NULL
    ) AS kapanewon_with_day_night_metric,
    count(*) FILTER (
        WHERE weekend_weekday_surge IS NOT NULL
    ) AS kapanewon_with_weekend_metric,
    count(*) FILTER (
        WHERE mean_external_origin_normalised_inflow_index IS NOT NULL
    ) AS kapanewon_with_od_metric,
    count(*) FILTER (
        WHERE mean_cell_presence_hhi IS NOT NULL
    ) AS kapanewon_with_concentration_metric,
    count(*) FILTER (
        WHERE median_cell_presence_hhi_normalized IS NOT NULL
    ) AS kapanewon_with_normalized_concentration_metric
FROM mart.mobility_kapanewon;