// SPDX-License-Identifier: Apache-2.0
//
// Pure functions that turn one served page into at most one closed-category
// row for the view_events table. Nothing here touches the network, a cookie or
// the browser; there is no script on the pages (CSP script-src stays 'self').
//
// What a row holds (see analytics/migrations/0001_page_views.sql):
//   ts        the hour, rounded down (epoch seconds)
//   page      the path of a page the origin answered 200 text/html
//   src_kind  d direct, i internal, r referrer host, o other
//   src       referrer host only (never a path or query)
//   country, region, city   from Cloudflare's request metadata (GEO_LEVEL)
//   net       hosting-datacenter | vpn-proxy | tor | unknown (ASN list only)
//   bot_class h likely human, a automated
//
// Never read, stored, logged or thrown: the visitor's address, the user agent
// string, the language header, the full referrer, the query string, the ASN
// number, the network owner name, coordinates, a postal code. The user agent
// and the ASN are read as locals, reduced to the closed values above, and
// dropped. analytics/test/middleware.test.mjs scans these sources for the
// header names and calls that would break that.
//
// Reused from Reach Around (worker/src/view.ts, botclass.ts, migrations
// 0005 to 0007, docs/analytics-design.md section 3): the row shape, the source
// kinds, the bot classes h and a, the network class names, the path rules of
// 3.2, the hour rounding proposed in 3.3 and the 5-view bucket floor.
// Simplified here on purpose: no unique-visitor hash (so no secret and no
// address is ever hashed), no browser/OS/language/window columns.

import { HOSTING_ASNS } from "./hosting-asns.mjs";

const MAX_PATH = 96;
const MAX_SEGMENTS = 6;
const MAX_REFERER_CHARS = 2048;
const MAX_HOST = 80;
const MAX_UA_CHARS = 512;
const MAX_DAILY_REFERRER_DOMAINS = 100;

// Closed list of common two-label public suffixes. All other valid names use
// their final two labels. KNOWN LIMIT: this is not the full Public Suffix List,
// so a suffix missing here reduces to the suffix itself, which merges unrelated
// sites into one bucket; it never stores more than two labels. The list is
// pinned in source and needs no runtime lookup or network.
const TWO_LABEL_PUBLIC_SUFFIXES = new Set([
  "ac.in", "ac.jp", "ac.nz", "ac.uk", "ac.za", "co.id", "co.il", "co.in",
  "co.jp", "co.kr", "co.nz", "co.th", "co.uk", "co.za", "com.ar", "com.au",
  "com.br", "com.cn", "com.co", "com.hk", "com.mx", "com.my", "com.ng",
  "com.pe", "com.ph", "com.pk", "com.sg", "com.tr", "com.tw", "com.ua",
  "com.vn", "edu.au", "edu.cn", "gov.au", "gov.cn", "gov.in", "gov.uk",
  "net.au", "net.cn", "net.in", "net.nz", "ne.jp", "or.jp", "org.au",
  "org.cn", "org.in", "org.nz", "org.uk", "org.za",
]);

function registrableDomain(host) {
  const labels = host.split(".");
  if (labels.length < 3) return host;
  const suffix = labels.slice(-2).join(".");
  return labels.slice(TWO_LABEL_PUBLIC_SUFFIXES.has(suffix) ? -3 : -2).join(".");
}

/** Epoch seconds of the start of the hour containing `nowMs`. */
export function hourBucket(nowMs) {
  return Math.floor(nowMs / 3_600_000) * 3600;
}

/**
 * Plain Hugo paths only: lower case, [a-z0-9/_.-], at most 96 characters and 6
 * segments. Anything else (a percent escape, a space, a long path) returns null
 * and the view is dropped, never rewritten. Pages with non-ASCII slugs are
 * therefore not counted.
 */
export function normalizePath(pathname) {
  if (typeof pathname !== "string" || pathname.length === 0) return null;
  if (pathname.length > MAX_PATH || pathname[0] !== "/") return null;
  const p = pathname.toLowerCase();
  if (!/^[a-z0-9/_.-]+$/.test(p)) return null;
  const segments = p.split("/").filter(Boolean);
  if (segments.length > MAX_SEGMENTS) return null;
  if (segments.some((s) => s === "." || s === "..")) return null;
  return p;
}

/**
 * Referrer reduced to a host name. Returns { kind, host }: d direct (none or
 * unusable), i internal (same host), r an external host, o an address literal
 * (stored as the word "other", never the address).
 */
export function referrerInfo(header, siteHost) {
  const direct = { kind: "d", host: "" };
  if (typeof header !== "string" || header.length === 0) return direct;
  if (header.length > MAX_REFERER_CHARS) return direct;
  let url;
  try {
    url = new URL(header);
  } catch {
    return direct;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return direct;
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  if (host.length === 0 || host.length > MAX_HOST) return direct;
  if (host === String(siteHost || "").toLowerCase()) return { kind: "i", host: "" };
  if (host.startsWith("[") || /^\d+(\.\d+){3}$/.test(host)) {
    return { kind: "o", host: "other" };
  }
  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/.test(host)) {
    return direct;
  }
  return { kind: "r", host: registrableDomain(host) };
}

/**
 * Country, region code and city from request.cf, each checked against a strict
 * shape; anything else becomes "". level: city (default), region or country.
 * Cloudflare's pseudo-country T1 means Tor (INFERRED from Cloudflare's
 * CF-IPCountry documentation; see docs/analytics-deploy.md): it is reported as
 * tor, not stored as a place.
 */
