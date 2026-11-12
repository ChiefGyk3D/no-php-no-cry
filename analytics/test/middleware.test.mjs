// Tests for the Pages Functions middleware: fail open, bounded time, no body
// or header changes, opt-outs record nothing. Run: node --test analytics/test/
import test from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { pathToFileURL } from "node:url";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { onRequest } from "../../functions/_middleware.js";
import { scanSource, checkFunctionsDir } from "../source-guard.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const UA = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0";

function fakeDb({ fail = false, hang = false } = {}) {
  const calls = [];
  return {
    calls,
    prepare(sql) {
      return {
        bind(...args) {
          return {
            sql,
            args,
            run: () => {
              calls.push({ sql, args });
              if (fail) return Promise.reject(new Error("D1 over the cap"));
              if (hang) return new Promise(() => {});
              return Promise.resolve({ success: true });
            },
          };
        },
      };
    },
    batch(stmts) {
      if (fail) return Promise.reject(new Error("D1 over the cap"));
      if (hang) return new Promise(() => {});
      for (const st of stmts) calls.push({ sql: st.sql, args: st.args });
      return Promise.resolve([]);
    },
  };
}

function ctx({
  url = "https://blog.example.test/posts/a/",
  headers = { "user-agent": UA },
  env = {},
  response,
  nextThrows,
} = {}) {
  const pending = [];
  const request = new Request(url, { headers });
  Object.defineProperty(request, "cf", {
    configurable: true,
    value: { country: "US", regionCode: "NY", city: "New York", asn: 1 },
  });
  const res =
    response ??
    new Response("<!doctype html><p>hi</p>", {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8", "x-keep": "1" },
    });
  return {
    pending,
    context: {
      request,
      env,
      waitUntil: (p) => pending.push(p),
      next: async () => {
        if (nextThrows) throw nextThrows;
        return res;
      },
    },
    res,
  };
}

test("records one row after returning the page, response untouched", async () => {
  const db = fakeDb();
  const { context, pending, res } = ctx({ env: { DB: db } });
  const out = await onRequest(context);
  assert.equal(out, res, "the very same Response object");
  assert.equal(out.headers.get("x-keep"), "1");
  assert.equal(await out.text(), "<!doctype html><p>hi</p>");
  await Promise.all(pending);
  assert.equal(db.calls.length, 1);
  assert.match(db.calls[0].sql, /^INSERT INTO view_events/);
  assert.equal(db.calls[0].args[1], "/posts/a/");
});

test("the write is deferred: the page returns while D1 hangs", async () => {
  const db = fakeDb({ hang: true });
  const { context, pending } = ctx({ env: { DB: db, ANALYTICS_TIMEOUT_MS: "100" } });
  const t0 = Date.now();
  const out = await onRequest(context);
  assert.ok(Date.now() - t0 < 50, "no waiting on the database");
  assert.equal(out.status, 200);
  const t1 = Date.now();
  await Promise.all(pending);
  assert.ok(Date.now() - t1 < 2000, "the background work is bounded by the timeout");
});

test("fails open: a D1 error never reaches the visitor", async () => {
  const { context, pending } = ctx({ env: { DB: fakeDb({ fail: true }) } });
  const out = await onRequest(context);
  assert.equal(out.status, 200);
  await assert.doesNotReject(Promise.all(pending));
});

test("fails open: a synchronous throw from the binding", async () => {
  const db = {
    prepare() {
      throw new Error("binding broke");
    },
  };
  const { context, pending } = ctx({ env: { DB: db } });
  const out = await onRequest(context);
  assert.equal(out.status, 200);
  await assert.doesNotReject(Promise.all(pending));
});

test("no DB binding: page served, nothing recorded, no throw", async () => {
  const { context, pending } = ctx({ env: {} });
  const out = await onRequest(context);
  assert.equal(out.status, 200);
  await assert.doesNotReject(Promise.all(pending));
});

test("env undefined and a missing waitUntil do not break delivery", async () => {
  const { context } = ctx({});
  context.env = undefined;
  delete context.waitUntil;
  assert.equal((await onRequest(context)).status, 200);
  const { context: c2 } = ctx({ env: { DB: fakeDb() } });
  delete c2.waitUntil;
  assert.equal((await onRequest(c2)).status, 200);
});

