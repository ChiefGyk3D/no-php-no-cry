"""Tests for the analytics SQL: schema guard, k-threshold views, rollup and retention.

Usage: python3 -I scripts/test-analytics-sql.py

Runs analytics/migrations/*.sql and analytics/maintenance.sql in an in-memory
SQLite database. The clock is pinned by replacing the literal 'now' in the
maintenance SQL with a fixed timestamp (the test asserts the replacement found
something, so it cannot silently pin nothing).
"""
import re
import sqlite3
import subprocess
import sys
import unittest
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = sorted((ROOT / "analytics" / "migrations").glob("*.sql"))
MAINT = ROOT / "analytics" / "maintenance.sql"
NOW = "2026-11-05 12:00:00"
NOW_EPOCH = 1793880000  # 2026-11-05 12:00:00 UTC, checked in test_clock_constant
HOUR = 3600
DAY = 86400

# Strict allow-list of columns per table: a new column must be added here on purpose.
ALLOWED = {
    "view_events": {"id", "ts", "page", "src_kind", "src", "country", "region", "city", "net", "bot_class"},
    "view_daily": {"day", "page", "src_kind", "src", "country", "bot_class", "views"},
    "view_geo_daily": {"day", "country", "region", "city", "bot_class", "views"},
    "view_dim_daily": {"day", "dim", "value", "bot_class", "views"},
}
# Names that suggest something identifying. Matched on whole underscore-separated words.
FORBIDDEN_WORDS = {
    "ip", "addr", "address", "ua", "agent", "useragent", "referrer", "referer", "url", "query",
    "asn", "cidr", "cookie", "lat", "lon", "latitude", "longitude", "postal", "zip", "fingerprint",
    "hash", "visitor", "uid", "session", "lang", "language", "org", "organization", "uri",
}


def guard(columns_by_table):
    """Returns a list of problems: unknown tables/columns and identifying names."""
    problems = []
    for table, cols in columns_by_table.items():
        if table not in ALLOWED:
            problems.append(f"unexpected table {table}")
            continue
        for c in cols:
            if c not in ALLOWED[table]:
                problems.append(f"{table}.{c} is not on the allow-list")
            if set(c.lower().split("_")) & FORBIDDEN_WORDS:
                problems.append(f"{table}.{c} looks identifying")
    return problems


def tables(db):
    out = {}
    for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"):
        out[name] = [r[1] for r in db.execute(f"PRAGMA table_info({name})")]
    return out


def fresh():
    db = sqlite3.connect(":memory:")
    for m in MIGRATIONS:
        db.executescript(m.read_text())
    return db


def maintenance_sql(now=NOW):
    text = MAINT.read_text()
    n = text.count("'now'")
    assert n >= 8, f"expected the maintenance SQL to use 'now' at least 8 times, found {n}"
    return text.replace("'now'", f"'{now}'")


def event(db, ts, page="/a/", src_kind="d", src="", country="US", region="NY", city="New York", net="unknown", bot="h", n=1):
    for _ in range(n):
        db.execute(
            "INSERT INTO view_events (ts,page,src_kind,src,country,region,city,net,bot_class) VALUES (?,?,?,?,?,?,?,?,?)",
            (ts, page, src_kind, src, country, region, city, net, bot),
        )


def insert_sql():
    """INSERT_SQL from analytics/collect.mjs, read with node (already required by the suite)."""
    code = 'import { INSERT_SQL } from "./analytics/collect.mjs"; process.stdout.write(INSERT_SQL);'
    out = subprocess.run(
        ["node", "--input-type=module", "-e", code], cwd=ROOT, check=True, capture_output=True, text=True
    )
    return out.stdout


