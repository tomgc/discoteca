# Estado del Proyecto Discoteca — Mayo 2026 (v4)

## Resumen ejecutivo

Catálogo personal de discos con 1375 álbumes importados desde Spotify, enriquecidos con Last.fm (scrobbles, tags) y MusicBrainz (sello, país, tipo). Backend en R completo. Frontend v3: header minimalista, releases bar horizontal (fusión del sidebar vertical + today banner), diseño visual refinado. Publicado en GitHub Pages.

## Changelog v3 → v4

### Reorganización del proyecto

- Documentación movida a `docs/` (ESTADO_PROYECTO, principios_desarrollo, PROMPT_DISCOTECA)
- Scripts one-time movidos a `archivo/fixes/` (6 scripts de fix/diagnóstico)
- Transiciones entre sesiones movidas a `archivo/transiciones/`
- Respaldos por versión en `archivo/v1/` a `archivo/v4/`
- `.gitignore` creado: excluye `.Renviron`, `music_cache.json`, `archivo/`, `.DS_Store`
- `.Renviron.ejemplo` creado como plantilla de credenciales
- `PROMPT_DISCOTECA.md` creado: brief completo del proyecto reconstruido
- Credenciales removidas de documentación pública (rotación pendiente)

## Estructura de archivos

```
~/Desktop/Discoteca/
│
├── .Renviron                      ← Credenciales API (en .gitignore)
├── .Renviron.ejemplo              ← Plantilla sin credenciales
├── .gitignore
├── README.md                      ← Documentación para GitHub (raíz)
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
│── FRONTEND ──────────────────────────────────────────────
├── index.html                     ← Plataforma web v3
│
│── DATOS ─────────────────────────────────────────────────
├── datos/
│   ├── music_cache.json           ← Caché permanente (1375 álbumes, ~30MB, en .gitignore)
│   ├── catalogo.json              ← Datos para la web (generado por construir.R)
│   ├── catalogo_musica.csv        ← Para Excel/R (generado por construir.R)
│   ├── correcciones_mb.json       ← Tabla de correcciones manuales MusicBrainz
│   └── ediciones_web.json         ← Exportado desde la web (si existe)
│
│── DOCUMENTACIÓN ─────────────────────────────────────────
├── docs/
│   ├── ESTADO_PROYECTO.md         ← Este archivo
│   ├── PROMPT_DISCOTECA.md        ← Brief original del proyecto
│   └── principios_desarrollo.md   ← Principios que rigen todo el código
│
│── ARCHIVO (solo local, excluido de GitHub) ──────────────
├── archivo/
│   ├── fixes/                     ← Scripts one-time ya corridos
│   ├── transiciones/              ← Documentos de transición entre sesiones
│   └── v1/ v2/ v3/ v4/           ← Respaldos por versión
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

Almacenadas en `.Renviron` (excluido de GitHub por `.gitignore`).
Ver `.Renviron.ejemplo` para la plantilla.

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

## Pendientes

- Conteo de Sello en resumen de construir.R muestra NA (bug cosmético del reporte, no de los datos)
- Clasificar discos con el nuevo sistema de categorías
- Correr wikipedia.R cuando haya más masterpieces clasificados
- Refactor: unificar uso de utils.R en todos los scripts (spotify.R, lastfm.R y musicbrainz.R tienen funciones duplicadas locales en vez de usar el módulo compartido)

## Notas técnicas

- `here::here()` requiere `install.packages("here")`
- `httr2` requerido para wikipedia.R: `install.packages("httr2")`
- Spotify rate limit es agresivo en Development mode
- MusicBrainz exige 1 req/s y User-Agent obligatorio
- Last.fm permite ~4 req/s
- Wikipedia permite ~200 req/s, usamos 0.5s por cortesía
- El frontend migra automáticamente datos con formato viejo (rating/favorito → categoria) tanto del JSON como de localStorage
