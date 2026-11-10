# Headline images

A headline (featured) image is optional. When a post has one, the site uses it
three ways from a single file: a hero below the title, a small thumbnail on the
Posts and Home cards, and the social card for sharing. A post without one shows
none of that and uses the default brand card.

The template is `layouts/_partials/featured-image.html`. The social card is
chosen in `layouts/_partials/head-meta.html` from the same front matter.

## Add one

1. Put the file in the post's folder and name it `featured.jpg`, `featured.png`
   or `featured.webp`. Only JPEG, PNG and WebP work.
2. Add to the front matter, and write the alt text yourself:

   ```yaml
   image: "featured.jpg"
   imageAlt: "A purple 3D-printed case with a small fan sitting on a mixer with glowing pads"
   build:
     publishResources: false
   ```

3. Build. The page now shows the hero below the title.

## What the site makes from it

| Use | How |
| --- | --- |
| Hero on the post | Resized WebP copies (480 and 800 pixels wide, quality 70) with `width`, `height`, `fetchpriority="high"` and no lazy loading, because it is the first image a reader sees. The original file is never served. |
| Card thumbnail | A 96 by 64 pixel crop (and a 192 by 128 copy for sharp screens), lazy loaded, with empty alt text. The title link beside it carries the meaning. |
| Social card | A JPEG of at most 1200 by 630 pixels, with its real size declared in the Open Graph tags. A transparent logo is flattened onto the site background color. |

## Rules

- `imageAlt` is required. A missing value or the `TODO alt text` placeholder
  fails the build, as does an image that is not a file in the post's folder or
  is not JPEG, PNG or WebP.
- A value that starts with `/` or `https://` is used for the social card only:
  no hero and no thumbnail.
- Set `build.publishResources: false` when the file is large. The page uses its
  resized copies, so the original should not ship; the budget check
  (`scripts/check-budget.py`) fails any image file over 300 KB in the build. A
  small file does not need it.
- Landscape images about 1200 pixels wide or more work best. The hero is capped
  in height and never cropped, so a logo or a square graphic is letterboxed on
  the dark surface instead of cut off.
- Remove EXIF and GPS data first. `scripts/check-image-metadata.py` fails the
  build otherwise. Keep the color profile on photos that have one.
- Like every image under `content/`, it needs a line in
  `brand/approved-assets.txt`. See [Images and alt text](Images-and-alt-text.md).

## Tests

`scripts/test-featured-image.sh` builds throwaway sites and asserts: a post with
`image` and `imageAlt` gets a hero below the title (not lazy, with dimensions and
alt), a thumbnail on the list page and its own social card; a post without one
gets none of those and the default card; and the build fails for a missing
`imageAlt`, a placeholder `imageAlt` and an image that is not in the bundle.