class ReferrerCap(unittest.TestCase):
    """Per-hour, per-group admission of new referrer domains.

    Arrival order across the day must not decide who is admitted: every UTC hour
    keeps its own budget of new domains, and automated rows (bot_class not h)
    have a budget of their own, so neither a burst of forged referrers nor a bot
    run can take the capacity of a later hour or of the human group.
    """

    MIDNIGHT = 1762732800  # 2026-11-10 00:00:00 UTC
    PER_HOUR = 5  # HOURLY_NEW_REFERRER_DOMAINS in collect.mjs

    def insert(self, db, ts, domain, bot="h"):
        start = self.MIDNIGHT
        db.execute(insert_sql(), (ts, "/", "r", domain, "", "", "", "unknown", bot, start, start + DAY))

    def test_new_domains_per_hour_are_limited(self):
        db = fresh()
        for i in range(self.PER_HOUR + 3):
            self.insert(db, self.MIDNIGHT, f"domain-{i}.example")
        kinds = dict(db.execute("SELECT src_kind, count(*) FROM view_events GROUP BY src_kind"))
        self.assertEqual(kinds, {"r": self.PER_HOUR, "o": 3})
        self.assertEqual(db.execute("SELECT DISTINCT src FROM view_events WHERE src_kind='o'").fetchone()[0], "other")

    def test_forged_burst_cannot_take_a_later_hours_capacity(self):
        db = fresh()
        for i in range(500):
            self.insert(db, self.MIDNIGHT, f"attacker-{i}.example")
        self.insert(db, self.MIDNIGHT + 5 * HOUR, "legit.example")
        got = db.execute("SELECT src_kind, src FROM view_events WHERE ts = ?", (self.MIDNIGHT + 5 * HOUR,)).fetchall()
        self.assertEqual(got, [("r", "legit.example")])
        distinct = db.execute("SELECT COUNT(DISTINCT src) FROM view_events WHERE src_kind='r'").fetchone()[0]
        self.assertLessEqual(distinct, self.PER_HOUR + 1)

    def test_automated_rows_never_consume_the_human_budget(self):
        db = fresh()
        for i in range(200):
            self.insert(db, self.MIDNIGHT, f"bot-{i}.example", bot="a")
        for i in range(self.PER_HOUR):
            self.insert(db, self.MIDNIGHT, f"human-{i}.example", bot="h")
        humans = db.execute("SELECT COUNT(DISTINCT src) FROM view_events WHERE src_kind='r' AND bot_class='h'").fetchone()[0]
        bots = db.execute("SELECT COUNT(DISTINCT src) FROM view_events WHERE src_kind='r' AND bot_class='a'").fetchone()[0]
        self.assertEqual(humans, self.PER_HOUR)
        self.assertEqual(bots, self.PER_HOUR)

    def test_human_burst_does_not_consume_the_automated_budget(self):
        db = fresh()
        for i in range(50):
            self.insert(db, self.MIDNIGHT, f"h-{i}.example", bot="h")
        self.insert(db, self.MIDNIGHT, "crawler.example", bot="a")
        self.assertEqual(
            db.execute("SELECT src_kind FROM view_events WHERE src = 'crawler.example'").fetchone()[0], "r"
        )

    def test_admitted_domain_stays_admitted_and_real_ts_still_capped(self):
        db = fresh()
        for i in range(self.PER_HOUR):
            self.insert(db, self.MIDNIGHT, f"d{i}.example")
        # Seen earlier the same UTC day: stays admitted even in a full hour.
        for i in range(self.PER_HOUR):
            self.insert(db, self.MIDNIGHT + 3600, f"e{i}.example")
        self.insert(db, self.MIDNIGHT + 3600, "d0.example")
        got = db.execute(
            "SELECT src_kind, src FROM view_events WHERE ts = ? ORDER BY id DESC LIMIT 1", (self.MIDNIGHT + 3600,)
        ).fetchall()
        self.assertEqual(got, [("r", "d0.example")])
        # ts bound as a real number is still capped in its own hour.
        for i in range(self.PER_HOUR):
            self.insert(db, float(self.MIDNIGHT + 12 * HOUR), f"f{i}.example")
        self.insert(db, float(self.MIDNIGHT + 12 * HOUR), "late.example")
        got = db.execute(
            "SELECT src_kind, src FROM view_events WHERE ts = ? ORDER BY id DESC LIMIT 1", (self.MIDNIGHT + 12 * HOUR,)
        ).fetchall()
        self.assertEqual(got, [("o", "other")])

    def test_day_boundary_resets_budget(self):
        db = fresh()
        for i in range(self.PER_HOUR + 2):
            self.insert(db, self.MIDNIGHT + DAY - 3600, f"x{i}.example")
        start = self.MIDNIGHT + DAY
        db.execute(insert_sql(), (start, "/", "r", "next.example", "", "", "", "unknown", "h", start, start + DAY))
        self.assertEqual(
            db.execute("SELECT src_kind FROM view_events WHERE src='next.example'").fetchone()[0], "r"
        )


