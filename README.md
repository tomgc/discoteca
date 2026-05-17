# Discoteca

Personal record collection — a catalog of 1375+ albums enriched with data from Spotify, Last.fm, MusicBrainz, and Wikipedia.

**Live site:** [tomgc.github.io/discoteca](https://tomgc.github.io/discoteca/)

## What is this?

A static web app that displays my personal music library as a browsable, filterable catalog. It's the musical sibling of [Cinemateca](https://github.com/tomgc/cinemateca) (my film collection).

The backend is a set of R scripts that import albums from Spotify, enrich them with metadata from Last.fm, MusicBrainz, and Wikipedia, and produce a `catalogo.json` that the frontend consumes. The frontend is vanilla HTML/CSS/JS, installable as a PWA, with offline support via service worker.

## Why it exists

Spotify keeps my saved albums but doesn't let me organize them my way. Last.fm logs what I listen to but doesn't let me curate a collection. I wanted a place of my own where my records live classified, enriched with data from multiple sources, and where I can browse my library as if it were a record store.

## Features

- **Grid of album covers** with artist, year, and category badges
- **Category system**: Masterpiece ◆ / Great ● / Good ○ / Dismiss ×
- **Filters**: genre, decade, category, free-text search
- **Featured album**: random highlight from the collection on each visit
- **"What should I listen to today?"**: tag-based random suggestion widget
- **Releases bar**: horizontal timeline of albums released on each day of the month
- **Album detail modal**: tracklist embed, scrobble count, Spotify link, Wikipedia extract (for masterpieces), personal notes and tags
- **Stats panel**: top artists, distribution by decade/genre/category, listening totals
- **Triage mode**: keyboard-shortcut batch classification of unrated albums
- **Share by URL**: `?album=<id>` opens the album modal directly; dynamic OpenGraph tags for Slack/Discord/Telegram previews
- **PWA**: installable, works offline (cached app shell + catalog, stale-while-revalidate)
- **Offline-first editing**: category, notes, and custom tags saved to localStorage, exportable as JSON
- **Accessible**: keyboard-navigable grid, ARIA labels, focus-visible rings, respects `prefers-reduced-motion`
- **Dark editorial aesthetic**: Playfair Display + Source Sans 3, dark surface, gold accents

## Data sources

| Source      | What it provides                                       | Auth required |
|-------------|--------------------------------------------------------|---------------|
| Spotify     | Albums, artwork, audio features, duration, track count | API key       |
| Last.fm     | Scrobbles, first scrobble date, genre tags             | API key       |
| MusicBrainz | Label, country, release type                           | None (1 req/s)|
| Wikipedia   | Introductory extract for masterpieces                  | None          |

## Project structure

```
├── index.html                  ← App shell (HTML structure)
├── assets/
│   ├── styles.css              ← All styles
│   ├── app.js                  ← All client logic
│   └── icon.svg
├── sw.js                       ← Service worker (PWA, offline)
├── manifest.webmanifest        ← PWA manifest
│
├── datos/
│   ├── catalogo.json           ← Album data for the frontend (sorted keys)
│   ├── catalogo_musica.csv     ← Same data in CSV for R/Excel
│   ├── music_cache.json        ← Permanent cache (~1.6MB, NOT tracked — see "Local cache" below)
│   ├── correcciones_mb.json    ← Manual MusicBrainz corrections
│   └── ediciones_web.json      ← Personal edits exported from the web
│
├── utils.R                     ← Shared module (atomic I/O, validation, constants)
├── spotify.R                   ← Import saved albums from Spotify
├── lastfm.R                    ← Enrich with scrobbles and tags
├── musicbrainz.R               ← Enrich with label, country, type
├── wikipedia.R                 ← Enrich masterpieces with Wikipedia extract
├── deduplicar.R                ← Detect and mark duplicate albums
├── construir.R                 ← Generate catalogo.json + CSV
├── run_all.R                   ← Pipeline entry point (CLI)
├── importar_ediciones.R        ← Import web-exported edits from ~/Downloads
├── obtener_refresh_token.R     ← One-shot OAuth helper for CI
├── restaurar_cache.R           ← Restore music_cache from latest CI artifact
│
├── tests/
│   ├── testthat.R              ← Test runner
│   └── testthat/test-utils.R   ← Tests for utils.R (67 expectations)
│
├── .github/workflows/
│   ├── ci.yml                  ← Validate JSON + run tests + lint R on every push
│   └── pipeline.yml            ← Scheduled refresh (Sun 09:00 UTC) → PR
│
├── docs/
│   ├── principios_desarrollo.md ← Engineering principles (P1-P13)
│   └── PROMPT_DISCOTECA.md      ← Project brief
│
├── CLAUDE.md                   ← Maintenance instructions for AI assistants
├── .Renviron.ejemplo           ← API credentials template
└── .gitignore
```

## Setup

### 1. Clone and configure credentials

```bash
git clone https://github.com/tomgc/discoteca.git
cd discoteca
cp .Renviron.ejemplo .Renviron
# Edit .Renviron with your Spotify and Last.fm API keys
```

### 2. Run the pipeline

The single entry point handles dependency installation, environment loading, and stage sequencing:

```bash
Rscript run_all.R                    # full pipeline
Rscript run_all.R --skip spotify     # skip a stage
Rscript run_all.R --only construir   # only regenerate catalogo.json
Rscript run_all.R --dedup            # include deduplication
```

The first run takes ~70 min (1375 albums × 3 req/s through MusicBrainz). Subsequent runs only process new albums (cache is incremental).

### Local cache

`datos/music_cache.json` is the permanent, append-only cache (~1.6MB). It's **not tracked** in the repo. The pipeline generates and updates it locally. If you lose your local copy:

```bash
Rscript restaurar_cache.R   # downloads latest cache from CI artifacts
```

CI restores it automatically from the most recent successful run's artifact before each run.

### 3. Run tests (optional, after changing `utils.R`)

```bash
Rscript tests/testthat.R
```

## Continuous integration

- **`ci.yml`** runs on every push: validates `catalogo.json`, checks HTML asset references exist, runs the testthat suite, and lints R scripts.
- **`pipeline.yml`** runs weekly (Sun 09:00 UTC) and on demand:
  1. Restores `music_cache.json` from the most recent successful run's artifact (incremental)
  2. Runs the full pipeline against the live APIs
  3. Compresses the cache and uploads it as a 90-day artifact (recoverable via `restaurar_cache.R`)
  4. Opens a PR with the refreshed `catalogo.json` + `catalogo_musica.csv`

  Requires GitHub secrets: `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, `SPOTIFY_REFRESH_TOKEN`, `LASTFM_API_KEY`, `LASTFM_USER`. Run `obtener_refresh_token.R` once locally to get the refresh token.

## Design principles

The R code follows the 13 engineering principles documented in [`docs/principios_desarrollo.md`](docs/principios_desarrollo.md): immutability of source data, reproducibility, idempotency with checkpointing, atomic writes, modularity, integrity validation, resilience with exponential backoff, and more.

## Tech stack

- **Frontend**: Vanilla HTML/CSS/JS, zero npm dependencies, Google Fonts, service worker
- **Backend**: R (tidyverse, httr2), no `renv` (small set of stable dependencies)
- **Hosting**: GitHub Pages, GitHub Actions for CI
- **Data format**: JSON with alphabetically sorted keys for clean git diffs

## License

Personal project. Not intended for redistribution.
