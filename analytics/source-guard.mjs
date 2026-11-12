// SPDX-License-Identifier: Apache-2.0
//
// Source selection and static lint for the page-view collector.
//
// BEST-EFFORT LINT, NOT A SECURITY BOUNDARY. These are regular expressions over
// source text, not a JavaScript parser (the repository has none and adds no
// dependency), so equivalent spellings of a call can evade them. They catch
// honest mistakes and keep review easy. The enforced egress boundary is the
// behavioral probe in analytics/test/fixtures/egress-probe.mjs (run by
// middleware.test.mjs), which traps every outbound and logging entry point
// before the Function loads. Do not extend these patterns to chase new spellings.
// Comments in collector sources avoid matching these patterns.
const FORBIDDEN = [
  ["address-header", /cf-connecting-ip|x-forwarded-for|true-client-ip|x-real-ip|x-client-ip/i],
  ["cookie-or-storage", /set-cookie|document\.cookie|localstorage|sessionstorage|indexeddb/i],
  ["outbound-call", /\bfetch\s*\(|\b(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:(?:globalThis|window|self)\s*\.\s*)?fetch\b|XMLHttpRequest|WebSocket|sendBeacon|["'](?:fetch|XMLHttpRequest|WebSocket|sendBeacon)["']/],
  ["logging", /\bconsole\s*\.|\b(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:(?:globalThis|window|self)\s*\.\s*)?console\b|["']console["']/],
  ["language-header", /accept-language/i],
  ["precise-location", /\.latitude|\.longitude|\.postalCode|\.metroCode|\.timezone\b/],
  ["network-owner", /asOrganization/],
];

const MAX_REFERER_CHARS = 2048;
const MAX_HOST = 80;
const SRC_RAW = /^[A-Za-z0-9-]{1,30}$/;
const SRC = /^[a-z0-9-]{1,30}$/;
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

/** Referrer reduced to a host name, never its path, query or fragment. */
export function referrerInfo(header, siteHost) {
  const direct = { kind: "d", value: "" };
  if (typeof header !== "string" || header.length === 0 || header.length > MAX_REFERER_CHARS) return direct;
  let url;
  try {
    url = new URL(header);
  } catch {
    return direct;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return direct;
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  if (host.length === 0 || host.length > MAX_HOST) return direct;
  if (host === String(siteHost || "").toLowerCase()) return { kind: "i", value: "" };
  if (host.startsWith("[") || /^\d+(\.\d+){3}$/.test(host)) return { kind: "o", value: "other" };
  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/.test(host)) return direct;
  return { kind: "r", value: registrableDomain(host) };
}

/** Parse the optional closed source list from the non-secret Pages variable. */
export function sourceList(raw) {
  if (raw === undefined) return undefined;
  let labels;
  try {
    labels = JSON.parse(raw);
  } catch {
    return undefined;
  }
  if (!Array.isArray(labels) || labels.length > 40) return undefined;
  if (labels.some((label) => typeof label !== "string" || !SRC.test(label))) return undefined;
  return [...new Set(labels)];
}

/**
 * Prefer exactly one valid closed-list `s` label. Invalid source input is
 * direct; only an absent `s` falls back to the referrer host. A site without a
 * list skips query parameters and uses the referrer rule.
 */
export function pageSource(pageUrl, sources, referrer, siteHost) {
  if (sources === undefined) return referrerInfo(referrer, siteHost);
  const all = pageUrl.searchParams.getAll("s");
  if (all.length === 0) return referrerInfo(referrer, siteHost);
  if (all.length !== 1 || !SRC_RAW.test(all[0])) return { kind: "d", value: "" };
  const label = all[0].toLowerCase();
  if (!SRC.test(label)) return { kind: "d", value: "" };
  return sources.includes(label) ? { kind: "s", value: label } : { kind: "o", value: "other" };
}

/** Names of the forbidden patterns found in a source text. */
export function scanSource(text) {
  return FORBIDDEN.filter(([, re]) => re.test(text)).map(([name]) => name);
}

/** Problems with the top-level functions listing and its one approved route. */
export function checkFunctionsDir(names) {
  const want = ["_middleware.js", "e", "package.json"];
  const problems = [];
  for (const n of names) if (!want.includes(n)) problems.push(`unexpected file: ${n}`);
  for (const n of want) if (!names.includes(n)) problems.push(`missing file: ${n}`);
  return problems;
}