test("kill switch records nothing", async () => {
  const db = fakeDb();
  const { context, pending } = ctx({ env: { DB: db, ANALYTICS_OFF: "1" } });
  await onRequest(context);
  await Promise.all(pending);
  assert.equal(db.calls.length, 0);
});

test("Do Not Track, GPC, 404s and assets record nothing", async () => {
  for (const [headers, response] of [
    [{ "user-agent": UA, dnt: "1" }],
    [{ "user-agent": UA, "sec-gpc": "1" }],
    [{ "user-agent": UA }, new Response("nope", { status: 404, headers: { "content-type": "text/html" } })],
    [{ "user-agent": UA }, new Response("body{}", { headers: { "content-type": "text/css" } })],
  ]) {
    const db = fakeDb();
    const { context, pending } = ctx({ headers, response, env: { DB: db } });
    await onRequest(context);
    await Promise.all(pending);
    assert.equal(db.calls.length, 0);
  }
});

test("a bot is recorded as a bot, not dropped", async () => {
  const db = fakeDb();
  const { context, pending } = ctx({ headers: { "user-agent": "Googlebot/2.1" }, env: { DB: db } });
  await onRequest(context);
  await Promise.all(pending);
  assert.equal(db.calls.length, 1);
  assert.equal(db.calls[0].args[8], "a");
});

test("hostile headers: huge referer, huge user agent, odd cf", async () => {
  const db = fakeDb();
  const { context, pending } = ctx({
    headers: {
      "user-agent": "x".repeat(30000),
      referer: "https://a.example.org/" + "y".repeat(30000),
    },
    env: { DB: db },
  });
  Object.defineProperty(context.request, "cf", {
    configurable: true,
    value: { country: { evil: 1 }, city: "x".repeat(1e5), asn: "NaN", botManagement: 7 },
  });
  const out = await onRequest(context);
  assert.equal(out.status, 200);
  await Promise.all(pending);
  assert.equal(db.calls.length, 1);
});

test("an error from next() is the origin's: not swallowed, nothing recorded", async () => {
  const db = fakeDb();
  const boom = new Error("origin down");
  const { context, pending } = ctx({ nextThrows: boom, env: { DB: db } });
  await assert.rejects(onRequest(context), boom);
  await Promise.all(pending);
  assert.equal(db.calls.length, 0);
});

// ---- egress boundary: the real control is behavioral. Cloudflare Pages
// Functions have no switch that removes outbound network access, so the probe
// runs the Function with every outbound and logging entry point trapped before
// load. The source guard below is only a best-effort lint on top of it.

