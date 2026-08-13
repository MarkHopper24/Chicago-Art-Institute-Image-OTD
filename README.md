











<!-- ARTWORK_START -->

## Adam and Eve

<p align="center">

<img src="https://www.artic.edu/iiif/2/905bea59-a6d2-52ef-90ee-cec035ecdf85/full/1200,/0/default.jpg" width="600" height="auto"/>

</p>

**Artist:** Rembrandt van Rijn, Dutch, 1606-1669

**Date:** 1638

**Medium:** Etching on ivory laid paper

[View this artwork at the Art Institute of Chicago](https://www.artic.edu/artworks/70019)

<!-- ARTWORK_END -->























<h2>What is this repository?</h2>

A self-updating, PowerShell-based repository that surfaces a different public-domain artwork
from the [Art Institute of Chicago](https://www.artic.edu) every day, formatted for the
[TRMNL](https://usetrmnl.com) e-ink display. It ships layouts for both the **TRMNL OG** and
**TRMNL X** devices.

Every day a scheduled [GitHub Actions](https://docs.github.com/actions) workflow runs
[`scripts/ArtInstituteImageOfTheDay.ps1`](scripts/ArtInstituteImageOfTheDay.ps1) on a
`windows-latest` runner. The script:

1. Queries the [Art Institute of Chicago API](https://api.artic.edu/docs/) for public-domain
   artworks that have an image.
2. Deterministically selects one artwork for the current UTC day, so every device shows the
   same piece and it rotates automatically each day.
3. Downloads the artwork's [IIIF](https://iiif.io) image in two sizes: `artwork.jpg` (tuned for
   the 800x480 OG display) and `artwork_x.jpg` (larger, for the higher-resolution X display).
4. Writes [`ArtInstituteImageOfTheDay.json`](ArtInstituteImageOfTheDay.json) with the artwork's
   metadata.

The workflow then commits the refreshed JSON, images, and README back to the repository.

## How to use it with TRMNL

1. In TRMNL, create a **Private Plugin** with strategy **Polling**.
2. Set the polling URL to the raw JSON:
   ```
   https://raw.githubusercontent.com/MarkHopper24/Art-Institute-Image-of-the-Day/refs/heads/main/ArtInstituteImageOfTheDay.json
   ```
3. Paste the markup from the [`templates`](templates) folder into the matching layout fields:

   | Device | Layout | File |
   | ------ | ------ | ---- |
   | OG | Full | [`templates/trmnlFullLayout.html`](templates/trmnlFullLayout.html) |
   | OG | Half Horizontal | [`templates/trmnlHalfHorizontal.html`](templates/trmnlHalfHorizontal.html) |
   | OG | Half Vertical | [`templates/trmnlHalfVertical.html`](templates/trmnlHalfVertical.html) |
   | OG | Quadrant | [`templates/trmnlQuadrant.html`](templates/trmnlQuadrant.html) |
   | X | Full | [`templates/trmnlFullLayoutX.html`](templates/trmnlFullLayoutX.html) |

The JSON fields (`Title`, `Artist`, `DateDisplay`, `Medium`, `Dimensions`, `Department`,
`CreditLine`, `ArtworkURL`, and the image URLs) are available as Liquid variables in the markup.

## Running it locally

```powershell
.\scripts\ArtInstituteImageOfTheDay.ps1
.\scripts\ReadMeUpdater.ps1
```

## Attribution

Artwork images and metadata are provided by the [Art Institute of Chicago](https://www.artic.edu)
under a [Creative Commons Zero (CC0)](https://creativecommons.org/publicdomain/zero/1.0/)
designation. Only public-domain works are selected. See the
[Art Institute of Chicago API documentation](https://api.artic.edu/docs/) and
[terms](https://www.artic.edu/terms) for details.
