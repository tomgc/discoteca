# Estado del Proyecto Discoteca — Mayo 2026 (v2)

## Resumen ejecutivo

Catálogo personal de discos con 1375 álbumes importados desde Spotify, enriquecidos con Last.fm (scrobbles, tags) y MusicBrainz (sello, país, tipo). Backend en R completo. Frontend HTML reescrito en v2: interfaz en inglés, sistema de categorías implementado, calendario compacto, código reorganizado según principios de desarrollo.

## Estructura de archivos

```
~/Desktop/Discoteca/
│
├── .Renviron                      ← Credenciales API (NO subir a GitHub)
├── .Renviron.ejemplo              ← Plantilla sin credenciales
├── .gitignore
│
│── BACKEND R ─────────────────────────────────────────────
├── utils.R                        ← Módulo compartido (caché atómico, constantes, validación)
├── spotify.R                      ← Importar álbumes guardados de Spotify
├── lastfm.R                       ← Enriquecer con scrobbles y tags
├── musicbrainz.R                  ← Enriquecer con sello, país, tipo
├── construir.R                    ← Generar catalogo.json + CSV
│
│── FIXES ONE-TIME (ya corridos, no necesitan re-correrse) ─
├── fix_lastfm_errors.R
├── fix_musicbrainz_titulos.R
├── fix_musicbrainz_v2.R
├── fix_musicbrainz_manual.R
├── diagnostico_musicbrainz_v2.R
│
│── FRONTEND ──────────────────────────────────────────────
├── index.html                     ← Plataforma web v2
│
│── DATOS ─────────────────────────────────────────────────
├── datos/
│   ├── music_cache.json           ← Caché permanente (1375 álbumes, ~30MB)
│   ├── catalogo.json              ← Datos para la web (generado por construir.R)
│   ├── catalogo_musica.csv        ← FALLA al generar — pendiente de fix
│   ├── correcciones_mb.json       ← Tabla de correcciones manuales MusicBrainz
│   └── ediciones_web.json         ← Exportado desde la web (si existe)
│
│── DOCUMENTACIÓN ─────────────────────────────────────────
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

### MusicBrainz — irrecuperables (41 no encontrados)
Artistas de nicho (Rubick, Jessie Robins), compilaciones raras (Buddy Rich),
releases muy nuevos (Cut Copy — Still See Love), formatos que MusicBrainz no indexa.
La web funciona sin estos datos.

### Sello NA/vacío: 40 álbumes
Principalmente artistas chilenos/independientes (Ases Falsos, Fother Muckers, Marineros).
MusicBrainz los tiene registrados pero sin sello discográfico.

### Sello [no label]: 12 álbumes
Releases independientes/autopublicados (Cory Wong, CRX, Angine de Poitrine).
Correcto — realmente no tienen sello.

## Sistema de categorías

Reemplaza el sistema anterior de rating (1-5 estrellas) + favorito (booleano).

| Valor          | Significado                     | Icono en UI |
|----------------|---------------------------------|-------------|
| `null`         | Sin clasificar (unrated)        | —           |
| `"good"`       | Buen disco                      | ○ Good      |
| `"great"`      | Disco notable                   | ● Great     |
| `"masterpiece"`| Obra maestra                    | ◆ Masterpiece|
| `"descartado"` | Fuera de la colección (oculto)  | × Dismiss   |

### Estado de implementación:
- ✅ `utils.R`: constantes CATEGORIAS_VALIDAS definidas
- ✅ `spotify.R`: nuevos álbumes se crean con `categoria = NULL`
- ✅ `construir.R`: migración automática de rating/favorito → categoria
- ✅ `index.html`: sistema de categorías completo (botones en modal, filtro, toggle Collection/All)
- ✅ `index.html`: migración automática de ediciones viejas en localStorage
- ⚠️ `construir.R`: el CSV falla (error "differing number of rows") — pendiente

## Frontend v2 — Cambios realizados

### Modelo de datos
- `rating`/`favorito` reemplazados por `categoria` en todo el JS
- Migración automática de ediciones viejas en localStorage (rating/favorito → categoria)
- `exportJSON()` genera claves ordenadas alfabéticamente (P10)

### Interfaz
- Idioma: todo en inglés (UI, calendario, placeholders)
- Toolbar: filtro por Category (en vez de Rating), toggle Collection/All (en vez de Todos/Hall of Fame)
- Modal: 4 botones de categoría (Masterpiece/Great/Good/Dismiss) en vez de estrellas + Hall of Fame
- Cards: icono de categoría, descartados atenuados al 40%
- Feature: excluye descartados, prioriza álbumes clasificados
- Calendario: celdas compactas 30×28px, tooltip desplegable hacia abajo
- Banner "hoy": limitado a 3 releases con indicador "+N more"

### Principios de desarrollo aplicados al frontend
- P5 Modularidad: JS reorganizado en secciones lógicas con comentarios de bloque
- P6 Nomenclatura: todas las funciones en inglés consistente (render, openModal, getFiltered, etc.)
- P8 Validación: validateCatalog() verifica campos obligatorios post-carga
- P9 Resiliencia: escapeHtml() en todo innerHTML, safeGetItem/safeSetItem para localStorage
- P10 Git-friendly: exportJSON con claves ordenadas
- P11 Constantes: CONFIG, CATEGORIES, UI, MONTHS, DAYS al inicio del script
- P13 Logging: mensajes [Discoteca] en consola (carga, validación, migración, errores)

## Credenciales API

```
SPOTIFY_CLIENT_ID=665e575529d24acfa84ad6f190752100
SPOTIFY_CLIENT_SECRET=7ecae0f7feaf40babb05a3f2e2f7f5cb
LASTFM_API_KEY=6b61b8fe8d1699850cd0788b2bea5859
LASTFM_USER=Mr_EdGe
# MusicBrainz: no requiere credenciales
```

Spotify Redirect URI: `http://127.0.0.1:1410/`
Spotify app en Development mode.

