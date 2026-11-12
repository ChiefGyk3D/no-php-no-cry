// SPDX-License-Identifier: Apache-2.0
//
// Behavioral egress probe, run in a child process by middleware.test.mjs.
// Every outbound and logging entry point is replaced by a trap BEFORE the
// collector is imported, so a module-load alias is trapped too, then the
// collector handles hostile requests. Any call to a trap is recorded. This
// watches what the code does, not how it is spelled, so it does not depend on
// matching syntax.
//
// HONEST LIMIT: this is a regression test, not proof. It observes only the
// requests it drives (the tables below: methods, paths, hosts, statuses, header
// names and values, environments). It cannot show that no input at all reaches
// an egress call, and a branch keyed on a value absent from the tables stays
// unseen. The tables are wide on purpose and cheap to extend, but the real
// guarantee is review of the small collector source plus the platform's own
// limits.
import { writeSync } from "node:fs";

const hits = [];
const trap = (name) => (...args) => {
  hits.push(name);
  throw new Error(`egress trap: ${name}`);
};
globalThis.fetch = trap("fetch");
globalThis.XMLHttpRequest = trap("XMLHttpRequest");
globalThis.WebSocket = trap("WebSocket");
globalThis.EventSource = trap("EventSource");
globalThis.WebTransport = trap("WebTransport");
try {
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: { sendBeacon: trap("sendBeacon") },
  });
} catch {}
for (const m of Object.keys(console)) {
  if (typeof console[m] === "function") console[m] = trap(`console.${m}`);
}
// Any logging route ends at a stream write.
for (const s of [process.stdout, process.stderr]) {
  s.write = trap("stdio-write");
}

// argv[2] names the module to drive; the default is the real Function. The test
// passes a deliberately leaking module to prove the probe bites.
const target = process.argv[2] || new URL("../../../functions/_middleware.js", import.meta.url).href;
const { onRequest } = await import(target);

const UA = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0";
const writes = [];
const db = {
  prepare(sql) {
    return {
      bind(...args) {
        return { sql, args, run: () => (writes.push({ sql, args }), Promise.resolve({ success: true })) };
      },
    };
  },
  batch(stmts) {
    for (const st of stmts) writes.push({ sql: st.sql, args: st.args });
    return Promise.resolve([]);
  },
};
const failingDb = {
  prepare() {
    throw new Error("D1 unavailable");
  },
};

const headerSets = [
  { "user-agent": UA },
  { "user-agent": UA, referer: "https://search.example.org/?q=secret" },
  { "user-agent": "Googlebot/2.1", referer: "https://evil.example/" },
  { "user-agent": "x".repeat(30000), referer: "https://a.example/" + "y".repeat(30000) },
  { "cf-connecting-ip": "198.51.100.7", "x-forwarded-for": "198.51.100.7", "accept-language": "en-US" },
  {},
];
// Every header name below is sent with every value below, one header at a
// time, so a branch keyed on a single header is driven.
const headerNames = [
  "x-leak", "x-debug", "x-forwarded-host", "x-real-ip", "x-forwarded-for", "forwarded",
  "cf-connecting-ip", "cf-ipcountry", "cf-ray", "cf-visitor", "true-client-ip", "via",
  "accept", "accept-language", "accept-encoding", "authorization", "cookie", "dnt",
  "sec-gpc", "sec-fetch-dest", "sec-fetch-mode", "sec-fetch-site", "origin", "host",
  "referer", "user-agent", "purpose", "x-requested-with", "range", "if-none-match",
];
const headerValues = ["1", "true", "debug", "", "https://example.org/", "198.51.100.7", "a".repeat(5000), "../.."];
for (const name of headerNames) {
  for (const value of headerValues) headerSets.push({ "user-agent": UA, [name]: value });
}
const methods = ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"];
const paths = [
  "/posts/a/?token=abc", "/", "/index.xml", "/robots.txt", "/favicon.ico", "/admin", "/api/x",
  "/posts/a/?x-leak=1", "/%2e%2e/", "/a/b/c/d/e/f/g/h/", "/" + "z".repeat(3000), "/posts/%00/",
];
const statuses = [200, 301, 404, 500];
const hosts = ["blog.example.test", "example.org", "203.0.113.9"];
const envs = [{ DB: db }, { DB: failingDb }, { DB: db, GEO_LEVEL: "country" }, {}];

async function drive(env, request, response) {
  const pending = [];
  Object.defineProperty(request, "cf", {
    configurable: true,
    value: { country: "US", regionCode: "NY", city: "New York", asn: 1, botManagement: { score: 3 } },
  });
  try {
    await onRequest({ request, env, waitUntil: (p) => pending.push(p), next: async () => response });
  } catch {}
  await Promise.allSettled(pending);
}
const page = () =>
  new Response("<!doctype html><p>hi</p>", { status: 200, headers: { "content-type": "text/html; charset=utf-8" } });

for (const env of envs) {
  for (const headers of headerSets) {
    await drive(env, new Request("https://blog.example.test/posts/a/?token=abc", { headers }), page());
  }
}
// Methods x paths x hosts x statuses, against the first two environments.
for (const env of envs.slice(0, 2)) {
  for (const method of methods) {
    for (const path of paths) {
      for (const host of hosts) {
        for (const status of statuses) {
          let request;
          try {
            request = new Request(`https://${host}${path}`, {
              method,
              headers: { "user-agent": UA, referer: `https://${host}/` },
            });
          } catch {
            continue;
          }
          const redirect = status === 301;
          const response = new Response(redirect ? null : "<!doctype html><p>x</p>", {
            status,
            headers: { "content-type": "text/html; charset=utf-8", ...(redirect ? { location: "/" } : {}) },
          });
          await drive(env, request, response);
        }
      }
    }
  }
}
const out = JSON.stringify({ hits, rows: writes.length });
writeSync(1, out);
