-- SPDX-License-Identifier: Apache-2.0
-- Release places at the least specific safe level (issue no-php-no-cry#294).
-- This is the confirmed view-only design: view_geo_daily remains a place-only
-- marginal table, and maintenance and its 90-day aggregate retention do not
-- change. A cyber-tier review is required before production enablement.

DROP VIEW report_view_geo_daily;

CREATE VIEW report_view_geo_daily AS
WITH
city_cells AS (
  SELECT day, country, region, city, bot_class, views
  FROM view_geo_daily
),
city_marked AS (
  SELECT c.*,
    SUM(CASE WHEN views < 5 THEN 1 ELSE 0 END) OVER (
      PARTITION BY day, country, region, bot_class
    ) AS withheld_count,
    CASE WHEN views >= 5 AND NOT EXISTS (
      SELECT 1 FROM city_cells smaller
      WHERE smaller.day = c.day AND smaller.country = c.country
        AND smaller.region = c.region AND smaller.bot_class = c.bot_class
        AND smaller.views >= 5
        AND (smaller.views < c.views OR (smaller.views = c.views AND smaller.city < c.city))
    ) THEN 1 ELSE 0 END AS next_smallest
  FROM city_cells c
),
city_classified AS (
  SELECT *,
    (views < 5 OR (withheld_count = 1 AND next_smallest = 1)) AS withheld
  FROM city_marked
),
region_cells AS (
  SELECT day, country, region, bot_class, SUM(views) AS views
  FROM city_classified
  WHERE withheld
  GROUP BY day, country, region, bot_class
),
region_marked AS (
  SELECT r.*,
    SUM(CASE WHEN views < 5 THEN 1 ELSE 0 END) OVER (
      PARTITION BY day, country, bot_class
    ) AS withheld_count,
    CASE WHEN views >= 5 AND NOT EXISTS (
      SELECT 1 FROM region_cells smaller
      WHERE smaller.day = r.day AND smaller.country = r.country
        AND smaller.bot_class = r.bot_class AND smaller.views >= 5
        AND (smaller.views < r.views OR (smaller.views = r.views AND smaller.region < r.region))
    ) THEN 1 ELSE 0 END AS next_smallest
  FROM region_cells r
),
region_classified AS (
  SELECT *,
    (views < 5 OR (withheld_count = 1 AND next_smallest = 1)) AS withheld
  FROM region_marked
),
country_cells AS (
  SELECT day, country, bot_class, SUM(views) AS views
  FROM region_classified
  WHERE withheld
  GROUP BY day, country, bot_class
),
country_marked AS (
  SELECT c.*,
    SUM(CASE WHEN views < 5 THEN 1 ELSE 0 END) OVER (
      PARTITION BY day, bot_class
    ) AS withheld_count,
    CASE WHEN views >= 5 AND NOT EXISTS (
      SELECT 1 FROM country_cells smaller
      WHERE smaller.day = c.day AND smaller.bot_class = c.bot_class
        AND smaller.views >= 5
        AND (smaller.views < c.views OR (smaller.views = c.views AND smaller.country < c.country))
    ) THEN 1 ELSE 0 END AS next_smallest
  FROM country_cells c
),
country_classified AS (
  SELECT *,
    (views < 5 OR (withheld_count = 1 AND next_smallest = 1)) AS withheld
  FROM country_marked
)
SELECT day, country, region, city, bot_class, views
FROM city_classified
WHERE NOT withheld AND views >= 5
UNION ALL
SELECT day, country, region, '', bot_class, views
FROM region_classified
WHERE NOT withheld AND views >= 5
UNION ALL
SELECT day, country, '', '', bot_class, views
FROM country_classified
WHERE NOT withheld AND views >= 5
UNION ALL
SELECT day, 'other', '', '', bot_class, SUM(views)
FROM country_classified
WHERE withheld
GROUP BY day, bot_class
HAVING SUM(views) >= 5;
