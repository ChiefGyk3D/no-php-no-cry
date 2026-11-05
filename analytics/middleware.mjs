// SPDX-License-Identifier: Apache-2.0
//
// The Pages Functions middleware body (functions/_middleware.js calls handle).
//
// Order matters for "never break a page":
//   1. await the page (context.next()); an error there is the origin's own and
//      is not hidden or recorded.
//   2. return that very Response, unread and unchanged.
//   3. everything this module does happens in code that cannot throw into the
//      response path: the row is built in a try block and the database write
//      runs after the response is on its way (waitUntil), raced against a
//      timer so a slow database frees the work in bounded time.
// Errors are swallowed on purpose and nothing is logged: a log line from a
// handler that has just read a request is where an address or user agent
// leaks. A visitor-level failure costs one lost count, never a page.

import { buildRow, insertRow } from "./collect.mjs";

const DEFAULT_TIMEOUT_MS = 1500;
const MIN_TIMEOUT_MS = 50;
const MAX_TIMEOUT_MS = 5000;

function timeoutMs(env) {
  const n = Number.parseInt(env.ANALYTICS_TIMEOUT_MS, 10);
  if (!Number.isFinite(n)) return DEFAULT_TIMEOUT_MS;
  return Math.min(MAX_TIMEOUT_MS, Math.max(MIN_TIMEOUT_MS, n));
}

async function boundedWrite(db, row, ms) {
  let timer;
  const limit = new Promise((resolve) => {
    timer = setTimeout(resolve, ms);
  });
  try {
    await Promise.race([insertRow(db, row), limit]);
  } catch {
    // fail open: a database error or a spent daily quota loses one count
  } finally {
    clearTimeout(timer);
  }
}

function schedule(context, response) {
  const env = context.env ?? {};
  if (!env.DB || env.ANALYTICS_OFF === "1") return;
  const row = buildRow(context.request, response, env, Date.now());
  if (row === null) return;
  const work = boundedWrite(env.DB, row, timeoutMs(env));
  if (typeof context.waitUntil === "function") context.waitUntil(work);
}

export async function handle(context) {
  const response = await context.next();
  try {
    schedule(context, response);
  } catch {
    // fail open
  }
  return response;
}
