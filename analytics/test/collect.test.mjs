// Unit tests for analytics/collect.mjs. Run: node --test analytics/test/
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  normalizePath,
  referrerInfo,
  geoFrom,
  netClass,
  botClass,
  shouldCount,
  buildRow,
  hourBucket,
  INSERT_SQL,
  dayWindow,
} from "../collect.mjs";
import { HOSTING_ASNS } from "../hosting-asns.mjs";

const HUMAN_UA =
  "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0";
const here = dirname(fileURLToPath(import.meta.url));

function req(url = "https://blog.example.test/posts/a/", headers = {}, cf) {
  const r = new Request(url, { headers });
  if (cf !== undefined) Object.defineProperty(r, "cf", { value: cf });
  return r;
}
const html = (status = 200) =>
  new Response("<!doctype html>", {
    status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });

test("normalizePath accepts plain Hugo paths and lowercases", () => {
  assert.equal(normalizePath("/"), "/");
  assert.equal(normalizePath("/posts/my-post/"), "/posts/my-post/");
  assert.equal(normalizePath("/Posts/My-Post/"), "/posts/my-post/");
  assert.equal(normalizePath("/about/index.html"), "/about/index.html");
});

test("normalizePath drops hostile paths instead of rewriting them", () => {
  assert.equal(normalizePath("/a%2fb/"), null, "encoded slash");
  assert.equal(normalizePath("/caf%C3%A9/"), null, "any percent escape");
  assert.equal(normalizePath("/a b/"), null);
  assert.equal(normalizePath("/a/b/c/d/e/f/g/"), null, "7 segments");
  assert.equal(normalizePath("/" + "a".repeat(200) + "/"), null, "long");
  assert.equal(normalizePath("/x\u0000y/"), null);
  assert.equal(normalizePath("/<script>/"), null);
  assert.equal(normalizePath(""), null);
  assert.equal(normalizePath(undefined), null);
  assert.equal(normalizePath("no-leading-slash"), null);
});

test("referrerInfo keeps only the registrable domain", () => {
  assert.deepEqual(
    referrerInfo("https://News.Example.ORG/a/b?q=secret#x", "blog.example.test"),
    { kind: "r", host: "example.org" },
  );
  assert.deepEqual(referrerInfo(null, "blog.example.test"), { kind: "d", host: "" });
  assert.deepEqual(referrerInfo("", "blog.example.test"), { kind: "d", host: "" });
  assert.deepEqual(
    referrerInfo("https://blog.example.test/other/", "blog.example.test"),
    { kind: "i", host: "" },
  );
});

test("referrerInfo reduces external hosts to a registrable domain", () => {
  assert.deepEqual(referrerInfo("https://one.two.example.org/path", "blog.example.test"), {
    kind: "r",
    host: "example.org",
  });
  assert.deepEqual(referrerInfo("https://news.example.co.uk/path", "blog.example.test"), {
    kind: "r",
    host: "example.co.uk",
  });
});

