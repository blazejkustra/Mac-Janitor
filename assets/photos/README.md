# Photos

The hero photos behind the landing page. All of them are under the
[Unsplash License](https://unsplash.com/license): free for commercial use, no attribution required.

| Files | What | Photographer | Source |
| --- | --- | --- | --- |
| `mist-*` | Mist over a larch and pine forest in the Dolomites | Vadim Sherbakov | https://unsplash.com/photos/green-trees-covering-with-fog-during-daytime-NQSWvyVRIJk |
| `glacier-*` | A glacier in Greenland, from above | Tobias Keller | https://unsplash.com/photos/an-aerial-view-of-a-snow-covered-mountain-range-HzSLh5zV42s |
| `aurora-*` | Northern lights over a line of trees | Vincent Guth | https://unsplash.com/photos/silhouette-of-trees-near-aurora-borealis-at-night-62V7ntlKgL8 |
| `ridge-*` | Wind blowing snow off a mountain ridge | Alessio Soggetti | https://unsplash.com/photos/snow-covered-mountains-under-clear-sky-during-daytime-IuSemNxGS88 |
| `moss-*` | Moss over the lava fields near Kirkjubæjarklaustur, Iceland | Adi Albulescu | https://unsplash.com/photos/lush-green-moss-covers-undulating-volcanic-landscape-JrdKqV3A1dg |
| `river-*` | Braided river in Iceland, from above | Karsten Winegeart | https://unsplash.com/photos/a-river-delta-flows-forming-beautiful-patterns-qd2FKfmZtqY |
| `coast-*` | Waves on a black sand beach in Bali, from above | Alexey Marchenko | https://unsplash.com/photos/an-aerial-view-of-the-ocean-with-waves-1l3bVHDWkpU |

`scripts/site-photos.sh` builds each one from the original download: a 2560 x 1600 crop for wide screens
and a 1080 x 1620 crop for phones, each as AVIF, WebP and JPEG. The colours are left as shot; the page
darkens them behind the text. The landing page uses `mist` and switches with `?bg=` and any other name
above, for example `?bg=glacier`.
