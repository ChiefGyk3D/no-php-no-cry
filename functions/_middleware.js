// SPDX-License-Identifier: Apache-2.0
// Cloudflare Pages Functions middleware: server-side page-view counting with
// no script on the page. All logic lives in analytics/ (see
// analytics/middleware.mjs); static/_routes.json limits this to HTML routes.
// This directory must hold only this file and package.json: every other file
// here would become a route (analytics/test/middleware.test.mjs enforces it).
import { handle } from "../analytics/middleware.mjs";

export async function onRequest(context) {
  return handle(context);
}
