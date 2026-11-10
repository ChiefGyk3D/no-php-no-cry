// Unit tests for analytics/collect.mjs. Run: node --test analytics/test/
import test from "node:test";
import assert from "node:assert/strict";
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
  REGISTER_SQL,
  REFERRER_DAILY_CAP,
  insertRow,
} from "../collect.mjs";
import { HOSTING_ASNS } from "../hosting-asns.mjs";

const HUMAN_UA =
  "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0";

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

test("the write path caps distinct referrer domains per day and says so", () => {
  assert.ok(Number.isInteger(REFERRER_DAILY_CAP) && REFERRER_DAILY_CAP >= 100 && REFERRER_DAILY_CAP <= 1000);
  assert.match(INSERT_SQL, /referrer_seen/);
  assert.match(REGISTER_SQL, /< \?3/);
  for (let i = 1; i <= 9; i++) assert.ok(INSERT_SQL.includes(`?${i}`), `insert binds ?${i}`);
});

// A fake D1 binding. run() applies one statement at once and keeps it even if a
// later one fails (the old two-call write path). batch() models D1's contract:
// the statements are one transaction, so a rejection restores the state taken
// before the first one. failOn names a statement (REGISTER_SQL or INSERT_SQL)
// that rejects after the earlier ones in the same call have been applied.
function fakeD1({ failOn = null, cap = REFERRER_DAILY_CAP } = {}) {
  const state = { registry: new Set(), events: [] };
  const apply = (st) => {
    if (st.sql === failOn) throw new Error("D1 timeout");
    if (st.sql === REGISTER_SQL) {
      if (!state.registry.has(st.args[1]) && state.registry.size < cap) state.registry.add(st.args[1]);
    } else if (st.sql === INSERT_SQL) {
      const [, page, kind, src] = st.args;
      const admitted = kind !== "r" || state.registry.has(src);
      state.events.push(admitted ? { page, kind, src } : { page, kind: "o", src: "other" });
    }
  };
  return {
    state,
    prepare: (sql) => ({ bind: (...args) => ({ sql, args, run: async () => apply({ sql, args }) }) }),
    async batch(stmts) {
      const before = { registry: new Set(state.registry), events: [...state.events] };
      try {
        for (const st of stmts) apply(st);
      } catch (err) {
        state.registry = before.registry;
        state.events = before.events;
        throw err;
      }
    },
  };
}

const rowBase = { ts: 3600, page: "/a/", src: "", country: "", region: "", city: "", net: "unknown", bot_class: "h" };

test("insertRow writes a plain row alone and a referrer as one batch, register first", async () => {
  const seen = [];
  const db = {
    prepare: (sql) => ({ bind: (...args) => ({ sql, args, run: async () => seen.push([sql]) }) }),
    batch: async (stmts) => seen.push(stmts.map((s) => s.sql)),
  };
  await insertRow(db, { ...rowBase, src_kind: "d" });
  assert.deepEqual(seen, [[INSERT_SQL]]);
  seen.length = 0;
  let registerArgs;
  db.batch = async (stmts) => {
    registerArgs = stmts[0].args;
    seen.push(stmts.map((s) => s.sql));
  };
  await insertRow(db, { ...rowBase, src_kind: "r", src: "x.example" });
  assert.deepEqual(seen, [[REGISTER_SQL, INSERT_SQL]]);
  assert.deepEqual(registerArgs, [3600, "x.example", REFERRER_DAILY_CAP]);
});

test("a failed event insert leaves no registered domain behind (atomic batch)", async () => {
  const db = fakeD1({ failOn: INSERT_SQL });
  await assert.rejects(insertRow(db, { ...rowBase, src_kind: "r", src: "x.example" }), /D1 timeout/);
  assert.equal(db.state.registry.size, 0, "registry must not stay reserved");
  assert.equal(db.state.events.length, 0);
});

test("negative control: the fake keeps a registration when the two writes are separate calls", async () => {
  const db = fakeD1({ failOn: INSERT_SQL });
  await db.prepare(REGISTER_SQL).bind(3600, "x.example", REFERRER_DAILY_CAP).run();
  await assert.rejects(db.prepare(INSERT_SQL).bind(3600, "/a/", "r", "x.example").run(), /D1 timeout/);
  assert.equal(db.state.registry.size, 1);
});

test("the event value follows the registry result inside the batch (fail closed)", async () => {
  const db = fakeD1({ cap: 1 });
  await insertRow(db, { ...rowBase, src_kind: "r", src: "first.example" });
  await insertRow(db, { ...rowBase, src_kind: "r", src: "second.example" });
  assert.deepEqual(db.state.events.map((e) => [e.kind, e.src]), [["r", "first.example"], ["o", "other"]]);
});

test("referrerInfo knows common multi-label suffixes outside the UK", () => {
  for (const [header, host] of [
    ["https://one.example.co.in/p", "example.co.in"],
    ["https://a.b.example.com.cn/p", "example.com.cn"],
    ["https://x.example.co.kr/p", "example.co.kr"],
    ["https://x.example.co.za/p", "example.co.za"],
    ["https://x.example.com.tr/p", "example.com.tr"],
  ]) {
    assert.deepEqual(referrerInfo(header, "blog.example.test"), { kind: "r", host }, header);
  }
  // Documented limit: a suffix not on the closed list reduces to two labels.
  assert.deepEqual(referrerInfo("https://a.example.unlisted.test/p", "blog.example.test"), {
    kind: "r",
    host: "unlisted.test",
  });
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
