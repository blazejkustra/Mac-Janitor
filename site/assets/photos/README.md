# Photos

The hero photos behind the landing page.

| Files | What | Photographer | Source | Licence |
| --- | --- | --- | --- | --- |
| `glacier-*` | A glacier in Greenland, from above | Tobias Keller | https://unsplash.com/photos/an-aerial-view-of-a-snow-covered-mountain-range-HzSLh5zV42s | [Unsplash License](https://unsplash.com/license): free for commercial use, no attribution required |
| `ice-*` | A crevassed glacier with a calm snow field, from above (the `?v=ice` variant) | Unconfirmed | Supplied as a 1672 x 941 image; original not yet found | Unconfirmed: check before this variant ships as the default |

`scripts/site-photos.sh` builds them from the originals (`glacier.jpg`, `ice.png`): a wide crop for
wide screens and a 2:3 crop for phones, each as AVIF, WebP and JPEG. The glacier gets 2560 x 1600 and
1080 x 1620; the ice photo stays at its own resolution (1672 x 941 and 720 x 1080). The colours are
left as shot; the page darkens the glacier behind the text. The same script renders `demo-poster.jpg`
and the social card `og.jpg` (from `scripts/og.html`) on top of the glacier.
