# Estado del Proyecto Discoteca — Mayo 2026 (v3)

## Resumen ejecutivo

Catálogo personal de discos con 1375 álbumes importados desde Spotify, enriquecidos con Last.fm (scrobbles, tags) y MusicBrainz (sello, país, tipo). Backend en R completo. Frontend v3: header minimalista, releases bar horizontal (fusión del sidebar vertical + today banner), diseño visual refinado. Publicado en GitHub Pages.

## Changelog v2 → v3

### Frontend (`index.html`)

**Header minimalista:**
- Centrado con "DISCOTECA" en mayúsculas a 2.4rem → barra izquierda "Discoteca" a 1.1rem
- Subtítulo pasa de debajo del título a inline con separador `·`
- Padding reducido de 2.5rem/1.5rem a 0.55rem (~40px vs ~100px)
- `text-transform: uppercase` eliminado

**Releases bar (fusión sidebar + today banner):**
- Eliminados: `<aside class="sidebar">` (columna izquierda 260px) y `<div class="today-banner">`
- Nuevo: `<div class="releases-bar">` — barra horizontal debajo del toolbar
- Navegación ◂ Mes Año ▸ a la izquierda, divider vertical, items scrolleables
- Day labels como chips horizontales: fondo `--accent-dim`, texto blanco, altura 32px (alineado con portadas)
- Día actual destacado con fondo `--accent` y font-weight 600
- Auto-scroll al día de hoy en el mes actual
- Layout principal: 2 columnas (`260px 1fr`) → columna única

**Código JS:**
- `renderReleaseList()` + `renderTodayBanner()` → `renderReleasesBar()` (función unificada)
- Eliminados: `maxBannerReleases`, `calendarTitle`, `bannerLabel` de CONFIG/UI
- CSS limpiado: clases `.today-banner-*`, `.sidebar`, `.release-day-*`, `.release-item-*` eliminadas

**Sin cambios:** modal, grilla, feature, categorías, "What should I listen to today?", exportar JSON.

## Estructura de archivos

```
~/Desktop/Discoteca/
│
├── .Renviron                      ← Credenciales API (NO subir a GitHub)
├── .Renviron.ejemplo              ← Plantilla sin credenciales
├── .gitignore
├── README.md                      ← Documentación del proyecto para GitHub
│
│── BACKEND R ─────────────────────────────────────────────
├── utils.R                        ← Módulo compartido (caché atómico, constantes, validación)
├── spotify.R                      ← Importar álbumes guardados de Spotify
├── lastfm.R                       ← Enriquecer con scrobbles y tags
├── musicbrainz.R                  ← Enriquecer con sello, país, tipo
├── construir.R                    ← Generar catalogo.json + CSV
├── deduplicar.R                   ← Detectar y marcar álbumes duplicados
├── wikipedia.R                    ← Enriquecer masterpieces con Wikipedia
│
│── FIXES ONE-TIME (ya corridos, no necesitan re-correrse) ─
├── fix_lastfm_errors.R
├── fix_musicbrainz_titulos.R
├── fix_musicbrainz_v2.R
├── fix_musicbrainz_manual.R
├── diagnostico_musicbrainz_v2.R
│
│── FRONTEND ──────────────────────────────────────────────
├── index.html                     ← Plataforma web v3
│
│── DATOS ─────────────────────────────────────────────────
├── datos/
│   ├── music_cache.json           ← Caché permanente (1375 álbumes, ~30MB)
│   ├── catalogo.json              ← Datos para la web (generado por construir.R)
│   ├── catalogo_musica.csv        ← Para Excel/R (generado por construir.R)
│   ├── correcciones_mb.json       ← Tabla de correcciones manuales MusicBrainz
│   └── ediciones_web.json         ← Exportado desde la web (si existe)
│
│── VERSIONES ANTERIORES ──────────────────────────────────
├── v1/                            ← Frontend v1 (original)
├── v2/                            ← Frontend v2 (rewrite: categorías, inglés, sidebar)
├── v3/                            ← Frontend v3 (header minimal, releases bar horizontal)
│
│── DOCUMENTACIÓN ─────────────────────────────────────────
├── README.md                      ← Documentación para GitHub
├── principios_desarrollo.md       ← Principios que rigen todo el código
├── PROMPT_DISCOTECA.md            ← Brief original del proyecto
└── ESTADO_PROYECTO.md             ← Este archivo
```

