# Photos

The hero photos behind the landing page. All three are under the
[Unsplash License](https://unsplash.com/license): free for commercial use, no attribution required.

| Files | What | Photographer | Source |
| --- | --- | --- | --- |
| `dunes-*` | Dunes at Sossusvlei, Namibia, from above | Andrew Svk | https://unsplash.com/photos/an-aerial-view-of-a-desert-with-sand-dunes-sFrBry-NkKw |
| `river-*` | Braided river in Iceland, from above | Karsten Winegeart | https://unsplash.com/photos/a-river-delta-flows-forming-beautiful-patterns-qd2FKfmZtqY |
| `coast-*` | Waves on a black sand beach in Bali, from above | Alexey Marchenko | https://unsplash.com/photos/an-aerial-view-of-the-ocean-with-waves-1l3bVHDWkpU |

`scripts/site-photos.sh` builds each one from the original download: a 2560 x 1600 crop for wide screens
and a 1080 x 1620 crop for phones, each as AVIF, WebP and JPEG. The colours are left as shot; the page
darkens them behind the text. The landing page uses `dunes` and switches with `?bg=river` or `?bg=coast`.