function sqlite(input) {
  return new Promise((resolve, reject) => {
    const child = spawn("sqlite3", [":memory:"], { stdio: ["pipe", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (status) => resolve({ status, stdout, stderr }));
    child.stdin.end(input);
  });
}

test("the insert caps distinct referrer domains per UTC day", async () => {
  const migration = readFileSync(join(here, "..", "migrations", "0001_page_views.sql"), "utf8");
  const ts = Date.UTC(2026, 10, 10, 12) / 1000;
  const quote = (value) => `'${String(value).replaceAll("'", "''")}'`;
  const inserts = [];
  for (let i = 0; i < 101; i += 1) {
    const day = dayWindow(ts);
    const values = [ts, "/", "r", `domain-${i}.example`, "", "", "", "unknown", "h", day.start, day.end];
    let sql = INSERT_SQL;
    for (let n = values.length; n >= 1; n -= 1) {
      sql = sql.replaceAll(`?${n}`, typeof values[n - 1] === "number" ? String(values[n - 1]) : quote(values[n - 1]));
    }
    inserts.push(`${sql};`);
  }
  const result = await sqlite(`${migration}\n${inserts.join("\n")}\nSELECT src_kind || ':' || src || ':' || count(*) FROM view_events GROUP BY src_kind, src ORDER BY src;\n`);
  assert.equal(result.status, 0, result.stderr);
  const rows = result.stdout.trim().split("\n");
  assert.equal(rows.filter((line) => line.startsWith("r:")).length, 100);
  assert.ok(rows.includes("o:other:1"));
});

test("the cap holds when the timestamp binds as a real, through real sqlite parameters", async () => {
  const migration = readFileSync(join(here, "..", "migrations", "0001_page_views.sql"), "utf8");
  const midnight = Date.UTC(2026, 10, 10) / 1000;
  const noon = midnight + 12 * 3600;
  const day = dayWindow(noon);
  const insertAt = (ts, tsText, domain) => `
.parameter clear
.parameter set ?1 ${tsText}
.parameter set ?2 '/'
.parameter set ?3 'r'
.parameter set ?4 '${domain}'
.parameter set ?5 ''
.parameter set ?6 ''
.parameter set ?7 ''
.parameter set ?8 'unknown'
.parameter set ?9 'h'
.parameter set ?10 ${day.start}
.parameter set ?11 ${day.end}
${INSERT_SQL};
`;
  let script = migration;
  for (let i = 0; i < 100; i += 1) script += insertAt(midnight, String(midnight), `d${i}.example`);
  // same UTC day, later hour, ts bound as REAL: must still land in the other bucket
  script += insertAt(noon, `${noon}.0`, "late.example");
  script += "SELECT src_kind || ':' || src FROM view_events WHERE ts = " + noon + " ;\n";
  const result = await sqlite(script);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), "o:other");
});

test("dayWindow is whole-second UTC day bounds", () => {
  assert.deepEqual(dayWindow(1762732800), { start: 1762732800, end: 1762819200 });
  assert.deepEqual(dayWindow(1762732800 + 43200), { start: 1762732800, end: 1762819200 });
});

test("referrerInfo handles odd and hostile referrers", () => {
  const site = "blog.example.test";
  for (const bad of [
    "javascript:alert(1)",
    "data:text/html,hi",
    "not a url",
    "ftp://files.example.org/x",
    "//scheme-relative.example.org/",
    "https://",
    "https://" + "a".repeat(5000) + ".example.org/",
    "https://exa mple.org/",
  ]) {
    assert.deepEqual(referrerInfo(bad, site), { kind: "d", host: "" }, bad.slice(0, 40));
  }
  // user info and port never leak into the stored host
  assert.deepEqual(
    referrerInfo("https://user:pw@host.example.org:8443/p", site),
    { kind: "r", host: "example.org" },
  );
  // an IP literal is not stored as a host name
  assert.deepEqual(referrerInfo("http://203.0.113.9/x", site), { kind: "o", host: "other" });
  assert.deepEqual(referrerInfo("http://[2001:db8::1]/x", site), { kind: "o", host: "other" });
  // a huge header is cut before parsing and never throws
  assert.deepEqual(
    referrerInfo("https://ok.example.org/" + "x".repeat(1_000_000), site),
    { kind: "d", host: "" },
  );
});

test("geoFrom tolerates missing and malformed cf", () => {
  const empty = { country: "", region: "", city: "", tor: false };
  assert.deepEqual(geoFrom(undefined, "city"), empty);
  assert.deepEqual(geoFrom(null, "city"), empty);
  assert.deepEqual(geoFrom({}, "city"), empty);
  assert.deepEqual(geoFrom({ country: 5, regionCode: {}, city: [] }, "city"), empty);
  assert.deepEqual(
    geoFrom({ country: "usa", regionCode: "toolong", city: "x".repeat(500) }, "city"),
    empty,
  );
  assert.deepEqual(geoFrom({ city: "Bad<script>" }, "city"), empty);
});

