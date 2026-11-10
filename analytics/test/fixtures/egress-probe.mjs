// SPDX-License-Identifier: Apache-2.0
//
// Behavioral egress probe, run in a child process by middleware.test.mjs.
// Every outbound and logging entry point is replaced by a trap BEFORE the
// collector is imported, so a module-load alias is trapped too, then the
// collector handles hostile requests. Any call to a trap is recorded. This
// watches what the code does, not how it is spelled, so it does not depend on
// matching syntax. Limit: only code paths the probe drives are observed.
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
const realWrite = process.stdout.constructor.prototype.write;

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
        return { run: () => (writes.push({ sql, args }), Promise.resolve({ success: true })) };
      },
    };
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
for (const env of [{ DB: db }, { DB: failingDb }, { DB: db, GEO_LEVEL: "country" }, {}]) {
  for (const headers of headerSets) {
    const pending = [];
    const request = new Request("https://blog.example.test/posts/a/?token=abc", { headers });
    Object.defineProperty(request, "cf", {
      configurable: true,
      value: { country: "US", regionCode: "NY", city: "New York", asn: 1, botManagement: { score: 3 } },
    });
    const response = new Response("<!doctype html><p>hi</p>", {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8" },
    });
    try {
      await onRequest({ request, env, waitUntil: (p) => pending.push(p), next: async () => response });
    } catch {}
    await Promise.allSettled(pending);
  }
}
const out = JSON.stringify({ hits, rows: writes.length });
realWrite.call(process.stdout, out);
