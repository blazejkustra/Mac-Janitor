# Photos

The hero photo behind the landing page, under the
[Unsplash License](https://unsplash.com/license): free for commercial use, no attribution required.

| Files | What | Photographer | Source |
| --- | --- | --- | --- |
| `glacier-*` | A glacier in Greenland, from above | Tobias Keller | https://unsplash.com/photos/an-aerial-view-of-a-snow-covered-mountain-range-HzSLh5zV42s |

`scripts/site-photos.sh` builds it from the original download: a 2560 x 1600 crop for wide screens
and a 1080 x 1620 crop for phones, each as AVIF, WebP and JPEG. The colours are left as shot; the page
darkens them behind the text. The same script renders `demo-poster.jpg` and the social card `og.jpg`
(from `scripts/og.html`) on top of this photo.