test("geoFrom returns country, region and city and honors the level", () => {
  const cf = { country: "US", regionCode: "NY", city: "New York", latitude: "40.7", postalCode: "10001" };
  assert.deepEqual(geoFrom(cf, "city"), { country: "US", region: "NY", city: "New York", tor: false });
  assert.deepEqual(geoFrom(cf, "region"), { country: "US", region: "NY", city: "", tor: false });
  assert.deepEqual(geoFrom(cf, "country"), { country: "US", region: "", city: "", tor: false });
  assert.deepEqual(geoFrom(cf, "nonsense"), { country: "US", region: "NY", city: "New York", tor: false });
  assert.equal(geoFrom({ city: "Zürich", country: "CH" }, "city").city, "Zürich");
  // T1 is Cloudflare's Tor pseudo-country: not a place
  assert.deepEqual(geoFrom({ country: "T1" }, "city"), { country: "", region: "", city: "", tor: true });
});

test("netClass uses the ASN list and never needs an address", () => {
  assert.ok(HOSTING_ASNS.size > 5, "the ASN list loaded");
  const [asn, kind] = [...HOSTING_ASNS][0];
  assert.equal(netClass({ asn }, false), kind);
  assert.equal(netClass({ asn: String(asn) }, false), kind, "string asn");
  assert.equal(netClass({ asn: 64496 }, false), "unknown");
  assert.equal(netClass({ asn: "abc" }, false), "unknown");
  assert.equal(netClass({ asn: -1 }, false), "unknown");
  assert.equal(netClass({ asn: 1.5 }, false), "unknown");
  assert.equal(netClass(undefined, false), "unknown");
  assert.equal(netClass({}, true), "tor");
});

test("every ASN entry is a valid number with a known class", () => {
  const kinds = new Set(["hosting-datacenter", "vpn-proxy"]);
  for (const [asn, kind] of HOSTING_ASNS) {
    assert.ok(Number.isInteger(asn) && asn > 0 && asn < 4294967296, String(asn));
    assert.ok(kinds.has(kind), kind);
  }
});

test("botClass", () => {
  const h = (o) => new Headers(o);
  assert.equal(botClass(h({ "user-agent": HUMAN_UA }), undefined), "h");
  assert.equal(botClass(h({}), undefined), "a", "no user agent");
  assert.equal(botClass(h({ "user-agent": "Googlebot/2.1 (+http://www.google.com/bot.html)" }), undefined), "a");
  assert.equal(botClass(h({ "user-agent": "curl/8.5.0" }), undefined), "a");
  assert.equal(botClass(h({ "user-agent": "python-requests/2.31" }), undefined), "a");
  assert.equal(botClass(h({ "user-agent": "HeadlessChrome/120" }), undefined), "a");
  assert.equal(botClass(h({ "user-agent": HUMAN_UA, "sec-fetch-mode": "cors" }), undefined), "a");
  assert.equal(botClass(h({ "user-agent": HUMAN_UA, "sec-fetch-mode": "navigate" }), undefined), "h");
  assert.equal(botClass(h({ "user-agent": "x".repeat(100000) }), undefined), "a", "huge UA");
  assert.equal(botClass(h({ "user-agent": HUMAN_UA }), { botManagement: { verifiedBot: true } }), "a");
  assert.equal(botClass(h({ "user-agent": HUMAN_UA }), { botManagement: { score: 3 } }), "a");
  assert.equal(botClass(h({ "user-agent": HUMAN_UA }), { botManagement: { score: 95 } }), "h");
  assert.equal(botClass(h({ "user-agent": HUMAN_UA }), { botManagement: { score: "junk" } }), "h");
  assert.equal(botClass(h({ "user-agent": HUMAN_UA }), { botManagement: "junk" }), "h");
});

test("shouldCount: only a GET answered 200 text/html", () => {
  const ok = req("https://blog.example.test/", { "user-agent": HUMAN_UA });
  assert.equal(shouldCount(ok, html()), true);
  assert.equal(shouldCount(ok, html(404)), false);
  assert.equal(shouldCount(ok, html(301)), false);
  assert.equal(shouldCount(ok, new Response("x", { headers: { "content-type": "image/png" } })), false);
  assert.equal(shouldCount(ok, new Response("x")), false, "no content type");
  assert.equal(shouldCount(new Request("https://blog.example.test/", { method: "HEAD" }), html()), false);
  assert.equal(shouldCount(new Request("https://blog.example.test/", { method: "POST", body: "x" }), html()), false);
});

