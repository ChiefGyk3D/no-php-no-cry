// SPDX-License-Identifier: Apache-2.0
// Build the closed ASN-to-class map used by collect.mjs. This file has no
// packages and performs no network access; the workflow fetches inputs first.
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const MIN_ENTRIES = 300;
const MAX_ENTRIES = 2500;
const MAX_CHANGE_RATIO = 0.2;
const SIX_MONTHS_MS = 183 * 24 * 60 * 60 * 1000;

// Owner-editable exceptions. Tor is excluded by comment separately because the
// collector detects it from Cloudflare's Tor pseudo-country.
export const KEEP_OUT_OF_VPN = new Set([
  60729, // Tor-related network handled by the Tor class.
  13335, // Cloudflare WARP and CDN origin traffic would over-classify visitors.
]);

function validAsn(asn) {
  return Number.isInteger(asn) && asn >= 1 && asn <= 4294967295 &&
    !(asn >= 64512 && asn <= 65534) && asn < 4200000000;
}

export function parseX4BList(text) {
  const entries = [];
  for (const raw of String(text).split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#") || line.startsWith("-AS")) continue;
    const match = /^AS(\d+)\s*(#\s*(.*))?$/.exec(line);
    if (!match) continue;
    const asn = Number(match[1]);
    if (!validAsn(asn)) continue;
    entries.push({ asn, comment: match[3] ?? "" });
  }
  return entries;
}

export function sanitizeComment(comment) {
  return String(comment)
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/`/g, "")
    .replace(/\*\//g, "* /")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 60);
}

export function buildEntries(vpnEntries, datacenterEntries) {
  const byAsn = new Map();
  for (const entry of vpnEntries) {
    if (KEEP_OUT_OF_VPN.has(entry.asn) || /tor/i.test(entry.comment)) continue;
    if (!byAsn.has(entry.asn)) {
      byAsn.set(entry.asn, { asn: entry.asn, className: "vpn-proxy", comment: sanitizeComment(entry.comment) });
    }
  }
  for (const entry of datacenterEntries) {
    if (!byAsn.has(entry.asn)) {
      byAsn.set(entry.asn, { asn: entry.asn, className: "hosting-datacenter", comment: sanitizeComment(entry.comment) });
    }
  }
  return [...byAsn.values()].sort((a, b) => a.asn - b.asn);
}

// ipverse has used both camelCase and snake_case in mirrors and snapshots.
// Accepted category fields: category, type. Accepted announcement fields:
// lastAnnounced, last_announced, lastAnnouncement, last_announcement.
export function parseIpverse(text) {
  const parsed = JSON.parse(text);
  const source = parsed.asns && typeof parsed.asns === "object" ? parsed.asns : parsed;
  const result = new Map();
  for (const [rawAsn, value] of Object.entries(source ?? {})) {
    if (!value || typeof value !== "object" || Array.isArray(value)) continue;
    const match = /^(?:AS)?(\d+)$/.exec(rawAsn);
    const asn = match ? Number(match[1]) : Number(value.asn ?? value.number);
    if (!validAsn(asn)) continue;
    result.set(asn, {
      category: value.category ?? value.type ?? "",
      lastAnnounced: value.lastAnnounced ?? value.last_announced ??
        value.lastAnnouncement ?? value.last_announcement ?? "",
    });
  }
  return result;
}

export function generateModule(entries, { sourceSha, refreshDate }) {
  const rows = [...entries]
    .sort((a, b) => a.asn - b.asn)
    .map(({ asn, className, comment }) => `  [${asn}, "${className}"],${comment ? ` // ${sanitizeComment(comment)}` : ""}`)
    .join("\n");
  return `// SPDX-License-Identifier: Apache-2.0
//
// Derived from X4BNet/lists_vpn at commit ${sourceSha}, MIT.
// Refreshed ${refreshDate}. See analytics/THIRD_PARTY.md.
//
// Autonomous systems that are hosting providers, data centers or VPN/proxy
// operators. The collector compares the visitor's ASN (which Cloudflare puts in
// request.cf, so no address is needed) with this table. A match only changes the
// "net" flag on the row; the ASN itself is never stored. No address ranges
// (CIDR) are used anywhere.
//
// Format: [ASN, class] where class is "hosting-datacenter" or "vpn-proxy".
// VPN wins when an ASN occurs in both upstream files. Each entry only changes a
// flag; a wrong or missing entry cannot break delivery.

export const HOSTING_ASNS = new Map([
${rows}
]);
`;
}

export function buildReport(entries, ipverse, now = new Date(), { sourceSha = "unknown" } = {}) {
  const lines = [
    "# ASN refresh report",
    "",
    `Generated ${now.toISOString().slice(0, 10)} with ${entries.length} entries.`,
    `X4BNet commit ${sourceSha}.`,
    "",
    "The ipverse cross-check is advisory. Findings never remove an ASN automatically.",
    "Accepted metadata fields are `category` or `type`, and `lastAnnounced`,",
    "`last_announced`, `lastAnnouncement` or `last_announcement`.",
    "",
    "## Review findings",
    "",
  ];
  if (!ipverse) {
    lines.push("ipverse metadata was not supplied.");
    return `${lines.join("\n")}\n`;
  }
  let findings = 0;
  for (const entry of entries) {
    const metadata = ipverse.get(entry.asn);
    if (!metadata) {
      lines.push(`- AS${entry.asn}: not present in ipverse metadata.`);
      findings++;
      continue;
    }
    if (String(metadata.category).toLowerCase() !== "hosting") {
      lines.push(`- AS${entry.asn}: ipverse category is ${metadata.category || "missing"}, not hosting.`);
      findings++;
    }
    const announced = Date.parse(metadata.lastAnnounced);
    if (Number.isFinite(announced) && now.getTime() - announced > SIX_MONTHS_MS) {
      lines.push(`- AS${entry.asn}: last announced ${metadata.lastAnnounced}, older than 6 months.`);
      findings++;
    }
  }
  if (findings === 0) lines.push("No advisory findings.");
  return `${lines.join("\n")}\n`;
}

function parseExisting(text) {
  const result = new Map();
  for (const match of String(text).matchAll(/\[(\d+),\s*"(hosting-datacenter|vpn-proxy)"\]/g)) {
    result.set(Number(match[1]), match[2]);
  }
  return result;
}

function changeRatio(entries, existing) {
  const next = new Map(entries.map((entry) => [entry.asn, entry.className]));
  let changed = 0;
  for (const [asn, className] of existing) if (next.get(asn) !== className) changed++;
  for (const asn of next.keys()) if (!existing.has(asn)) changed++;
  return existing.size === 0 ? Infinity : changed / existing.size;
}

function argumentsFrom(argv) {
  const options = { allowLargeChange: false };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--allow-large-change") {
      options.allowLargeChange = true;
      continue;
    }
    const key = { "--vpn": "vpn", "--datacenter": "datacenter", "--ipverse": "ipverse", "--out": "out", "--report": "report", "--source-sha": "sourceSha" }[arg];
    if (!key || index + 1 >= argv.length) throw new Error(`unknown or incomplete argument: ${arg}`);
    options[key] = argv[++index];
  }
  for (const key of ["vpn", "datacenter", "out", "report", "sourceSha"]) {
    if (!options[key]) throw new Error(`missing --${key === "sourceSha" ? "source-sha" : key}`);
  }
  if (!/^[0-9a-f]{40}$/i.test(options.sourceSha)) throw new Error("--source-sha must be a 40-character commit SHA");
  return options;
}

function writeAtomic(path, contents) {
  const temporary = join(dirname(path), `.${basename(path)}.${process.pid}.tmp`);
  writeFileSync(temporary, contents);
  renameSync(temporary, path);
}

export function main(argv = process.argv.slice(2)) {
  const options = argumentsFrom(argv);
  const entries = buildEntries(
    parseX4BList(readFileSync(options.vpn, "utf8")),
    parseX4BList(readFileSync(options.datacenter, "utf8")),
  );
  if (entries.length < MIN_ENTRIES || entries.length > MAX_ENTRIES) {
    throw new Error(`entry count ${entries.length} is outside safety range ${MIN_ENTRIES}..${MAX_ENTRIES}`);
  }
  let existing = new Map();
  try {
    existing = parseExisting(readFileSync(options.out, "utf8"));
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
  const ratio = changeRatio(entries, existing);
  if (!options.allowLargeChange && ratio > MAX_CHANGE_RATIO) {
    throw new Error(`more than 20 percent of entries changed (${Number.isFinite(ratio) ? (ratio * 100).toFixed(1) : "no existing list"}%); review and rerun with --allow-large-change`);
  }
  const now = new Date();
  const ipverse = options.ipverse ? parseIpverse(readFileSync(options.ipverse, "utf8")) : null;
  const output = generateModule(entries, { sourceSha: options.sourceSha.toLowerCase(), refreshDate: now.toISOString().slice(0, 10) });
  const report = buildReport(entries, ipverse, now, { sourceSha: options.sourceSha.toLowerCase() });
  writeAtomic(options.out, output);
  writeAtomic(options.report, report);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`refresh-asns: ${error.message}\n`);
    process.exitCode = 1;
  }
}