class Schema(unittest.TestCase):
    def test_collected(self):
        self.assertTrue(MIGRATIONS, "no migration collected")
        self.assertTrue(MAINT.is_file())

    def test_clock_constant(self):
        import calendar
        import time

        self.assertEqual(NOW_EPOCH, calendar.timegm(time.strptime(NOW, "%Y-%m-%d %H:%M:%S")))

    def test_schema_passes_the_guard(self):
        db = fresh()
        t = tables(db)
        self.assertEqual(set(t), set(ALLOWED), "tables differ from the allow-list")
        self.assertEqual(guard(t), [])

    def test_guard_bites(self):
        for col in ("ip", "client_ip", "user_agent", "ua", "referrer_url", "asn", "net_cidr", "cookie_id", "latitude", "postal_code", "visitor_hash", "accept_language"):
            bad = {"view_events": sorted(ALLOWED["view_events"]) + [col]}
            self.assertTrue(guard(bad), f"guard missed a {col} column")
        self.assertTrue(guard({"visitor_seen": ["day", "h"]}), "guard missed an extra table")
        self.assertEqual(guard({"view_events": sorted(ALLOWED["view_events"])}), [])

    def test_ts_must_be_hour_rounded(self):
        db = fresh()
        with self.assertRaises(sqlite3.IntegrityError):
            event(db, NOW_EPOCH + 1)
        event(db, NOW_EPOCH)

    def test_enum_checks(self):
        db = fresh()
        with self.assertRaises(sqlite3.IntegrityError):
            event(db, NOW_EPOCH, net="residential")
        with self.assertRaises(sqlite3.IntegrityError):
            event(db, NOW_EPOCH, bot="s")
        with self.assertRaises(sqlite3.IntegrityError):
            event(db, NOW_EPOCH, src_kind="u")
        with self.assertRaises(sqlite3.IntegrityError):
            event(db, NOW_EPOCH, page="x" * 97)