const probe = join(here, "fixtures", "egress-probe.mjs");
function runProbe(moduleUrl) {
  const args = moduleUrl ? [probe, moduleUrl] : [probe];
  const r = spawnSync(process.execPath, args, { encoding: "utf8", timeout: 30000 });
  assert.equal(r.status, 0, `probe failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

test("egress probe: the Function makes no outbound call and logs nothing", () => {
  const out = runProbe();
  assert.deepEqual(out.hits, []);
  assert.ok(out.rows > 0, "the probe drove the recording path");
});

test("egress probe bites: leaking modules are caught", () => {
  const dir = mkdtempSync(join(tmpdir(), "egress-probe-"));
  try {
    const cases = {
      "fetch": 'export async function onRequest(c) { try { await fetch("https://example.org/?u=" + c.request.url); } catch {} return c.next(); }',
      "console.log": "export async function onRequest(c) { console.log(c.request.url); return c.next(); }",
      "stdio-write": "export async function onRequest(c) { try { process.stdout.write(c.request.url); } catch {} return c.next(); }",
    };
    for (const [name, src] of Object.entries(cases)) {
      const f = join(dir, `${name.replace(/\W/g, "_")}.mjs`);
      writeFileSync(f, src);
      const out = runProbe(pathToFileURL(f).href);
      assert.ok(out.hits.includes(name), `${name} detected: ${JSON.stringify(out.hits)}`);
    }
    const clean = join(dir, "clean.mjs");
    writeFileSync(clean, "export async function onRequest(c) { return c.next(); }");
    assert.deepEqual(runProbe(pathToFileURL(clean).href).hits, []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("egress probe bites on input-dependent leaks the first probe set missed", () => {
  const dir = mkdtempSync(join(tmpdir(), "egress-probe-"));
  try {
    // Each module leaks only for one header, method or path. A fixed handful of
    // requests would not drive them; the input tables do.
    const cases = {
      header: 'export async function onRequest(c) { if (c.request.headers.get("x-leak")) { try { await fetch("https://example.org/"); } catch {} } return c.next(); }',
      method: 'export async function onRequest(c) { if (c.request.method === "PATCH") { try { await fetch("https://example.org/"); } catch {} } return c.next(); }',
      path: 'export async function onRequest(c) { if (new URL(c.request.url).pathname === "/robots.txt") { try { await fetch("https://example.org/"); } catch {} } return c.next(); }',
    };
    for (const [name, src] of Object.entries(cases)) {
      const f = join(dir, `${name}.mjs`);
      writeFileSync(f, src);
      assert.ok(runProbe(pathToFileURL(f).href).hits.includes("fetch"), `${name}-dependent leak detected`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// ---- source lint (best effort, NOT a security boundary): collect loosely,
// assert strictly, with a negative case.

test("guard: collector sources never read the address, set cookies or call out", () => {
  const files = readdirSync(join(root, "analytics"))
    .filter((f) => f.endsWith(".mjs") && f !== "source-guard.mjs")
    .map((f) => join(root, "analytics", f));
  files.push(join(root, "functions", "_middleware.js"));
  files.push(join(root, "functions", "e", "c", "[[domain]].js"));
  assert.ok(files.length >= 3, "the guard collected the collector sources");
  for (const f of files) {
    assert.deepEqual(scanSource(readFileSync(f, "utf8")), [], f);
  }
});

test("guard bites: scanSource flags each forbidden pattern", () => {
  for (const bad of [
    'request.headers.get("CF-Connecting-IP")',
    "headers.get('x-forwarded-for')",
    'headers.get("True-Client-IP")',
    'new Headers({ "Set-Cookie": "a=b" })',
    'await fetch("https://example.org")',
    "document.cookie",
    "localStorage.setItem",
    'console.log(request.headers.get("user-agent"))',
    "console.log(request.url)",
    'headers.get("accept-language")',
    "cf.latitude",
    "cf.postalCode",
  ]) {
    assert.ok(scanSource(bad).length > 0, bad);
  }
  assert.deepEqual(scanSource("const a = 1; // nothing here"), []);
});

test("guard bites: computed properties and simple aliases cannot hide calls", () => {
  for (const bad of [
    'globalThis["console"]["log"](request.url)',
    'globalThis["fetch"]("https://example.org")',
    "const send = fetch; send('https://example.org')",
    "const send = globalThis.fetch; send('https://example.org')",
    "let send = window.fetch; send('https://example.org')",
    "var send = self . fetch; send('https://example.org')",
    "const log = globalThis.console; log.log(1)",
    "const socket = globalThis['WebSocket']; new socket('wss://example.org')",
    "const beacon = navigator['sendBeacon']; beacon('/collect')",
  ]) {
    assert.ok(scanSource(bad).length > 0, bad);
  }
});

test("guard: functions/ holds only the middleware, click route, and package.json", () => {
  const names = readdirSync(join(root, "functions")).sort();
  assert.deepEqual(names, ["_middleware.js", "e", "package.json"]);
  assert.deepEqual(readdirSync(join(root, "functions", "e")), ["c"]);
  assert.deepEqual(readdirSync(join(root, "functions", "e", "c")), ["[[domain]].js"]);
  assert.deepEqual(checkFunctionsDir(names), []);
});

test("guard bites: checkFunctionsDir flags any extra route or script", () => {
  assert.ok(checkFunctionsDir(["_middleware.js", "e", "package.json", "api.js"]).length > 0);
  assert.ok(checkFunctionsDir(["_middleware.js", "package.json", "_worker.js"]).length > 0);
  assert.ok(checkFunctionsDir(["package.json"]).length > 0, "middleware missing");
});
