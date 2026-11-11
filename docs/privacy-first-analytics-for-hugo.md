# Add privacy-first analytics to a Hugo site

This pattern counts successful HTML page views in a Cloudflare Pages Function, not in
browser JavaScript. It honors Global Privacy Control and Do Not Track, fails open when
the counter cannot write, and never stores or logs a raw or partial address, user-agent
text, fingerprint signal, cookie or storage identifier, cross-site identifier, or value
that can be joined to a person.

In no-php-no-cry, the view collector is built and tested but not deployed. The outbound
click route and the configuration-generated privacy page described below are planned and
are not live in no-php-no-cry. Treat the snippets as an integration checklist, not as a
drop-in package.

## Site configuration

Keep owner choices in one non-secret data file, such as `data/analytics.toml`. Start with
the more private settings and leave the kill switch on until the preview checks pass.

```toml
enabled = false
host = "PUBLIC_SITE_HOST"
geo = "country"
min_cell = 5
raw_keep_days = 7
aggregate_keep_days = 90
clicks = "off"
visitor_code = "off"
sources = ["newsletter"]

[limits]
referrer_domains_per_day = 300
click_domains_per_day = 150
```

Use a placeholder in a public example and put the real host and source labels only in
the site configuration. Validate every choice against a closed vocabulary. For example,
`geo` is one of `country`, `region`, or `city`; `clicks` is `off`, `listed`, or
`per-domain`; and `visitor_code` is `off` or `daily`. Reject unknown keys and invalid
values. A bad site entry disables that site instead of falling back to a wider setting.

At deploy time, map the same choices to the collector's environment: the database is
bound as `DB`, `geo` becomes `GEO_LEVEL`, and `enabled = false` becomes
`ANALYTICS_OFF=1`. The current no-php-no-cry collector implements those three settings.
Retention, floors, source labels, click mode, and visitor-code mode must not be claimed
until the corresponding code and maintenance job implement them.

Optional, less private: city stores rough city names in a separate location aggregate.
It needs a floor at each geographic level, roll-up from city to region to country, and
complementary suppression. no-php-no-cry does not yet implement all of those safeguards.

Optional, less private: per-domain clicks reveal which destination sites receive clicks.
Strip paths, queries, fragments, ports, user information, and subdomains at build time,
then admit only registrable domains found in the built site. Fold excess or invalid
values into `other`. This route is planned in no-php-no-cry.

Optional, less private: daily visitor code estimates unique visitors. It creates a
short-lived identifier even if it rotates daily. no-php-no-cry rejected this option and
does not implement a visitor code, visitor table, or hashing secret.

## Hugo render hook

The planned click option uses a Markdown link render hook at
`layouts/_markup/render-link.html`. A build helper backed by a pinned Public Suffix List
must first reduce each external destination to a registrable domain and expose it as
`.Page.Scratch.Get "analyticsDomain"`. If that value is missing or is not in the
configured built-site domain list, omit `ping`.

```go-html-template
{{- $href := .Destination | safeURL -}}
{{- $domain := .Page.Scratch.Get "analyticsDomain" -}}
{{- $allowed := and site.Data.analytics.enabled (ne site.Data.analytics.clicks "off") $domain -}}
<a href="{{ $href }}"{{ with .Title }} title="{{ . }}"{{ end }}
  {{- if $allowed }} ping="/e/c/{{ $domain | urlquery }}"{{ end -}}>
  {{- .Text | safeHTML -}}
</a>
```

Do not derive the domain with string splitting in the template. Public suffixes and
private hosting suffixes make that unsafe. The Function must repeat the validation,
check membership in the generated domain list, return one uniform empty response, and
log nothing. Until that route and helper exist, keep `clicks = "off"` and omit `ping`.

## Cloudflare Pages routes

Copy `_routes.json` into the published site. Include page requests so the middleware can
see successful HTML responses, then exclude static assets so they do not invoke a
Function. Keep the list below aligned with the file types your site publishes.

```json
{
  "version": 1,
  "include": ["/*"],
  "exclude": [
    "/css/*",
    "/fonts/*",
    "/*.js",
    "/*.png",
    "/*.jpg",
    "/*.webp",
    "/*.svg",
    "/*.woff2",
    "/*.xml",
    "/*.txt"
  ]
}
```

Preview the generated file before relying on a wildcard. The collector itself must still
count only `GET` requests answered `200` with a `text/html` content type.

## Response headers

The server-side view counter needs no browser permission. A same-origin click `ping`
uses `connect-src 'self'`. Add or preserve these lines in the site's single `/*` block in
`_headers`; merge them into an existing policy instead of adding a second policy.

