// Tests for the dependency-free ASN refresh generator. All fixtures are synthetic.
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import {
  buildEntries,
  buildReport,
  generateModule,
  main,
  parseIpverse,
  parseX4BList,
  sanitizeComment,
} from "../refresh-asns.mjs";

function syntheticList(start, count, label = "Synthetic N0CALL network") {
  return Array.from({ length: count }, (_, index) => `AS${start + index} # ${label} ${index}`).join("\n");
}

test("X4B parsing skips exclusions and rejects invalid and reserved ASNs", () => {
  const parsed = parseX4BList(`
# comment only
-AS65000 # excluded
AS0 # zero
AS64512 # private low
AS65534 # private high
AS4200000000 # reserved high
AS4294967296 # too large
AS64496 # valid
AS65535 # valid
bad input
`);
  assert.deepEqual(parsed, [
    { asn: 64496, comment: "valid" },
    { asn: 65535, comment: "valid" },
  ]);
});

test("VPN filtering drops Tor and keep-out entries and VPN wins overlap", () => {
  const vpn = parseX4BList(`
AS64496 # N0CALL VPN
AS64497 # N0TST Tor exit
AS60729 # N0CALL proxy
AS13335 # Cloudflare synthetic label
`);
  const datacenter = parseX4BList(`
AS64496 # N0CALL hosting overlap
AS64498 # N0TST hosting
AS13335 # N0CALL datacenter
`);
  assert.deepEqual(buildEntries(vpn, datacenter), [
    { asn: 13335, className: "hosting-datacenter", comment: "N0CALL datacenter" },
    { asn: 64496, className: "vpn-proxy", comment: "N0CALL VPN" },
    { asn: 64498, className: "hosting-datacenter", comment: "N0TST hosting" },
  ]);
});

test("comments are sanitized as untrusted input", () => {
  assert.equal(
    sanitizeComment("  N0CALL\u0000  `bad` */ line\n" + "x".repeat(80)),
    "N0CALL bad * / line " + "x".repeat(40),
  );
  assert.equal(sanitizeComment("\r\n\t"), "");
});

test("generated module is deterministic, sorted and imports cleanly", async () => {
  const entries = [
    { asn: 64498, className: "hosting-datacenter", comment: "N0TST two" },
    { asn: 64496, className: "vpn-proxy", comment: "N0CALL one" },
  ];
  const options = { sourceSha: "a".repeat(40), refreshDate: "2026-11-10" };
  const first = generateModule(entries, options);
  assert.equal(first, generateModule([...entries].reverse(), options));
  assert.ok(first.indexOf("[64496") < first.indexOf("[64498"));
  assert.match(first, /SPDX-License-Identifier: Apache-2.0/);
  assert.match(first, /X4BNet\/lists_vpn at commit a{40}, MIT/);

  const dir = mkdtempSync(join(tmpdir(), "asn-module-"));
  try {
    const file = join(dir, "hosting-asns.mjs");
    writeFileSync(file, first);
    const imported = await import(`${pathToFileURL(file)}?test=${Date.now()}`);
    assert.deepEqual([...imported.HOSTING_ASNS], [
      [64496, "vpn-proxy"],
      [64498, "hosting-datacenter"],
    ]);
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("ipverse field variants produce review findings without dropping entries", () => {
  const metadata = parseIpverse(JSON.stringify({
    "64496": { category: "hosting", lastAnnounced: "2026-10-01" },
    "AS64497": { type: "isp", last_announced: "2025-01-01" },
  }));
  const entries = [
    { asn: 64496, className: "vpn-proxy", comment: "N0CALL" },
    { asn: 64497, className: "hosting-datacenter", comment: "N0TST" },
    { asn: 64498, className: "hosting-datacenter", comment: "N0CALL unknown" },
  ];
  const report = buildReport(entries, metadata, new Date("2026-11-10T00:00:00Z"), { sourceSha: "c".repeat(40) });
  assert.match(report, /X4BNet commit c{40}/);
  assert.match(report, /AS64497.*category.*isp/i);
  assert.match(report, /AS64497.*older than 6 months/i);
  assert.match(report, /AS64498.*not present/i);
  assert.equal(entries.length, 3);
});

test("CLI refuses entry counts outside the safety range without writing output", () => {
  const dir = mkdtempSync(join(tmpdir(), "asn-count-"));
  try {
    const vpn = join(dir, "vpn.txt");
    const dc = join(dir, "dc.txt");
    const out = join(dir, "out.mjs");
    const report = join(dir, "report.md");
    writeFileSync(vpn, "AS64496 # N0CALL\n");
    writeFileSync(dc, "AS64497 # N0TST\n");
    assert.throws(
      () => main(["--vpn", vpn, "--datacenter", dc, "--out", out, "--report", report, "--source-sha", "a".repeat(40)]),
      /entry count.*300/i,
    );
    assert.throws(() => readFileSync(out));

    writeFileSync(vpn, syntheticList(100000, 1251));
    writeFileSync(dc, syntheticList(200000, 1250));
    assert.throws(
      () => main(["--vpn", vpn, "--datacenter", dc, "--out", out, "--report", report, "--source-sha", "a".repeat(40)]),
      /entry count.*2500/i,
    );
    assert.throws(() => readFileSync(out));
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("CLI refuses a change over 20 percent and allow-large-change overrides it", () => {
  const dir = mkdtempSync(join(tmpdir(), "asn-change-"));
  try {
    const vpn = join(dir, "vpn.txt");
    const dc = join(dir, "dc.txt");
    const out = join(dir, "out.mjs");
    const report = join(dir, "report.md");
    writeFileSync(vpn, syntheticList(100000, 150));
    writeFileSync(dc, syntheticList(100150, 150));
    writeFileSync(out, generateModule(buildEntries(parseX4BList(syntheticList(200000, 150)), parseX4BList(syntheticList(200150, 150))), { sourceSha: "b".repeat(40), refreshDate: "2026-10-10" }));
    const args = ["--vpn", vpn, "--datacenter", dc, "--out", out, "--report", report, "--source-sha", "a".repeat(40)];
    assert.throws(() => main(args), /more than 20 percent/i);
    assert.match(readFileSync(out, "utf8"), /commit b{40}/);

    main([...args, "--allow-large-change"]);
    assert.match(readFileSync(out, "utf8"), /commit a{40}/);
  } finally {
    rmSync(dir, { recursive: true });
  }
});
