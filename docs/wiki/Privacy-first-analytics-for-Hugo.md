# Add privacy-first analytics to a Hugo site

This pattern counts successful HTML page views in a Cloudflare Pages Function, not in
browser JavaScript. It honors Global Privacy Control and Do Not Track, fails open when
the counter cannot write, and never stores or logs a raw or partial address, user-agent
text, fingerprint signal, cookie or storage identifier, cross-site identifier, or value
that can be joined to a person.

In no-php-no-cry, the view collector is built and tested but not deployed. The outbound
click route and configuration-generated privacy page below are planned and not live in no-php-no-cry.
Treat the snippets as an integration checklist, not as a drop-in package.

## Site configuration

Keep owner choices in one non-secret `analytics.toml` data file. Start with the more
private settings and leave the kill switch on until the preview checks pass.

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

Put every real owner value only in configuration. Validate closed choices: `geo` is
`country`, `region`, or `city`; `clicks` is `off`, `listed`, or `per-domain`; and
`visitor_code` is `off` or `daily`. Reject unknown keys. A bad entry disables that site.
Map the database to `DB`, `geo` to `GEO_LEVEL`, and `enabled = false` to
`ANALYTICS_OFF=1`. Those are the settings the current collector implements.

Optional, less private: city needs per-level floors, geographic roll-up, and
complementary suppression. Those safeguards are not all implemented here yet.

Optional, less private: per-domain clicks expose which destination sites receive clicks.
Keep only registrable domains from the built site and fold invalid or excess values into
`other`. This route is planned here.

Optional, less private: daily visitor code creates a short-lived identifier. This site
rejected it and has no visitor code, visitor table, or hashing secret.

## Hugo render hook

The planned `render-link.html` hook consumes a registrable domain from a
build helper backed by a pinned Public Suffix List. It omits `ping` unless the domain is
in the configured built-site list.

```go-html-template
{{- $href := .Destination | safeURL -}}
{{- $domain := .Page.Scratch.Get "analyticsDomain" -}}
{{- $allowed := and site.Data.analytics.enabled $domain -}}
<a href="{{ $href }}"{{ with .Title }} title="{{ . }}"{{ end }}
  {{- if $allowed }} ping="/e/c/{{ $domain | urlquery }}"{{ end -}}>
  {{- .Text | safeHTML -}}
</a>
```

Do not derive domains with string splitting. The Function must repeat validation, check
the generated allowlist, return one uniform empty response, and log nothing. Until that
route and helper exist, keep `clicks = "off"` and omit `ping`.

## Cloudflare Pages routes

Publish `_routes.json`, include pages, and exclude assets so they bypass the Function:

```json
{
  "version": 1,
  "include": ["/*"],
  "exclude": ["/css/*", "/fonts/*", "/*.js", "/*.png", "/*.jpg", "/*.webp", "/*.svg", "/*.woff2", "/*.xml", "/*.txt"]
}
```

Preview wildcard behavior. The collector must still accept only a `GET` answered `200`
with a `text/html` content type.

## Response headers

The view counter needs no browser permission. Same-origin click pings use
`connect-src 'self'`. Merge these lines into the single `/*` block in `_headers`:

```text
/*
  Content-Security-Policy: default-src 'none'; connect-src 'self'; img-src 'self'; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: accelerometer=(), camera=(), geolocation=(), gyroscope=(), microphone=(), payment=(), usb=()
```

If Cloudflare Web Analytics remains enabled, name it as a separate counter and add only
the script source its current documentation requires. Never join the two counters.

## Privacy text from the same configuration

Render the privacy page from `site.Data.analytics`, the object used by deployment and the
hook. A partial can expose its enabled choices and ceilings:

```go-html-template
{{- with site.Data.analytics -}}
{{- if .enabled -}}
<p>This site counts successful HTML page views without cookies or a visitor identifier.
It keeps the page path, referrer host, hour, bot class, and {{ .geo }} location for at
most {{ .raw_keep_days }} days. Daily totals are kept for at most
{{ .aggregate_keep_days }} days and cells below {{ .min_cell }} visits are withheld.</p>
<p>Global Privacy Control and Do Not Track requests are not counted.</p>
{{- if eq .clicks "per-domain" -}}
<p>Outbound clicks are counted by destination site only, never by full address.</p>
{{- end -}}
{{- end -}}
{{- end -}}
```

Also name every excluded identifier and every other analytics service. Fail the build if
an enabled field has no privacy text. Publish that text with the first counting deploy.

## Preview-first deployment order

1. With `enabled = false`, deploy the Function, `_routes.json`, and `_headers` to a branch
   preview that has a separate preview database.
2. Migrate and bind only the preview database, then turn on the preview entry.
3. Confirm only successful HTML counts, opt-out headers record nothing, assets bypass the
   Function, failures still serve pages, and request data is never logged.
4. Run maintenance, read only floored report views, and compare rendered privacy text to
   the configuration.
5. Create and migrate production while its site entry remains off.
6. Deploy code, routes, headers, and privacy text together. Bind production, then enable
   only that entry.
7. Verify one synthetic view and the kill switch. Use `N0CALL`, `N0TST`, and `FN31pr` for
   identity-like fixture values.

Never send preview traffic to production storage.

## Owner-only account checklist

The repository agent does not perform these Cloudflare and Doppler account changes.

- [ ] Create separate preview and production D1 databases in Cloudflare.
- [ ] Bind each database as `DB` only in its matching Pages environment.
- [ ] Apply migrations with a narrowly scoped D1 token, then reduce its scope.
- [ ] Keep account values and scoped tokens in Doppler, never in source or logs.
- [ ] Set `ANALYTICS_OFF=1`, `GEO_LEVEL`, and the bounded write timeout in preview.
- [ ] Select fail open so analytics cannot take down the site.
- [ ] Schedule idempotent roll-up and retention, and test them on preview data.
- [ ] If retained, enable Cloudflare Web Analytics and verify its beacon separately.
- [ ] Publish matching production privacy text before removing the site kill switch.
- [ ] Check account limits after launch and retain the tested kill-switch rollback.