## Orden de ejecución de scripts

### Flujo diario (agregar nuevos discos):
```r
readRenviron(".Renviron")  # Solo si recién abriste R
source("spotify.R")         # Descarga solo los nuevos
source("lastfm.R")          # Solo procesa los que no tienen datos
source("musicbrainz.R")     # Solo procesa los que no tienen datos
source("construir.R")       # Regenera catalogo.json + CSV
```

### Fixes one-time (ya corridos, no necesitan re-correrse):
```r
source("fix_lastfm_errors.R")
source("fix_musicbrainz_titulos.R")
source("fix_musicbrainz_v2.R")
source("fix_musicbrainz_manual.R")
```

## Pendientes

### Prioritarios
1. **CSV falla en `construir.R`** — error "differing number of rows", probablemente `tags_propios` vacío
2. **Verificar que `construir.R` exporte `categoria`** — si aún exporta rating/favorito, el frontend lo migra automáticamente pero lo correcto es que el backend genere el formato nuevo
3. **Link al álbum** — agregar URL de Spotify como link clickeable en el modal

### Fase futura
4. **Wikipedia para Masterpieces** — ficha expandida con info de Wikipedia para álbumes categoría "masterpiece". API gratuita, sin auth. Script: `wikipedia.R` (por crear)
5. **"What should I listen to today?"** — basado en tags propios y tags de Last.fm. Dejado para fase posterior.

## Notas técnicas

- `here::here()` requiere `install.packages("here")`
- Spotify rate limit es agresivo en Development mode — el script aborta si pide >5 min
- MusicBrainz exige 1 req/s y User-Agent obligatorio
- Last.fm permite ~4 req/s
- El `.Renviron` se carga al inicio de R, no en tiempo real. Usar `readRenviron(".Renviron")` si no lo detecta
- El frontend migra automáticamente datos con formato viejo (rating/favorito → categoria) tanto del JSON como de localStorage
