# Discoteca

Personal record collection — a catalog of 1375+ albums enriched with data from Spotify, Last.fm, MusicBrainz, and Wikipedia.

**Live site:** [tomgc.github.io/discoteca](https://tomgc.github.io/discoteca/)

## What is this?

A single-file web app (`index.html`) that displays my personal music library as a browsable, filterable catalog. It's the musical sibling of [Cinemateca](https://github.com/tomgc/cinemateca) (my film collection).

The backend is a set of R scripts that import albums from Spotify, enrich them with metadata from Last.fm, MusicBrainz, and Wikipedia, and produce a `catalogo.json` that the frontend consumes.

## Features

- **Grid of album covers** with artist, year, and category badges
- **Category system**: Masterpiece ◆ / Great ● / Good ○ / Dismiss ×
- **Filters**: genre, decade, category, free-text search
- **Featured album**: random highlight from the collection on each visit
- **"What should I listen to today?"**: tag-based random suggestion widget
- **Releases bar**: horizontal timeline of albums released on each day of the month
- **Album detail modal**: tracklist info, scrobble count, Spotify link, Wikipedia extract (for masterpieces), personal notes and tags
- **Offline-first editing**: category, notes, and custom tags saved to localStorage, exportable as JSON
- **Dark editorial aesthetic**: Playfair Display + Source Sans 3, dark surface, gold accents

## Data sources

| Source      | What it provides                                      | Auth required |
|-------------|-------------------------------------------------------|---------------|
| Spotify     | Albums, artwork, audio features, duration, track count | API key       |
| Last.fm     | Scrobbles, first scrobble date, genre tags             | API key       |
| MusicBrainz | Label, country, release type                           | None (1 req/s)|
| Wikipedia   | Introductory extract for masterpieces                  | None          |

## Project structure

```
├── index.html              ← Single-file web app (GitHub Pages)
├── datos/
│   ├── catalogo.json       ← Album data for the frontend
│   ├── catalogo_musica.csv ← Same data in CSV for R/Excel
│   ├── music_cache.json    ← Permanent cache (~30MB, not in repo)
│   └── correcciones_mb.json← Manual MusicBrainz corrections
├── utils.R                 ← Shared module (atomic cache, constants)
├── spotify.R               ← Import saved albums from Spotify
├── lastfm.R                ← Enrich with scrobbles and tags
├── musicbrainz.R           ← Enrich with label, country, type
├── construir.R             ← Generate catalogo.json + CSV
├── deduplicar.R            ← Detect and mark duplicate albums
├── wikipedia.R             ← Enrich masterpieces with Wikipedia
├── .Renviron.ejemplo       ← API credentials template
├── .gitignore
└── v1/, v2/, v3/           ← Archived versions of index.html
```

## Setup (if you want to run the R scripts)

### 1. Clone and configure credentials

```bash
git clone https://github.com/tomgc/discoteca.git
cd discoteca
cp .Renviron.ejemplo .Renviron
# Edit .Renviron with your API keys
```

### 2. Install R dependencies

```r
install.packages(c("httr2", "jsonlite", "dplyr", "purrr", "stringr", "here", "janitor", "readr"))
```

### 3. Run the pipeline

```r
readRenviron(".Renviron")
source("spotify.R")        # Import albums from Spotify
source("lastfm.R")         # Enrich with Last.fm scrobbles
source("musicbrainz.R")    # Enrich with label/country
source("construir.R")      # Generate catalogo.json + CSV
```

### 4. Optional: deduplication and Wikipedia

```r
source("deduplicar.R")     # Detect duplicates (diagnostic mode)
source("wikipedia.R")      # Fetch Wikipedia for masterpieces
source("construir.R")      # Regenerate after changes
```

## Design principles

All code follows [`principios_desarrollo.md`](principios_desarrollo.md) — a set of 13 engineering principles covering immutability, reproducibility, idempotency, atomic writes, modularity, and more.

## Tech stack

- **Frontend**: Vanilla HTML/CSS/JS, zero dependencies, Google Fonts
- **Backend**: R (tidyverse), httr2 for API calls
- **Hosting**: GitHub Pages
- **Data format**: JSON (Git-friendly, sorted keys, indented)

## License

Personal project. Not intended for redistribution.
