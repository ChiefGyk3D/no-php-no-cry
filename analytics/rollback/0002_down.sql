-- SPDX-License-Identifier: Apache-2.0
-- Rollback for analytics/migrations/0002_report_top_referrers.sql (issue
-- no-php-no-cry#72). NOT a migration: it lives outside migrations/ so wrangler
-- never applies it by itself. Run by hand:
--   wrangler d1 execute <db> --remote --file analytics/rollback/0002_down.sql
-- Restores the two 0001 report views exactly and drops the referrer_seen
-- registry. Every statement tolerates a partial state (a 0002 run that stopped
-- part way), and it can be run twice. The view text below is copied from 0001;
-- scripts/test-analytics-sql.py compares it with 0001 character for character.
-- Inferred, not verified: wrangler records 0002 as applied in d1_migrations, so
-- to apply the file again its row there must be removed first.
-- Collector note: deploy the collector from before 0002 first, or the insert
-- will fail on the missing table (the Function fails open and drops the view).

DROP VIEW IF EXISTS report_funnel_daily;
DROP VIEW IF EXISTS report_view_daily;
DROP INDEX IF EXISTS referrer_seen_n;
DROP TABLE IF EXISTS referrer_seen;

CREATE VIEW report_view_daily AS
SELECT day, page, src_kind, src, country, bot_class, views
FROM view_daily WHERE views >= 5
UNION ALL
SELECT day, 'other', 'o', 'other', '', bot_class, SUM(views)
FROM view_daily WHERE views < 5
GROUP BY day, bot_class HAVING SUM(views) >= 5;

CREATE VIEW report_funnel_daily AS
SELECT day, page, src_kind, src, views
FROM report_view_daily WHERE bot_class = 'h';
