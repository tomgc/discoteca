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

**Guía maestra:** `~/Desktop/principios_desarrollo_v3.md` (global del usuario).
**Detalle del proyecto:** `docs/principios_desarrollo.md` (numeración P1-P13 propia).

### Aplicación al proyecto

- **C.1/C.3/C.4 (P1, P3, P4)** — Inmutabilidad, idempotencia, escritura atómica:
  toda escritura JSON pasa por `guardar_json`/`guardar_cache` (`utils.R`). Nunca
  `write_json` directo. El `music_cache.json` solo se aumenta, nunca se reescribe
  destructivamente.
- **C.8 (P8)** — Validación: `validar_cache()` y `validar_catalogo()` en `utils.R`.
  Llamar `validar_catalogo()` desde cualquier script que produzca el catálogo final.
- **C.10 (P10)** — Claves JSON ordenadas alfabéticamente: aplicar `ordenar_keys()`
  antes de `guardar_json` para artefactos publicados (catalogo.json).
- **C.11 (P11)** — Constantes con nombre en `utils.R` (rutas, rate limits, categorías).
  Sin números mágicos.
- **C.12** — Verificación de paquetes: cada R script empieza con
  `source(utils.R); instalar_si_falta(...)` antes de `library()`.
- **C.13** — Logging: `cli_alert_info/success/warning/danger`. Resumen final.

### Excepciones declaradas (principios que NO aplican)

- **D estructura `data/raw/`, `scripts/`, `R/`, `qmd/`, `output/`**: el proyecto
  usa estructura plana (`datos/`, scripts en raíz). Los "raw data" viven en APIs
  remotas, no en disco; el `music_cache.json` cumple el rol de `data/processed/`.
  Reorganizar rompería paths cableados en `app.js` y rutas de GitHub Pages.
- **C.2 `set.seed()`**: no hay sampling/simulación en el pipeline. El
  `Math.random()` del frontend es UX (feature aleatorio), no análisis.
- **D.R Quarto**: no hay documentos, solo scripts ejecutables.