## Estado de los datos

| Fuente      | Completos | Parciales       | Sin datos              |
|-------------|-----------|-----------------|------------------------|
| Spotify     | 1375/1375 | 0               | 0                      |
| Last.fm     | 1375/1375 | 0               | 0                      |
| MusicBrainz | ~1282     | ~52 (sin sello) | 41 (no encontrados)    |

### Duplicados
84 álbumes marcados como duplicados por `deduplicar.R`. Son re-releases, remasters o versiones regionales de Spotify. Se conserva el que tiene más scrobbles; los demás quedan como `descartado` con `_duplicado_de` en el caché. No se borran (P1 — inmutabilidad).

## Sistema de categorías

| Valor          | Significado                     | Icono en UI |
|----------------|---------------------------------|-------------|
| `null`         | Sin clasificar (unrated)        | —           |
| `"good"`       | Buen disco                      | ○ Good      |
| `"great"`      | Disco notable                   | ● Great     |
| `"masterpiece"`| Obra maestra                    | ◆ Masterpiece|
| `"descartado"` | Fuera de la colección (oculto)  | × Dismiss   |

### Estado actual de clasificación:
- 3 masterpieces, 1 great (migrados del formato viejo rating/favorito)
- 84 descartados (duplicados)
- ~1287 sin clasificar

## Frontend v3 — Features implementadas

### Infraestructura (invisible al usuario)
- CONFIG, CATEGORIES, UI, MONTHS, DAYS como constantes al inicio (P11)
- validateCatalog() valida campos obligatorios post-carga (P8)
- safeGetItem/safeSetItem protegen localStorage (P9)
- escapeHtml() en todo innerHTML con datos dinámicos (P9)
- log()/warn() con prefijo [Discoteca] en consola (P13)
- Migración automática de ediciones viejas en localStorage (rating/favorito → categoria)
- exportJSON() con claves ordenadas (P10)
- Funciones renombradas a inglés consistente (P6)

### Interfaz
- Idioma: todo en inglés
- Header: minimalista, alineado a la izquierda, "Discoteca · Personal record collection"
- Toolbar: filtro por Category, toggle Collection/All
- Releases bar: barra horizontal con navegación mensual y releases scrolleables
- Modal: 4 botones de categoría, botón "Open in Spotify", sección "About this album" (Wikipedia)
- Cards: icono de categoría, descartados atenuados 40%
- Feature: excluye descartados, prioriza clasificados
- Widget "What should I listen to today?": tags clickeables → sugerencia aleatoria

## Credenciales API

```
SPOTIFY_CLIENT_ID=665e575529d24acfa84ad6f190752100
SPOTIFY_CLIENT_SECRET=7ecae0f7feaf40babb05a3f2e2f7f5cb
LASTFM_API_KEY=6b61b8fe8d1699850cd0788b2bea5859
LASTFM_USER=Mr_EdGe
# MusicBrainz: no requiere credenciales
# Wikipedia: no requiere credenciales
```

## Orden de ejecución de scripts

### Flujo diario (agregar nuevos discos):
```r
readRenviron(".Renviron")
source("spotify.R")
source("lastfm.R")
source("musicbrainz.R")
source("construir.R")
```

### Deduplicación (después de agregar muchos discos):
```r
source("deduplicar.R")         # modo diagnóstico primero
# editar APLICAR_CAMBIOS <- TRUE si se ve bien
source("deduplicar.R")         # aplicar
source("construir.R")          # regenerar catálogo
```

### Wikipedia (después de clasificar masterpieces):
```r
source("wikipedia.R")
source("construir.R")
```

## Pendientes menores

- Conteo de Sello en resumen de construir.R muestra NA (bug cosmético del reporte, no de los datos)
- Clasificar discos con el nuevo sistema de categorías
- Correr wikipedia.R cuando haya más masterpieces clasificados

## Notas técnicas

- `here::here()` requiere `install.packages("here")`
- `httr2` requerido para wikipedia.R: `install.packages("httr2")`
- Spotify rate limit es agresivo en Development mode
- MusicBrainz exige 1 req/s y User-Agent obligatorio
- Last.fm permite ~4 req/s
- Wikipedia permite ~200 req/s, usamos 0.5s por cortesía
- El frontend migra automáticamente datos con formato viejo (rating/favorito → categoria) tanto del JSON como de localStorage
