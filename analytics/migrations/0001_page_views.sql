-- SPDX-License-Identifier: Apache-2.0
-- Blog page views (issue no-php-no-cry#84). Derived from Reach Around's
-- worker/migrations/0005 to 0007 (raw table, marginal daily tables, no column
-- for anything that could identify a visitor) and simplified:
--   * ts is rounded to the hour (Reach Around design proposal D-A1)
--   * no unique-visitor hash table: nothing derived from an address is stored
--   * no browser, OS, language or window columns
--   * no site column: this database belongs to the blog alone
--
-- There is deliberately NO column for an address, network or CIDR, user agent,
-- referrer URL, query string, ASN, cookie, coordinates or postal code. What is
-- not stored cannot leak. scripts/test-analytics-sql.py rejects such a column.
-- A new column is a new migration and must pass that test.
--
-- Apply with wrangler at deploy time, never from CI (docs/analytics-deploy.md).

-- One row per counted page view, kept 7 days. No index on purpose: an index is
-- a second row written per view against D1's free write quota, and the daily
-- purge and rollup scan a few days of rows only. INTEGER PRIMARY KEY without
-- AUTOINCREMENT avoids the sqlite_sequence write too.
-- src_kind: d direct, i internal, r referrer host, s listed source, o other.
-- net: from the ASN list in analytics/hosting-asns.mjs; "unknown" means only
-- "no list matched", never "residential".
-- bot_class: h likely human, a automated. Bots are counted, in their own rows
-- of every aggregate, and left out of the funnel (the report views).
CREATE TABLE view_events (
  id INTEGER PRIMARY KEY,
  ts INTEGER NOT NULL CHECK (ts % 3600 = 0),
  page TEXT NOT NULL CHECK (length(page) BETWEEN 1 AND 96),
  src_kind TEXT NOT NULL CHECK (src_kind IN ('d', 'i', 'r', 's', 'o')),
  src TEXT NOT NULL DEFAULT '' CHECK (length(src) <= 80),
  country TEXT NOT NULL DEFAULT '' CHECK (length(country) <= 2),
  region TEXT NOT NULL DEFAULT '' CHECK (length(region) <= 3),
  city TEXT NOT NULL DEFAULT '' CHECK (length(city) <= 60),
  net TEXT NOT NULL DEFAULT 'unknown'
    CHECK (net IN ('unknown', 'hosting-datacenter', 'vpn-proxy', 'tor')),
  bot_class TEXT NOT NULL CHECK (bot_class IN ('h', 'a'))
);

-- Daily aggregates, kept 90 days. Three marginal tables, one kind of fact each,
-- so a day's cities and networks can never be recombined into a profile.
-- Filled by analytics/maintenance.sql. Read only through the report_* views.
CREATE TABLE view_daily (
  day TEXT NOT NULL,
  page TEXT NOT NULL,
  src_kind TEXT NOT NULL CHECK (src_kind IN ('d', 'i', 'r', 's', 'o')),
  src TEXT NOT NULL,
  country TEXT NOT NULL,
  bot_class TEXT NOT NULL CHECK (bot_class IN ('h', 'a')),
  views INTEGER NOT NULL CHECK (views >= 1),
  PRIMARY KEY (day, page, src_kind, src, country, bot_class)
) WITHOUT ROWID;

CREATE TABLE view_geo_daily (
  day TEXT NOT NULL,
  country TEXT NOT NULL,
  region TEXT NOT NULL,
  city TEXT NOT NULL,
  bot_class TEXT NOT NULL CHECK (bot_class IN ('h', 'a')),
  views INTEGER NOT NULL CHECK (views >= 1),
  PRIMARY KEY (day, country, region, city, bot_class)
) WITHOUT ROWID;

CREATE TABLE view_dim_daily (
  day TEXT NOT NULL,
  dim TEXT NOT NULL CHECK (dim IN ('net')),
  value TEXT NOT NULL,
  bot_class TEXT NOT NULL CHECK (bot_class IN ('h', 'a')),
  views INTEGER NOT NULL CHECK (views >= 1),
  PRIMARY KEY (day, dim, value, bot_class)
) WITHOUT ROWID;

-- The k-threshold. Anyone reading numbers (the owner, a dashboard, a script)
-- reads these views, never the tables. A bucket with fewer than 5 views is not
-- shown. The suppressed buckets of one day and class are added together and
-- shown as one "other" row only if that sum is itself at least 5, so a small
-- bucket cannot be recovered by subtraction. Bot rows are separate buckets
-- (bot_class is part of every key), so bots never lift a human bucket over the
-- line. The threshold is the literal 5 in each statement below; the SQL test
-- checks all of them.
CREATE VIEW report_view_daily AS
SELECT day, page, src_kind, src, country, bot_class, views
FROM view_daily WHERE views >= 5
UNION ALL
SELECT day, 'other', 'o', 'other', '', bot_class, SUM(views)
FROM view_daily WHERE views < 5
GROUP BY day, bot_class HAVING SUM(views) >= 5;

CREATE VIEW report_view_geo_daily AS
SELECT day, country, region, city, bot_class, views
FROM view_geo_daily WHERE views >= 5
UNION ALL
SELECT day, '', '', 'other', bot_class, SUM(views)
FROM view_geo_daily WHERE views < 5
GROUP BY day, bot_class HAVING SUM(views) >= 5;

CREATE VIEW report_view_dim_daily AS
SELECT day, dim, value, bot_class, views
FROM view_dim_daily WHERE views >= 5
UNION ALL
SELECT day, dim, 'other', bot_class, SUM(views)
FROM view_dim_daily WHERE views < 5
GROUP BY day, dim, bot_class HAVING SUM(views) >= 5;

-- The funnel: likely-human traffic only, with the same floor. Bots are in the
-- report_* views above as their own bot_class rows and are never in this one.
CREATE VIEW report_funnel_daily AS
SELECT day, page, src_kind, src, views
FROM report_view_daily WHERE bot_class = 'h';
