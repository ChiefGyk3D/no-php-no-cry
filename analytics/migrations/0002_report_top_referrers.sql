-- SPDX-License-Identifier: Apache-2.0
-- Referrer domains are chosen at report time (issue no-php-no-cry#72).
-- The Referer header is forged freely, so no rule at write time can tell a
-- real domain from a forged one, and any cutoff by arrival order lets a
-- requester lock real domains out. Every domain is stored as it arrived. This
-- view lists the 20 referrer domains with the most views per day and class
-- (ties broken by name, never by arrival) and folds every other referrer row
-- into the closed "other" bucket, so no view is dropped. Ranking is per class,
-- so automated rows never push out likely-human domains. A domain counts all
-- its pages together. The k-threshold is unchanged: a bucket under 5 views is
-- not listed, and the folded remainder shows only if it sums to 5 or more.
-- Residual risk, accepted as Low: a requester who sends more views than a real
-- domain can still outrank it; that costs real requests, which the rest of the
-- design already treats as the attacker's budget. The count 20 is the literal
-- below, checked by scripts/test-analytics-sql.py.

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
