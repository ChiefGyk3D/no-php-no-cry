// Tests for the outbound-click collector (issue 296).
import test from "node:test";
import assert from "node:assert/strict";

import {
  CLICK_DAILY_NAMED_CAP,
  CLICK_HOURLY_NEW_CAP,
  buildClick,
  insertClick,
  registrableDomain,
} from "../click.mjs";
import { onRequestPost } from "../../functions/e/c/[[domain]].js";

const listed = new Set(["n0call.test", "n0tst.test"]);

function request(domain, { method = "POST", pingFrom = "https://chiefgyk3d.com/posts/fn31pr/", cf } = {}) {
  const headers = new Headers({ "ping-from": pingFrom });
  const value = new Request(`https://chiefgyk3d.com/e/c/${domain}`, { method, headers });
  if (cf !== undefined) Object.defineProperty(value, "cf", { value: cf });
  return value;
}

test("PSL parsing returns only an eTLD+1 and includes private suffixes", () => {
  assert.equal(registrableDomain("n0call.test"), "n0call.test");
  assert.equal(registrableDomain("www.n0call.test"), "n0call.test");
  assert.equal(registrableDomain("test"), null, "public suffix");
  assert.equal(registrableDomain("n0call.github.io"), "n0call.github.io", "private suffix");
  assert.equal(registrableDomain("github.io"), null, "private suffix itself");
});

test("the route accepts a listed eTLD+1 and reduces everything else to other", () => {
  const now = Date.UTC(2026, 10, 11, 15, 42);
  assert.deepEqual(buildClick(request("n0call.test"), "n0call.test", listed, now), {
    ts: Date.UTC(2026, 10, 11, 15) / 1000,
    domain: "n0call.test",
    country: "",
  });
  for (const forged of [
    "forged.test",
    "www.n0call.test",
    "TEST",
    "n0call.test:443",
    "n0call.test%2Fpath",
    "127.0.0.1",
    "user@n0call.test",
    "github.io",
    "a".repeat(52) + ".test",
  ]) {
    assert.equal(buildClick(request(forged), forged, listed, now).domain, "other", forged);
  }
});

test("non-POST, opt-out, and forged Ping-From requests record nothing", () => {
  assert.equal(buildClick(request("n0call.test", { method: "GET" }), "n0call.test", listed, 0), null);
  assert.equal(
    buildClick(request("n0call.test", { pingFrom: "https://n0tst.test/fn31pr/" }), "n0call.test", listed, 0),
    null,
  );
  const optedOut = request("n0call.test");
  optedOut.headers.set("sec-gpc", "1");
  assert.equal(buildClick(optedOut, "n0call.test", listed, 0), null);
});

test("the Pages route returns one uniform empty 204 and defers its write", async () => {
  const pending = [];
  const db = fakeDb();
  const response = await onRequestPost({
    request: request("n0call.test"),
    params: { domain: "n0call.test" },
    env: { DB: db },
    waitUntil: (work) => pending.push(work),
  });
  assert.equal(response.status, 204);
  assert.equal(await response.text(), "");
  assert.equal(pending.length, 1);
  await Promise.all(pending);
  assert.equal(db.state.events.length, 1);
});

function fakeDb() {
  const state = { seen: new Map(), events: [], countries: new Map() };
  return {
    state,
    async write(row) {
      const day = new Date(row.ts * 1000).toISOString().slice(0, 10);
      const hour = row.ts;
      let domain = row.domain;
      if (domain !== "other") {
        const daySeen = state.seen.get(day) ?? new Map();
        if (!daySeen.has(domain)) {
          const hourCount = [...daySeen.values()].filter((value) => value === hour).length;
          if (daySeen.size >= CLICK_DAILY_NAMED_CAP || hourCount >= CLICK_HOURLY_NEW_CAP) domain = "other";
          else daySeen.set(domain, hour);
        }
        state.seen.set(day, daySeen);
      }
      state.events.push({ ts: row.ts, domain });
      const key = `${day}:${row.country}`;
      state.countries.set(key, (state.countries.get(key) ?? 0) + 1);
    },
  };
}

test("one hour cannot spend the daily domain pool", async () => {
  const db = fakeDb();
  const ts = Date.UTC(2026, 10, 11, 15) / 1000;
  for (let i = 0; i < CLICK_DAILY_NAMED_CAP; i++) {
    await insertClick(db, { ts, domain: `n0call-${i}.test`, country: "" });
  }
  assert.equal(db.state.seen.get("2026-11-11").size, CLICK_HOURLY_NEW_CAP);
  assert.equal(db.state.events.filter((row) => row.domain === "other").length, CLICK_DAILY_NAMED_CAP - CLICK_HOURLY_NEW_CAP);
});

test("the daily cap folds excess domains into the reserved other cell", async () => {
  const db = fakeDb();
  const start = Date.UTC(2026, 10, 11) / 1000;
  for (let i = 0; i < CLICK_DAILY_NAMED_CAP + 20; i++) {
    await insertClick(db, {
      ts: start + Math.min(23, Math.floor(i / CLICK_HOURLY_NEW_CAP)) * 3600,
      domain: `n0tst-${i}.test`,
      country: "US",
    });
  }
  assert.equal(db.state.seen.get("2026-11-11").size, CLICK_DAILY_NAMED_CAP);
  assert.equal(new Set(db.state.events.map((row) => row.domain)).size, 150, "149 names plus other");
  assert.equal(db.state.events.filter((row) => row.domain === "other").length, 20);
  assert.equal(db.state.countries.get("2026-11-11:US"), CLICK_DAILY_NAMED_CAP + 20);
});

