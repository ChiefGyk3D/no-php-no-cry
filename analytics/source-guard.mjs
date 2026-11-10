// SPDX-License-Identifier: Apache-2.0
//
// Static guards used by the tests. Not part of the Function bundle.

// Each entry is [name, pattern]. This is an explicit closed heuristic, not a
// JavaScript parser. Security-sensitive names are rejected in direct calls,
// computed string properties and simple assignments. Comments in collector
// sources avoid matching these patterns. The fixtures cover every supported
// form so broadening JavaScript style cannot silently weaken the guard.
const FORBIDDEN = [
  ["address-header", /cf-connecting-ip|x-forwarded-for|true-client-ip|x-real-ip|x-client-ip/i],
  ["cookie-or-storage", /set-cookie|document\.cookie|localstorage|sessionstorage|indexeddb/i],
  ["outbound-call", /\bfetch\s*\(|\b(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:(?:globalThis|window|self)\s*\.\s*)?fetch\b|XMLHttpRequest|WebSocket|sendBeacon|["'](?:fetch|XMLHttpRequest|WebSocket|sendBeacon)["']/],
  ["logging", /\bconsole\s*\.|\b(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:(?:globalThis|window|self)\s*\.\s*)?console\b|["']console["']/],
  ["language-header", /accept-language/i],
  ["precise-location", /\.latitude|\.longitude|\.postalCode|\.metroCode|\.timezone\b/],
  ["network-owner", /asOrganization/],
];

/** Names of the forbidden patterns found in a source text. */
export function scanSource(text) {
  return FORBIDDEN.filter(([, re]) => re.test(text)).map(([name]) => name);
}

/** Problems with the listing of functions/: only these two files, no routes. */
export function checkFunctionsDir(names) {
  const want = ["_middleware.js", "package.json"];
  const problems = [];
  for (const n of names) if (!want.includes(n)) problems.push(`unexpected file: ${n}`);
  for (const n of want) if (!names.includes(n)) problems.push(`missing file: ${n}`);
  return problems;
}