export function geoFrom(cf, level) {
  const out = { country: "", region: "", city: "", tor: false };
  if (cf === null || typeof cf !== "object") return out;
  if (cf.country === "T1") {
    out.tor = true;
    return out;
  }
  if (typeof cf.country === "string" && /^[A-Z]{2}$/.test(cf.country) && cf.country !== "XX") {
    out.country = cf.country;
  }
  if (level === "country") return out;
  if (typeof cf.regionCode === "string" && /^[A-Z0-9]{1,3}$/.test(cf.regionCode)) {
    out.region = cf.regionCode;
  }
  if (level === "region") return out;
  if (typeof cf.city === "string" && /^[\p{L}\p{M}][\p{L}\p{M}' .-]{0,59}$/u.test(cf.city)) {
    out.city = cf.city;
  }
  return out;
}

/** Network class from the ASN list; the ASN itself is not returned. */
export function netClass(cf, tor) {
  if (tor) return "tor";
  if (cf === null || typeof cf !== "object") return "unknown";
  const asn = Number(cf.asn);
  if (!Number.isInteger(asn) || asn <= 0) return "unknown";
  return HOSTING_ASNS.get(asn) ?? "unknown";
}

const BOT_UA =
  /bot|crawl|spider|slurp|scrap|fetch|headless|phantom|puppeteer|playwright|selenium|curl|wget|python|go-http|java\/|okhttp|libwww|httpclient|axios|node-|php\/|preview|monitor|uptime|pingdom|lighthouse|facebookexternalhit|embedly|archive|feed|reader|validator|check/i;

/**
 * h likely human, a automated. Signals: no or oversized user agent, a known
 * automation word, a Sec-Fetch-Mode other than navigate, and (only when the
 * zone has Bot Management) Cloudflare's own verdict. The user agent is not
 * kept.
 */
export function botClass(headers, cf) {
  const ua = headers.get("user-agent");
  if (typeof ua !== "string" || ua.length === 0 || ua.length > MAX_UA_CHARS) return "a";
  if (BOT_UA.test(ua)) return "a";
  const mode = headers.get("sec-fetch-mode");
  if (mode !== null && mode.toLowerCase() !== "navigate") return "a";
  const bm = cf !== null && typeof cf === "object" ? cf.botManagement : undefined;
  if (bm !== null && typeof bm === "object") {
    if (bm.verifiedBot === true) return "a";
    if (typeof bm.score === "number" && bm.score < 30) return "a";
  }
  return "h";
}

/**
 * Whether this exchange is a countable page view: a GET answered 200 with
 * text/html, not a prefetch, and the visitor has not opted out. Do Not Track
 * and Global Privacy Control are honored by recording nothing; any value
 * other than an explicit 0 counts as an opt-out, to fail safe.
 */
export function shouldCount(request, response) {
  if (request.method !== "GET") return false;
  if (response.status !== 200) return false;
  const type = response.headers.get("content-type");
  if (typeof type !== "string" || !type.toLowerCase().startsWith("text/html")) return false;
  for (const name of ["dnt", "sec-gpc"]) {
    const v = request.headers.get(name);
    if (v !== null && v.trim() !== "0") return false;
  }
  const purpose = `${request.headers.get("sec-purpose") ?? ""} ${request.headers.get("purpose") ?? ""} ${request.headers.get("x-moz") ?? ""}`;
  if (/prefetch|preview/i.test(purpose)) return false;
  return true;
}

/**
 * The row to store, or null to store nothing. Never throws for odd input.
 * env.GEO_LEVEL: city (default), region or country.
 */
export function buildRow(request, response, env, nowMs) {
  if (!shouldCount(request, response)) return null;
  const url = new URL(request.url);
  const page = normalizePath(url.pathname);
  if (page === null) return null;
  const cf = request.cf;
  const geo = geoFrom(cf, env && env.GEO_LEVEL);
  const ref = referrerInfo(request.headers.get("referer"), url.hostname);
  return {
    ts: hourBucket(nowMs),
    page,
    src_kind: ref.kind,
    src: ref.host,
    country: geo.country,
    region: geo.region,
    city: geo.city,
    net: netClass(cf, geo.tor),
    bot_class: botClass(request.headers, cf),
  };
}

// ?10 and ?11 are the UTC day bounds, computed in JS (see dayWindow), so the
// window never depends on how the driver types ?1.
// One statement makes the admission check and insert atomic in SQLite. A
// domain already admitted that UTC day stays in its bucket. New domains after
// the cap share the closed other bucket. The cap check runs once per row, in
// the cap subquery, and both CASE columns read its result.
export const INSERT_SQL = `INSERT INTO view_events
  (ts, page, src_kind, src, country, region, city, net, bot_class)
SELECT ?1, ?2,
  CASE WHEN cap.over THEN 'o' ELSE ?3 END,
  CASE WHEN cap.over THEN 'other' ELSE ?4 END,
  ?5, ?6, ?7, ?8, ?9
FROM (
  SELECT (
    ?3 = 'r'
    AND NOT EXISTS (
      SELECT 1 FROM view_events
      WHERE ts >= ?10 AND ts < ?11
        AND src_kind = 'r' AND src = ?4
    )
    AND ${MAX_DAILY_REFERRER_DOMAINS} <= (
      SELECT COUNT(DISTINCT src) FROM view_events
      WHERE ts >= ?10 AND ts < ?11
        AND src_kind = 'r'
    )
  ) AS over
) AS cap`;

/** Whole-second UTC day bounds [start, end) containing ts (seconds). */
export function dayWindow(ts) {
  const start = Math.floor(ts / 86400) * 86400;
  return { start, end: start + 86400 };
}

/** One D1 write. Rejects on any database error; the caller swallows it. */
export async function insertRow(db, row) {
  const day = dayWindow(row.ts);
  await db
    .prepare(INSERT_SQL)
    .bind(row.ts, row.page, row.src_kind, row.src, row.country, row.region, row.city, row.net, row.bot_class, day.start, day.end)
    .run();
}
