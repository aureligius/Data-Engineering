CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS audit;

-- 1. Classify the Overture Places taxonomy into project categories.
-- Keep the original Overture categories for traceability.
CREATE OR REPLACE TABLE mart.poi_kapanewon_classified AS
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
    kapanewon_source,

        CASE
        -- Market first, so a market is not captured as retail.
        WHEN coalesce(basic_category, '') IN (
            'market',
            'farmers_market'
        )
        OR regexp_matches(
            lower(coalesce(taxonomy_primary, '')),
            '(^|_)(market|farmers_market|marketplace)($|_)'
        )
            THEN 'market'

        -- Food, beverage, and accommodation
        WHEN coalesce(basic_category, '') IN (
            'restaurant',
            'coffee_shop',
            'casual_eatery',
            'food_and_beverage_store',
            'bakery',
            'bar_or_pub',
            'fast_food_restaurant',
            'cafe',
            'hotel',
            'lodging',
            'resort',
            'guest_house'
        )
        OR regexp_matches(
            lower(coalesce(taxonomy_primary, '')),
            'restaurant|cafe|coffee|bakery|food|beverage|hotel|lodging|resort|guest_house'
        )
            THEN 'fnb_accommodation'

        -- Retail and shopping
        WHEN coalesce(basic_category, '') IN (
            'shopping',
            'fashion_and_apparel_store',
            'hardware_home_and_garden_store',
            'department_store',
            'convenience_store',
            'supermarket',
            'grocery_store',
            'pharmacy',
            'book_store',
            'electronics_store'
        )
        OR regexp_matches(
            lower(coalesce(taxonomy_primary, '')),
            'store|shop|retail|supermarket'
        )
            THEN 'retail'

        -- Visitor and leisure destinations
        WHEN coalesce(basic_category, '') IN (
            'tourist_attraction',
            'museum',
            'park',
            'zoo',
            'amusement_park',
            'beach',
            'art_gallery',
            'historical_landmark'
        )
        OR regexp_matches(
            lower(coalesce(taxonomy_primary, '')),
            'tourist|attraction|museum|(^|_)park($|_)|zoo|beach|heritage|monument'
        )
            THEN 'tourism'

        ELSE 'other'
    END AS commercial_group,

    CASE
        WHEN confidence >= 0.70 THEN true
        ELSE false
    END AS is_high_confidence
FROM mart.poi_kapanewon;

-- 2. Full POI profile. This lets you show exactly which categories were used.
CREATE OR REPLACE TABLE audit.poi_category_profile AS
SELECT
    commercial_group,
    is_high_confidence,
    count(*) AS poi_count,
    count(DISTINCT basic_category) AS distinct_basic_categories,
    count(DISTINCT taxonomy_primary) AS distinct_taxonomy_categories
FROM mart.poi_kapanewon_classified
GROUP BY 1, 2
ORDER BY 1, 2 DESC;

-- 3. Commercial context by kapanewon.
-- High-confidence counts are used for the opportunity proxy.
CREATE OR REPLACE TABLE mart.commercial_context_kapanewon AS
SELECT
    adm1_pcode,
    adm2_pcode,
    adm3_pcode,
    kab_kota_source AS kab_kota,
    kapanewon_source AS kapanewon,
    kab_kota_key,
    kapanewon_key,

    count(*) AS all_pois,
    count(*) FILTER (WHERE is_high_confidence) AS high_confidence_pois,

    count(*) FILTER (
        WHERE commercial_group = 'fnb_accommodation'
    ) AS fnb_accommodation_pois,

    count(*) FILTER (
        WHERE commercial_group = 'retail'
    ) AS retail_pois,

    count(*) FILTER (
        WHERE commercial_group = 'market'
    ) AS market_pois,

    count(*) FILTER (
        WHERE commercial_group = 'tourism'
    ) AS tourism_pois,

    count(*) FILTER (
        WHERE commercial_group = 'other'
    ) AS other_pois,

    count(*) FILTER (
        WHERE is_high_confidence
          AND commercial_group IN (
              'fnb_accommodation',
              'retail',
              'market',
              'tourism'
          )
    ) AS high_confidence_commercial_pois
FROM mart.poi_kapanewon_classified
GROUP BY 1, 2, 3, 4, 5, 6, 7;

-- 4. Keep all 78 kapanewon, including any without assigned POIs.
CREATE OR REPLACE TABLE mart.commercial_context_diy AS
SELECT
    k.adm1_pcode,
    k.adm2_pcode,
    k.adm3_pcode,
    k.kab_kota_source AS kab_kota,
    k.kapanewon_source AS kapanewon,
    k.kab_kota_key,
    k.kapanewon_key,
    k.area_sqkm,

    coalesce(c.all_pois, 0) AS all_pois,
    coalesce(c.high_confidence_pois, 0) AS high_confidence_pois,
    coalesce(c.fnb_accommodation_pois, 0) AS fnb_accommodation_pois,
    coalesce(c.retail_pois, 0) AS retail_pois,
    coalesce(c.market_pois, 0) AS market_pois,
    coalesce(c.tourism_pois, 0) AS tourism_pois,
    coalesce(c.other_pois, 0) AS other_pois,
    coalesce(c.high_confidence_commercial_pois, 0)
        AS high_confidence_commercial_pois,

    coalesce(c.high_confidence_commercial_pois, 0)
        / nullif(k.area_sqkm, 0)
        AS high_confidence_commercial_pois_per_sqkm
FROM staging.dim_kapanewon k
LEFT JOIN mart.commercial_context_kapanewon c
    USING (kab_kota_key, kapanewon_key);

-- 5. One DIY-wide table for analysis and map creation.
-- This intentionally does not create a final "opportunity score" yet.
CREATE OR REPLACE TABLE mart.diy_mobility_commerce AS
SELECT
    m.adm1_pcode,
    m.adm2_pcode,
    m.adm3_pcode,
    m.kab_kota,
    m.kapanewon,
    m.kab_kota_key,
    m.kapanewon_key,

    m.relative_adjusted_daytime_index,
    m.day_night_ratio,
    m.weekend_weekday_surge,
    m.mean_external_origin_normalised_inflow_index,
    m.mean_external_origins_observed,
    m.valid_od_months,
    m.mean_cell_presence_hhi,
    m.mean_published_cells_per_day,

    c.area_sqkm,
    c.all_pois,
    c.high_confidence_pois,
    c.fnb_accommodation_pois,
    c.retail_pois,
    c.market_pois,
    c.tourism_pois,
    c.high_confidence_commercial_pois,
    c.high_confidence_commercial_pois_per_sqkm
FROM mart.mobility_kapanewon m
JOIN mart.commercial_context_diy c
    USING (adm1_pcode, adm2_pcode, adm3_pcode, kab_kota_key, kapanewon_key);

-- 6. Completeness audit.
CREATE OR REPLACE TABLE audit.commercial_context_completeness AS
SELECT
    count(*) AS total_kapanewon,
    count(*) FILTER (
        WHERE high_confidence_commercial_pois > 0
    ) AS kapanewon_with_commercial_pois,
    sum(high_confidence_commercial_pois) AS diy_high_confidence_commercial_pois,
    sum(fnb_accommodation_pois) AS diy_fnb_accommodation_pois,
    sum(retail_pois) AS diy_retail_pois,
    sum(market_pois) AS diy_market_pois,
    sum(tourism_pois) AS diy_tourism_pois
FROM mart.diy_mobility_commerce;