```text
/*
  Content-Security-Policy: default-src 'none'; script-src 'self'; connect-src 'self'; img-src 'self'; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: accelerometer=(), camera=(), geolocation=(), gyroscope=(), microphone=(), payment=(), usb=()
```

If Cloudflare Web Analytics is also enabled, name it separately in the privacy text and
append only the beacon script source that its current documentation requires to the
existing `script-src` directive. It is a second counter, and its results must not be
joined to this one.

## Privacy text from the same configuration

Build the privacy text from `site.Data.analytics`, the same object used by the hook and
deployment configuration. Do not maintain a looser hand-written list. A partial can
render the enabled choices, floor, and retention ceilings:

```go-html-template
{{- with site.Data.analytics -}}
{{- if .enabled -}}
<p>This site counts successful HTML page views without cookies.
{{- if eq .visitor_code "off" }} It does not use a visitor identifier.
{{- else if eq .visitor_code "daily" }} It uses a short-lived visitor code that rotates
daily to estimate unique visitors.
{{- else }}{{ errorf "unsupported analytics visitor_code %q" .visitor_code }}{{ end }}
It keeps the page path, referrer host, hour, bot class, and {{ .geo }} location for at
most {{ .raw_keep_days }} days. Daily totals are kept for at most
{{ .aggregate_keep_days }} days and cells below {{ .min_cell }} visits are withheld.</p>
<p>Global Privacy Control and Do Not Track requests are not counted.</p>
{{- if eq .clicks "off" -}}
{{- else if eq .clicks "listed" -}}
<p>Clicks to configured links are counted by their configured label.</p>
{{- else if eq .clicks "per-domain" -}}
<p>Outbound clicks are counted by destination site only, never by full address.</p>
{{- else -}}
{{- errorf "unsupported analytics clicks mode %q" .clicks -}}
{{- end -}}
{{- end -}}
{{- end -}}
```

The complete page must also say that the counter stores no address, user-agent text,
fingerprint, cookie or storage identifier, cross-site identifier, or join to a person.
Name every other analytics service separately. If configuration enables a field that the
template cannot describe, fail the build. Ship the privacy change in the same deployment
that first turns counting on.

## Preview-first deployment order

1. Keep `enabled = false`, deploy the Function and static `_routes.json` and `_headers`
   files to a non-production branch preview, and use a separate preview database.
2. Apply migrations to the preview database and bind it to the preview environment.
3. Turn the preview entry on. Confirm that only successful HTML requests count, opt-out
   headers record nothing, excluded assets bypass the Function, failures still serve the
   page, and no handler logs request data.
4. Run maintenance and read only the floored report views. Check the rendered privacy
   page against the enabled configuration.
5. Create and migrate the production database. Keep the production entry off.
6. Deploy the code, routes, headers, and privacy text to production together. Bind the
   production database, then turn on that site entry.
7. Verify one synthetic page view, then verify the kill switch. Use synthetic values such
   as `N0CALL`, `N0TST`, and `FN31pr` wherever a test fixture needs identity-like data.

Never send preview traffic to the production database.

## Owner-only account checklist

These steps change Cloudflare or Doppler account state. The repository agent does not run
them.

- [ ] In Cloudflare, create separate preview and production D1 databases.
- [ ] In Cloudflare Pages, bind each database as `DB` only in its matching environment.
- [ ] Apply the migrations with a narrowly scoped D1 token, then remove that scope from
      the deploy token if a separate maintenance token owns scheduled cleanup.
- [ ] Store account values and scoped tokens in Doppler. Do not commit them or place them
      in Hugo data, rendered HTML, logs, or examples.
- [ ] Set `ANALYTICS_OFF=1` in preview, configure `GEO_LEVEL`, and review the bounded
      write timeout before the first preview test.
- [ ] Review Cloudflare Pages runtime behavior and select fail open so an analytics
      failure cannot take down the site.
- [ ] Schedule the idempotent roll-up and retention job, then verify it against preview
      data before granting production access.
- [ ] If keeping Cloudflare Web Analytics, enable it deliberately, keep its Content
      Security Policy entries narrow, and verify its injected beacon separately.
- [ ] After the preview checks pass, repeat the binding and variables for production,
      publish the matching privacy text, and remove the per-site kill switch.
- [ ] After launch, compare request volume with the account limits and keep a tested
      rollback: restore `ANALYTICS_OFF=1`, remove `DB`, or revert the deployment.

