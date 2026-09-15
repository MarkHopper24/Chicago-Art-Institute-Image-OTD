





































<!-- ARTWORK_START -->

## Under the Wave off Kanagawa (Kanagawa oki nami ura), also known as The Great Wave, from the series "Thirty-Six Views of Mount Fuji (Fugaku sanjurokkei)"

<p align="center">

<img src="https://www.artic.edu/iiif/2/05cd1ba7-67d1-96c5-0e78-2eb4114b65e7/full/1200,/0/default.jpg" width="600" height="auto"/>

</p>

**Artist:** Katsushika Hokusai 葛飾 北斎, Japanese, 1760-1849

**Date:** 1830/33

**Medium:** Color woodblock print; oban

[View this artwork at the Art Institute of Chicago](https://www.artic.edu/artworks/77333)

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
