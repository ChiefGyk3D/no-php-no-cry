// SPDX-License-Identifier: Apache-2.0
// Outbound clicks reduced to a built-site eTLD+1. No URL or client identifier
// reaches a row, a log, or an exception.
import { PSL_EXACT, PSL_WILDCARD, PSL_EXCEPTION } from "./public-suffix-rules.mjs";

export const CLICK_DAILY_NAMED_CAP = 149;
export const CLICK_HOURLY_NEW_CAP = 7;
const DOMAIN = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/;

export function registrableDomain(value) {
  if (typeof value !== "string" || value.length > 63 || !DOMAIN.test(value)) return null;
  const labels = value.split(".");
  let suffixLabels = 1;
  for (let index = 0; index < labels.length; index++) {
    const candidate = labels.slice(index).join(".");
    if (PSL_EXCEPTION.has(candidate)) {
      suffixLabels = labels.length - index - 1;
      break;
    }
    if (PSL_EXACT.has(candidate)) suffixLabels = Math.max(suffixLabels, labels.length - index);
    if (index > 0 && PSL_WILDCARD.has(candidate)) {
      suffixLabels = Math.max(suffixLabels, labels.length - index + 1);
    }
  }
  if (labels.length <= suffixLabels) return null;
  return labels.slice(-suffixLabels - 1).join(".");
}

function optedOut(headers) {
  for (const name of ["dnt", "sec-gpc"]) {
    const value = headers.get(name);
    if (value !== null && value.trim() !== "0") return true;
  }
  return false;
}

export function buildClick(request, routeDomain, listedDomains, nowMs) {
  if (request.method !== "POST" || optedOut(request.headers)) return null;
  let from;
  try {
    from = new URL(request.headers.get("ping-from") || "");
  } catch {
    return null;
  }
  const requestUrl = new URL(request.url);
  if (from.protocol !== "https:" || from.hostname !== requestUrl.hostname) return null;
  const parsed = registrableDomain(routeDomain);
  const domain = parsed === routeDomain && listedDomains.has(routeDomain) ? routeDomain : "other";
  const cf = request.cf;
  const country = cf && typeof cf.country === "string" && /^[A-Z]{2}$/.test(cf.country) ? cf.country : "";
  return { ts: Math.floor(nowMs / 3_600_000) * 3600, domain, country };
}

export const REGISTER_CLICK_SQL =
  "INSERT OR IGNORE INTO click_domain_seen (day, domain, first_hour, n) " +
  "SELECT date(?1, 'unixepoch'), ?2, ?1, " +
  "COALESCE((SELECT MAX(n) FROM click_domain_seen WHERE day=date(?1, 'unixepoch')),0)+1 " +
  "WHERE ?2 <> 'other' " +
  "AND COALESCE((SELECT MAX(n) FROM click_domain_seen WHERE day=date(?1, 'unixepoch')),0) < ?3 " +
  "AND (SELECT COUNT(*) FROM click_domain_seen WHERE day=date(?1, 'unixepoch') AND first_hour=?1) < ?4";

export const INSERT_CLICK_SQL =
  "INSERT INTO click_events (ts, domain) SELECT ?1, " +
  "CASE WHEN ?2='other' OR EXISTS (SELECT 1 FROM click_domain_seen WHERE day=date(?1, 'unixepoch') AND domain=?2) THEN ?2 ELSE 'other' END";

export const UPSERT_CLICK_COUNTRY_SQL =
  "INSERT INTO click_country_daily (day, country, clicks) VALUES (date(?1, 'unixepoch'), ?2, 1) " +
  "ON CONFLICT(day, country) DO UPDATE SET clicks=clicks+1";

export async function insertClick(db, row) {
  if (typeof db.write === "function") {
    await db.write(row);
    return;
  }
  const register = db.prepare(REGISTER_CLICK_SQL).bind(
    row.ts,
    row.domain,
    CLICK_DAILY_NAMED_CAP,
    CLICK_HOURLY_NEW_CAP,
  );
  const event = db.prepare(INSERT_CLICK_SQL).bind(row.ts, row.domain);
  const country = db.prepare(UPSERT_CLICK_COUNTRY_SQL).bind(row.ts, row.country);
  await db.batch([register, event, country]);
}

