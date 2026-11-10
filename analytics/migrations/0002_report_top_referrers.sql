-- SPDX-License-Identifier: Apache-2.0
-- Referrer domains: a per-day write cap, then a report-time ranking (issue
-- no-php-no-cry#72).
--
-- The Referer header is forged freely, so no rule can tell a real domain from
-- a forged one. Two parts, each with a stated limit:
--
-- 1. Storage is capped at write time. referrer_seen lists the distinct referrer
--    domains admitted per UTC day; the collector admits at most
--    REFERRER_DAILY_CAP of them (analytics/collect.mjs) and stores every later
--    new domain as the existing "other" bucket (src_kind 'o'). That bounds the
--    distinct referrer rows in view_daily (90 days) and the six-day maintenance
--    recompute. The cap is first come: a requester who sends that many forged
--    domains early in a UTC day makes real domains that first appear later that
--    day count as "other" for that day. That costs the requester at least cap
--    requests per day and loses detail, never a view.
-- 2. What is LISTED is chosen at report time. The view below lists the 20
--    referrer domains with the most views per day and class (ties by name,
--    never by arrival) and folds every other referrer row into "other", so no
--    view is dropped. A domain counts all its pages together.
--
-- Residual risk (proposed Low, docs only): class partitioning does not stop a
-- forged domain from being classified likely human, because without Bot
-- Management an ordinary browser User-Agent gets that class. A requester who
-- sends more views than a real domain can therefore outrank it in the listing.
-- It costs real requests (the real domain's count plus one, per forged name).
-- The k-threshold is a display floor: a bucket under 5 views is not listed and
-- the folded remainder shows only if it sums to 5 or more. It is not a bound
-- across reports (see docs/analytics-deploy.md).
--
-- Execution: the Cloudflare docs do not say that wrangler applies a migration
-- file as one transaction, and they say a dump must not contain BEGIN or
-- COMMIT, so this file carries no transaction of its own. It is ordered so the
-- additive statement comes first, the dependent view (funnel) is dropped before
-- the view it reads, and the two replacements are created back to back. If a
-- run stops part way, apply analytics/rollback/0002_down.sql (every statement in
-- it tolerates a partial state) and fix the file. Test the file against a local
-- database first: wrangler d1 migrations apply <db> --local.
-- The count 20 is the literal below, checked by scripts/test-analytics-sql.py.

CREATE TABLE referrer_seen (
  day TEXT NOT NULL,
  src TEXT NOT NULL CHECK (length(src) BETWEEN 1 AND 80),
  n INTEGER NOT NULL CHECK (n >= 1),
  PRIMARY KEY (day, src)
) WITHOUT ROWID;
-- Unique per day: n counts the admitted domains 1, 2, 3 ..., so the largest n
-- of a day is a one-row index read, and two concurrent first requests cannot
-- both take the same slot (the second insert is ignored and it is stored as
-- "other"), so the cap holds exactly.
CREATE UNIQUE INDEX referrer_seen_n ON referrer_seen (day, n);

DROP VIEW report_funnel_daily;
DROP VIEW report_view_daily;

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
