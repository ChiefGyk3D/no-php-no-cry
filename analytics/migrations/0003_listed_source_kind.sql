-- SPDX-License-Identifier: Apache-2.0
-- Add the listed-source kind to databases that applied 0001 before `s` was
-- added to its baseline. SQLite cannot alter a CHECK constraint in place, so
-- preserve the rows while rebuilding the two affected tables.

CREATE TABLE view_events_with_listed_source (
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

INSERT INTO view_events_with_listed_source
SELECT * FROM view_events;
DROP TABLE view_events;
ALTER TABLE view_events_with_listed_source RENAME TO view_events;

DROP VIEW report_funnel_daily;
DROP VIEW report_view_daily;

CREATE TABLE view_daily_with_listed_source (
  day TEXT NOT NULL,
  page TEXT NOT NULL,
  src_kind TEXT NOT NULL CHECK (src_kind IN ('d', 'i', 'r', 's', 'o')),
  src TEXT NOT NULL,
  country TEXT NOT NULL,
  bot_class TEXT NOT NULL CHECK (bot_class IN ('h', 'a')),
  views INTEGER NOT NULL CHECK (views >= 1),
  PRIMARY KEY (day, page, src_kind, src, country, bot_class)
) WITHOUT ROWID;

INSERT INTO view_daily_with_listed_source
SELECT * FROM view_daily;
DROP TABLE view_daily;
ALTER TABLE view_daily_with_listed_source RENAME TO view_daily;

CREATE VIEW report_view_daily AS
WITH dom AS (
  SELECT day, bot_class, src,
    ROW_NUMBER() OVER (PARTITION BY day, bot_class ORDER BY SUM(views) DESC, src) AS rn
  FROM view_daily WHERE src_kind = 'r'
  GROUP BY day, bot_class, src
),
kept AS (
  SELECT d.day, d.page, d.src_kind, d.src, d.country, d.bot_class, d.views,
    (d.src_kind <> 'r' OR dom.rn <= 20) AS listed
  FROM view_daily d
  LEFT JOIN dom ON d.src_kind = 'r' AND dom.day = d.day
    AND dom.bot_class = d.bot_class AND dom.src = d.src
)
SELECT day, page, src_kind, src, country, bot_class, views
FROM kept WHERE views >= 5 AND listed
UNION ALL
SELECT day, 'other', 'o', 'other', '', bot_class, SUM(views)
FROM kept WHERE views < 5 OR NOT listed
GROUP BY day, bot_class HAVING SUM(views) >= 5;

CREATE VIEW report_funnel_daily AS
SELECT day, page, src_kind, src, views
FROM report_view_daily WHERE bot_class = 'h';
