-- SPDX-License-Identifier: Apache-2.0
-- Rollback for analytics/migrations/0004_geo_report_floor.sql (issue
-- no-php-no-cry#294). NOT a migration. Run by hand if the report view must be
-- restored. Both statements tolerate a partial migration and repeated runs.

DROP VIEW IF EXISTS report_view_geo_daily;

CREATE VIEW report_view_geo_daily AS
SELECT day, country, region, city, bot_class, views
FROM view_geo_daily WHERE views >= 5
UNION ALL
SELECT day, '', '', 'other', bot_class, SUM(views)
FROM view_geo_daily WHERE views < 5
GROUP BY day, bot_class HAVING SUM(views) >= 5;