class Rollup(unittest.TestCase):
    def test_rollup_counts_and_is_idempotent(self):
        db = fresh()
        event(db, NOW_EPOCH, page="/a/", n=3)
        event(db, NOW_EPOCH - HOUR, page="/a/", n=2)
        event(db, NOW_EPOCH, page="/a/", bot="a", n=4)
        event(db, NOW_EPOCH, page="/b/", src_kind="r", src="news.example.org", n=1)
        for _ in range(2):
            db.executescript(maintenance_sql())
        rows = dict(((r[0], r[1], r[2], r[3], r[4], r[5]), r[6]) for r in db.execute("SELECT * FROM view_daily"))
        self.assertEqual(rows[("2026-11-05", "/a/", "d", "", "US", "h")], 5)
        self.assertEqual(rows[("2026-11-05", "/a/", "d", "", "US", "a")], 4)
        self.assertEqual(rows[("2026-11-05", "/b/", "r", "news.example.org", "US", "h")], 1)
        self.assertEqual(db.execute("SELECT SUM(views) FROM view_geo_daily").fetchone()[0], 10)
        self.assertEqual(db.execute("SELECT SUM(views) FROM view_dim_daily").fetchone()[0], 10)

    def test_late_rows_update_the_day(self):
        db = fresh()
        event(db, NOW_EPOCH, n=2)
        db.executescript(maintenance_sql())
        event(db, NOW_EPOCH, n=3)
        db.executescript(maintenance_sql())
        self.assertEqual(db.execute("SELECT views FROM view_daily").fetchall(), [(5,)])

    def test_every_day_in_the_window_is_complete_before_its_raw_rows_go(self):
        # Raw rows live 7 days; the rollup window starts 5 days back at midnight.
        # Run the rollup on each of 8 consecutive days: nothing may be undercounted.
        db = fresh()
        start = NOW_EPOCH - 10 * DAY
        for d in range(11):
            for h in (1, 13):
                event(db, (start // DAY) * DAY + d * DAY + h * HOUR, n=2)
        for d in range(11):
            now = (start // DAY) * DAY + d * DAY + 23 * HOUR
            stamp = sqlite3.connect(":memory:").execute("SELECT datetime(?, 'unixepoch')", (now,)).fetchone()[0]
            db.executescript(maintenance_sql(stamp))
        counts = dict(db.execute("SELECT day, SUM(views) FROM view_daily GROUP BY day").fetchall())
        # days that were rolled while complete keep all 4 views even after their raw rows were purged
        self.assertTrue(counts)
        for day, n in counts.items():
            self.assertEqual(n, 4, f"{day} undercounted: {n}")

    def test_only_the_literal_now_is_used_as_a_clock(self):
        text = MAINT.read_text()
        self.assertNotRegex(text, r"(?i)current_(date|time|timestamp)|julianday|datetime\(\s*'now'\s*,\s*'localtime'")


class Retention(unittest.TestCase):
    def test_raw_7_days_aggregate_90_days(self):
        db = fresh()
        event(db, NOW_EPOCH - 7 * DAY - 2 * HOUR, page="/old/")  # older than 7 days
        event(db, NOW_EPOCH - 6 * DAY, page="/keep/")  # inside
        db.execute("INSERT INTO view_daily VALUES ('2026-08-06','/x/','d','','US','h',9)")  # 91 days
        db.execute("INSERT INTO view_daily VALUES ('2026-08-07','/y/','d','','US','h',9)")  # 90 days: kept
        db.execute("INSERT INTO view_geo_daily VALUES ('2026-08-06','US','NY','NYC','h',9)")
        db.execute("INSERT INTO view_dim_daily VALUES ('2026-08-06','net','unknown','h',9)")
        db.executescript(maintenance_sql())
        self.assertEqual([r[0] for r in db.execute("SELECT page FROM view_events")], ["/keep/"])
        days = {r[0] for r in db.execute("SELECT day FROM view_daily")}
        self.assertNotIn("2026-08-06", days)
        self.assertIn("2026-08-07", days)
        self.assertEqual(db.execute("SELECT COUNT(*) FROM view_geo_daily").fetchone()[0], 0)
        self.assertEqual(db.execute("SELECT COUNT(*) FROM view_dim_daily").fetchone()[0], 0)

    def test_nothing_else_is_deleted(self):
        db = fresh()
        event(db, NOW_EPOCH, n=3)
        db.executescript(maintenance_sql())
        self.assertEqual(db.execute("SELECT COUNT(*) FROM view_events").fetchone()[0], 3)


class KThreshold(unittest.TestCase):
    def setUp(self):
        self.db = fresh()

    def day(self, rows):
        for page, bot, n in rows:
            self.db.execute("INSERT INTO view_daily VALUES ('2026-11-04',?,'d','','US',?,?)", (page, bot, n))

    def shown(self):
        return sorted(self.db.execute("SELECT page, bot_class, views FROM report_view_daily"))

    def test_four_hidden_five_shown(self):
        self.day([("/four/", "h", 4), ("/five/", "h", 5), ("/six/", "h", 6)])
        self.assertEqual(self.shown(), [("/five/", "h", 5), ("/six/", "h", 6)])

    def test_small_buckets_fold_into_other_only_when_the_sum_reaches_five(self):
        self.day([("/a/", "h", 4), ("/b/", "h", 1), ("/c/", "h", 2)])
        self.assertEqual(self.shown(), [("other", "h", 7)])
        self.db.execute("DELETE FROM view_daily")
        self.day([("/a/", "h", 3), ("/b/", "h", 1)])
        self.assertEqual(self.shown(), [], "a remainder of 4 must not be shown")

    def test_single_small_bucket_cannot_be_recovered_by_subtraction(self):
        self.day([("/big/", "h", 10), ("/tiny/", "h", 2)])
        self.assertEqual(self.shown(), [("/big/", "h", 10)])

    def test_bots_are_separate_buckets(self):
        self.day([("/a/", "h", 3), ("/a/", "a", 3)])
        self.assertEqual(self.shown(), [], "3 human plus 3 bot must not add up to a bucket")
        self.db.execute("DELETE FROM view_daily")
        self.day([("/a/", "h", 5), ("/a/", "a", 9)])
        self.assertEqual(self.shown(), [("/a/", "a", 9), ("/a/", "h", 5)])

    def test_funnel_has_no_bots(self):
        self.day([("/a/", "h", 5), ("/a/", "a", 90), ("/b/", "a", 40)])
        self.assertEqual(self.db.execute("SELECT page, views FROM report_funnel_daily").fetchall(), [("/a/", 5)])

    def test_geo_and_dim_views_apply_the_same_floor(self):
        self.db.executescript(
            """
            INSERT INTO view_geo_daily VALUES ('2026-11-04','US','NY','Smalltown','h',4);
            INSERT INTO view_geo_daily VALUES ('2026-11-04','US','NY','New York','h',5);
            INSERT INTO view_dim_daily VALUES ('2026-11-04','net','tor','h',2);
            INSERT INTO view_dim_daily VALUES ('2026-11-04','net','unknown','h',20);
            """
        )
        self.assertEqual(
            self.db.execute("SELECT city, views FROM report_view_geo_daily").fetchall(),
            [("New York", 5)],
        )
        self.assertEqual(
            self.db.execute("SELECT value, views FROM report_view_dim_daily").fetchall(),
            [("unknown", 20)],
        )

    def test_the_threshold_is_five_everywhere(self):
        text = (ROOT / "analytics" / "migrations" / "0001_page_views.sql").read_text()
        text = text[text.index("CREATE VIEW") :]  # the report views only; CHECK (views >= 1) is a table rule
        thresholds = re.findall(r"views\s*(>=|<)\s*(\d+)|SUM\(views\)\s*>=\s*(\d+)", text)
        self.assertGreaterEqual(len(thresholds), 9)
        for a, b, c in thresholds:
            self.assertEqual(b or c, "5")

    def test_end_to_end_report_through_the_rollup(self):
        for i in range(5):
            event(self.db, NOW_EPOCH - i * 0, page="/post/")
        event(self.db, NOW_EPOCH, page="/rare/")
        self.db.executescript(maintenance_sql())
        self.assertEqual(self.shown(), [("/post/", "h", 5)])


if __name__ == "__main__":
    warnings.simplefilter("ignore", ResourceWarning)  # throwaway in-memory databases
    unittest.main(verbosity=1)
