// SPDX-License-Identifier: Apache-2.0
//
// Static lint used by the tests. Not part of the Function bundle.
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
