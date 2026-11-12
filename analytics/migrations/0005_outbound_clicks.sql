-- SPDX-License-Identifier: Apache-2.0
-- Outbound clicks by destination eTLD+1. Domain and country stay in separate
-- marginal counters and no URL, path, query, fragment, port, or identifier is
-- represented in this schema.

CREATE TABLE click_events (
  id INTEGER PRIMARY KEY,
  ts INTEGER NOT NULL CHECK (ts % 3600 = 0),
  domain TEXT NOT NULL CHECK (domain = 'other' OR length(domain) BETWEEN 3 AND 63)
);

-- 149 named cells plus the reserved other cell make the 150-cell daily bound.
CREATE TABLE click_domain_seen (
  day TEXT NOT NULL,
  domain TEXT NOT NULL CHECK (domain <> 'other' AND length(domain) BETWEEN 3 AND 63),
  first_hour INTEGER NOT NULL CHECK (first_hour % 3600 = 0),
  n INTEGER NOT NULL CHECK (n BETWEEN 1 AND 149),
  PRIMARY KEY (day, domain),
  UNIQUE (day, n)
) WITHOUT ROWID;

CREATE TABLE click_domain_daily (
  day TEXT NOT NULL,
  domain TEXT NOT NULL,
  clicks INTEGER NOT NULL CHECK (clicks >= 1),
  PRIMARY KEY (day, domain)
) WITHOUT ROWID;

CREATE TABLE click_country_daily (
  day TEXT NOT NULL,
  country TEXT NOT NULL CHECK (length(country) <= 2),
  clicks INTEGER NOT NULL CHECK (clicks >= 1),
  PRIMARY KEY (day, country)
) WITHOUT ROWID;

CREATE TABLE click_domain_monthly (
  month TEXT NOT NULL,
  domain TEXT NOT NULL,
  clicks INTEGER NOT NULL CHECK (clicks >= 1),
  PRIMARY KEY (month, domain)
) WITHOUT ROWID;

CREATE VIEW report_click_domain_daily AS
SELECT day, domain, clicks FROM click_domain_daily WHERE clicks >= 5
UNION ALL
SELECT day, 'other', SUM(clicks) FROM click_domain_daily WHERE clicks < 5
GROUP BY day HAVING SUM(clicks) >= 5;

CREATE VIEW report_click_country_daily AS
SELECT day, country, clicks FROM click_country_daily WHERE clicks >= 5
UNION ALL
SELECT day, 'other', SUM(clicks) FROM click_country_daily WHERE clicks < 5
GROUP BY day HAVING SUM(clicks) >= 5;

CREATE VIEW report_click_domain_monthly AS
SELECT month, domain, clicks FROM click_domain_monthly WHERE clicks >= 5
UNION ALL
SELECT month, 'other', SUM(clicks) FROM click_domain_monthly WHERE clicks < 5
GROUP BY month HAVING SUM(clicks) >= 5;
