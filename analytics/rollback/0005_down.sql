-- Roll back outbound-click analytics. Safe to run more than once.
DROP VIEW IF EXISTS report_click_domain_monthly;
DROP VIEW IF EXISTS report_click_country_daily;
DROP VIEW IF EXISTS report_click_domain_daily;
DROP TABLE IF EXISTS click_domain_monthly;
DROP TABLE IF EXISTS click_country_daily;
DROP TABLE IF EXISTS click_domain_daily;
DROP TABLE IF EXISTS click_domain_seen;
DROP TABLE IF EXISTS click_events;
