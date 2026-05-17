# CLAUDE.md — Discoteca

Catálogo personal de discos. R en el backend, web estática en GitHub Pages.

## Arquitectura

- **Backend R**: `spotify.R` → `lastfm.R` → `musicbrainz.R` → `wikipedia.R` → `construir.R` (genera `datos/catalogo.json`)
- **Entrada única**: `Rscript run_all.R [--skip a,b] [--only x] [--dedup]`
- **Frontend**: `index.html` + `assets/styles.css` + `assets/app.js`. Sin frameworks.
- **PWA**: `sw.js` + `manifest.webmanifest`. Cache versionado en `sw.js` — al modificar shell assets, incrementar `CACHE_VERSION`.
- **Tests**: `Rscript tests/testthat.R` — correr después de tocar `utils.R`.
- **Importar ediciones del navegador**: `Rscript importar_ediciones.R` (busca en ~/Downloads).

## Datos

- `datos/catalogo.json` se commitea (es lo que sirve GitHub Pages).
- `datos/music_cache.json` NO se commitea (~30MB, en `.gitignore`).
- `datos/ediciones_web.json` se commitea (clasificaciones manuales del usuario).
- `.Renviron` NUNCA se commitea. Plantilla en `.Renviron.ejemplo`.

## Workflow

- Después de tocar `utils.R` → correr tests.
- Después de tocar scripts del pipeline → si tiene sentido y hay caché, regenerar `catalogo.json` con `Rscript run_all.R --only construir`.
- Después de tocar frontend → verificar en preview (`preview_start` con server `discoteca`, puerto 4323).
- Commits en español, conventional commits. Push directo a `main`.

## Cosas a NO hacer

- No reescribir `git history` para borrar las credenciales viejas del commit `90c2ff4` — están rotadas (o se rotarán), eso es lo que importa.
- No agregar dependencias JS al frontend. Vanilla es decisión arquitectónica.
- No usar `Sys.sleep` < 1s para MusicBrainz (rate limit estricto).
- No tocar `archivo/` ni `v1/` `v2/` `v3/` — son backups históricos solo locales.

## Principios

`docs/principios_desarrollo.md` rige el código. Los más invocados:
- **P4** — escritura atómica (siempre `guardar_json`/`guardar_cache` de `utils.R`, nunca `write_json` directo).
- **P11** — sin números mágicos, constantes en `utils.R`.
