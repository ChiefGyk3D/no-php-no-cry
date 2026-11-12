import { buildClick, insertClick } from "../../../analytics/click.mjs";
import { SITE_DOMAINS } from "../../../analytics/site-domains.mjs";

export async function onRequestPost(context) {
  const row = buildClick(context.request, context.params.domain, SITE_DOMAINS, Date.now());
  if (row && context.env.DB && context.env.ANALYTICS_OFF !== "1") {
    const work = insertClick(context.env.DB, row).catch(() => undefined);
    if (typeof context.waitUntil === "function") context.waitUntil(work);
  }
  return new Response(null, { status: 204 });
}

