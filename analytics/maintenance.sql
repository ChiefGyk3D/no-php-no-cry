-- SPDX-License-Identifier: Apache-2.0
-- Scheduled maintenance for the blog page-view database: roll up, then purge.
-- NOT DEPLOYED. Run once a day (see docs/analytics-deploy.md for the two ways
-- to schedule it). Safe to run again at any time: every statement is
-- idempotent.
--
--   rollup   recomputes the last 6 UTC days (today and the 5 before it) from
--            raw rows and overwrites those days' aggregate rows, so late rows
--            and re-runs never double count.
--   purge    raw rows older than 7 days; aggregate rows older than 90 days;
--            referrer registry rows older than 7 days.
--
-- Invariant that makes the rollup safe: raw rows are kept 7 days and the
-- rollup window reaches back 5 days (start of that UTC day), so a day is always
-- rolled up from complete raw rows. A run may be missed for up to 5 days without
-- losing a day; after longer, days that aged out of the window before a run are
-- lost from the aggregates (their raw rows are purged on schedule regardless).
--
-- Every time reference is the literal 'now', so the SQL test can pin the clock.

-- 1. Rollup (UTC day buckets, by the hour-rounded ts).
INSERT INTO view_daily (day, page, src_kind, src, country, bot_class, views)
SELECT date(ts, 'unixepoch'), page, src_kind, src, country, bot_class, COUNT(*)
FROM view_events
WHERE ts >= CAST(strftime('%s', date('now', '-5 days')) AS INTEGER)
GROUP BY 1, 2, 3, 4, 5, 6
ON CONFLICT (day, page, src_kind, src, country, bot_class)
DO UPDATE SET views = excluded.views;

INSERT INTO view_geo_daily (day, country, region, city, bot_class, views)
SELECT date(ts, 'unixepoch'), country, region, city, bot_class, COUNT(*)
FROM view_events
WHERE ts >= CAST(strftime('%s', date('now', '-5 days')) AS INTEGER)
GROUP BY 1, 2, 3, 4, 5
ON CONFLICT (day, country, region, city, bot_class)
DO UPDATE SET views = excluded.views;

INSERT INTO view_dim_daily (day, dim, value, bot_class, views)
SELECT date(ts, 'unixepoch'), 'net', net, bot_class, COUNT(*)
FROM view_events
WHERE ts >= CAST(strftime('%s', date('now', '-5 days')) AS INTEGER)
GROUP BY 1, 2, 3, 4
ON CONFLICT (day, dim, value, bot_class)
DO UPDATE SET views = excluded.views;

INSERT INTO click_domain_daily (day, domain, clicks)
SELECT date(ts, 'unixepoch'), domain, COUNT(*)
FROM click_events
WHERE ts >= CAST(strftime('%s', date('now', '-5 days')) AS INTEGER)
GROUP BY 1, 2
ON CONFLICT (day, domain) DO UPDATE SET clicks = excluded.clicks;

-- Rebuild the current and prior two months from the retained daily cells. This
-- makes retries idempotent and finishes the previous month after its last day.
DELETE FROM click_domain_monthly
WHERE month >= strftime('%Y-%m', date('now', 'start of month', '-2 months'));
INSERT INTO click_domain_monthly (month, domain, clicks)
SELECT substr(day, 1, 7), domain, SUM(clicks)
FROM click_domain_daily
WHERE day >= date('now', 'start of month', '-2 months')
GROUP BY 1, 2;

-- 2. Retention: 7 days raw, 90 days aggregates.
DELETE FROM view_events
WHERE ts < CAST(strftime('%s', 'now', '-7 days') AS INTEGER);

DELETE FROM view_daily WHERE day < date('now', '-90 days');
DELETE FROM view_geo_daily WHERE day < date('now', '-90 days');
DELETE FROM view_dim_daily WHERE day < date('now', '-90 days');
DELETE FROM click_events
WHERE ts < CAST(strftime('%s', 'now', '-7 days') AS INTEGER);
DELETE FROM click_domain_daily WHERE day < date('now', '-90 days');
DELETE FROM click_country_daily WHERE day < date('now', '-90 days');
DELETE FROM click_domain_monthly
WHERE month < strftime('%Y-%m', date('now', 'start of month', '-24 months'));
DELETE FROM click_domain_seen WHERE day < date('now', '-7 days');
-- The per-day referrer registry is only read for the day being written, so it
-- is kept as long as the raw rows.
DELETE FROM referrer_seen WHERE day < date('now', '-7 days');