test("shouldCount: Do Not Track, GPC and prefetch record nothing", () => {
  const u = "https://blog.example.test/";
  assert.equal(shouldCount(req(u, { dnt: "1" }), html()), false);
  assert.equal(shouldCount(req(u, { "sec-gpc": "1" }), html()), false);
  assert.equal(shouldCount(req(u, { "sec-purpose": "prefetch" }), html()), false);
  assert.equal(shouldCount(req(u, { purpose: "prefetch" }), html()), false);
  assert.equal(shouldCount(req(u, { "x-moz": "prefetch" }), html()), false);
  // DNT: 0 and GPC: 0 are an explicit "tracking allowed"
  assert.equal(shouldCount(req(u, { dnt: "0", "sec-gpc": "0" }), html()), true);
  // any other value of an opt-out header is treated as an opt-out, to fail safe
  assert.equal(shouldCount(req(u, { dnt: "yes" }), html()), false);
});

test("hourBucket rounds down to the hour in epoch seconds", () => {
  const t = Date.UTC(2026, 10, 5, 14, 59, 59, 999);
  assert.equal(hourBucket(t), Date.UTC(2026, 10, 5, 14) / 1000);
  assert.equal(hourBucket(t) % 3600, 0);
});

test("buildRow stores only the allowed fields, never the address or user agent", () => {
  const r = req(
    "https://blog.example.test/Posts/A/?utm=1#frag",
    {
      "user-agent": HUMAN_UA,
      referer: "https://social.example.org/user/123?token=abc",
      "cf-connecting-ip": "198.51.100.7",
      "x-forwarded-for": "198.51.100.7",
      "accept-language": "en-US,en;q=0.9",
      cookie: "session=abc",
    },
    {
      country: "US",
      regionCode: "NY",
      city: "New York",
      asn: 14061,
      asOrganization: "Example Org",
      latitude: "1",
      postalCode: "10001",
    },
  );
  const row = buildRow(r, html(), {}, Date.UTC(2026, 10, 5, 14, 30));
  assert.deepEqual(Object.keys(row).sort(), [
    "bot_class",
    "city",
    "country",
    "net",
    "page",
    "region",
    "src",
    "src_kind",
    "ts",
  ]);
  assert.equal(row.page, "/posts/a/");
  assert.equal(row.src_kind, "r");
  assert.equal(row.src, "example.org");
  assert.equal(row.ts % 3600, 0);
  assert.equal(row.bot_class, "h");
  const dump = JSON.stringify(row);
  for (const secret of ["198.51.100.7", "Firefox", "Example Org", "token=abc", "session", "10001", "utm", "123", "en-US"]) {
    assert.ok(!dump.includes(secret), `row must not contain ${secret}`);
  }
});

test("buildRow with no cf, no referrer and no headers still works", () => {
  const row = buildRow(req("https://blog.example.test/"), html(), {}, 0);
  assert.equal(row.country, "");
  assert.equal(row.src_kind, "d");
  assert.equal(row.net, "unknown");
  assert.equal(row.bot_class, "a", "no UA is automated");
});

test("buildRow returns null for hostile paths, opt-outs and non-pages", () => {
  const now = 0;
  assert.equal(buildRow(req("https://blog.example.test/a%2fb/", { "user-agent": HUMAN_UA }), html(), {}, now), null);
  assert.equal(buildRow(req("https://blog.example.test/", { "user-agent": HUMAN_UA, "sec-gpc": "1" }), html(), {}, now), null);
  assert.equal(buildRow(req("https://blog.example.test/", { "user-agent": HUMAN_UA }), html(404), {}, now), null);
});

test("buildRow honors GEO_LEVEL from env", () => {
  const r = req(
    "https://blog.example.test/",
    { "user-agent": HUMAN_UA },
    { country: "US", regionCode: "NY", city: "New York" },
  );
  const row = buildRow(r, html(), { GEO_LEVEL: "country" }, 0);
  assert.equal(row.city, "");
  assert.equal(row.region, "");
  assert.equal(row.country, "US");
});
