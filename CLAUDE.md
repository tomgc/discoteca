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

- Después de tocar `utils.R` o cualquier script con tests → correr `Rscript tests/testthat.R` (107 expectaciones).
- Después de tocar scripts del pipeline → si tiene sentido y hay caché, regenerar `catalogo.json` con `Rscript run_all.R --only construir`.
- Después de tocar frontend (`assets/styles.css` o `assets/app.js`) → incrementar `CACHE_VERSION` en `sw.js` (`discoteca-vN`) para que el SW invalide el shell cache. Verificar en preview (`preview_start` con server `discoteca`, puerto 4323).
- Commits en español, conventional commits. Push directo a `main`.

### Patrones obligatorios en R

- **Acceso a campos opcionales del caché**: usar `safe_str()` / `safe_num()` de `utils.R`, NO `%||%` solo. `%||%` captura NULL pero NO `list()` vacía ni `NA` — formas en que jsonlite serializa campos opcionales. Pasar list() a operaciones que esperan escalar produce errores en runtime (`cat != "x"` da `logical(0)`, `vapply(..., numeric(1))` falla, etc.).
- **Tests de funciones puras**: scripts con `main()` al final usan el guard `if (!isTRUE(getOption("discoteca.load_only"))) main()`. Los tests setean esa opción con `withr::local_options()` para sourcear sin ejecutar el pipeline.
- **Antes de escribir JSON publicado**: pasar por `ordenar_keys()` para diffs git limpios.

### Convenciones del frontend

- **Búsqueda accent-insensitive**: usar `normalizeForSearch()` (NFD + remove combining marks + lowercase) para que "carino" matchee "Cariño". No solo `toLowerCase()`.
- **Cards del grid**: deben ser `role="button" tabindex="0"` con `aria-label` descriptivo, handler de `Enter`/`Space`. Imágenes con `alt=""` (decorativas, la card ya tiene nombre accesible).
- **Modales/overlays**: `role="dialog" aria-modal="true" aria-labelledby="..."`. Cerrar con Esc + click fuera. Manejar foco con guard de "modal abierto" en shortcuts globales.
- **OG/Twitter meta tags**: actualizar dinámicamente en `setUrlAlbum()` para Slack/Discord/Telegram. Twitter/Facebook usan los defaults estáticos del `<head>`.

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
