# Images and alt text

An image that does not meet these rules cannot be published: the build fails
instead of shipping it. The rules live in code, in
`layouts/_markup/render-image.html`, and the checks that back them are in
`scripts/`.

## Add an image to a post

Put the file in the post's folder, next to `index.md`, and reference it with
Markdown:

```md
![A terminal showing failed login attempts grouped by hour](failed-logins.webp)
```

## What the render hook enforces

| Rule | What happens |
| --- | --- |
| Alt text is required | An empty alt fails the build. |
| The `TODO alt text` placeholder | The WordPress converter writes it where the old image had no alt. It is allowed in a draft and fails the build on a published page. |
| Bundle images only | The file must sit in the page's own folder. A remote image, or one from elsewhere in the site, fails the build. |
| Format | JPEG, PNG or WebP. Anything else fails. WebP is preferred. |

For an accepted image the hook writes `width` and `height` (so the layout does
not shift), `loading="lazy"`, `decoding="async"` and, when the file is wide
enough, a `srcset` of 480, 800 and 1200 pixel copies with the page column as
`sizes`. The largest version served in the page is capped at 800 pixels wide.

## Writing good alt text

- Describe what the image shows and why it is in the post. Do not start with
  "image of".
- A screenshot: say which window and what it proves.
- If the image is only decoration, leave it out.
- Keep it to a sentence or two. The alt text is what a listener gets instead of
  the picture.

## Other checks an image meets

- **Metadata.** `scripts/check-image-metadata.py` runs inside
  `scripts/check-output.sh` and fails the build for EXIF, XMP or IPTC data (GPS
  lives in EXIF) in any published image. Strip it first, for example with
  `exiftool -all= photo.jpg`.
- **Size.** `scripts/check-budget.py` fails an image over 120 KB that a page
  loads, and any image file over 300 KB in the build. Resize before you commit.
  See [Build checks and budgets](Build-checks-and-budgets.md).
- **The asset manifest.** `scripts/check-brand-assets.sh` fails the build when an
  image under `content/` is not listed in `brand/approved-assets.txt` with its
  sha256, a source and a note that someone looked at it. Add the line in the same
  pull request: `path | sha256 | source | verification`. A changed file needs its
  hash updated. The file's own header explains the format.
- **Private content.** Crop or blur screen names, addresses, serial numbers and
  device labels before you add a photo or screenshot.
- **Rights.** Third-party photos keep their owners' terms. List them in
  `BRAND.md` and do not add one without the right to publish it.

## Where this is tested

- `scripts/test-archetype.sh` publishes a post with an image and checks the
  output passes, then removes the alt text and the placeholder and checks the
  build fails each time.
- `scripts/test-check-output.sh` holds the negative cases for the output checks.
- `tools/wxr2hugo/webp.py` shrinks images during a WordPress migration, see
  [Migrating from WordPress](Migrating-from-WordPress.md).

The optional headline image has its own rules: [Headline images](Headline-images.md).
