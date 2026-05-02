# PROMPT_DISCOTECA.md — Brief del Proyecto

## Qué es Discoteca

Catálogo personal de discos. Una plataforma web que muestra mi biblioteca musical como una grilla navegable de portadas, con filtros, clasificación personal y datos enriquecidos de múltiples fuentes.

Es el hermano musical de [Cinemateca](https://github.com/tomgc/cinemateca) (mi catálogo de películas). Misma filosofía: un solo `index.html`, cero dependencias de framework, estética oscura editorial, datos estáticos servidos desde GitHub Pages.

## Por qué existe

Spotify guarda mis discos pero no me deja organizarlos a mi manera. Last.fm registra lo que escucho pero no me deja curar una colección. Quiero un lugar propio donde mis discos vivan clasificados, enriquecidos con datos de varias fuentes, y donde pueda explorar mi biblioteca como si fuera una tienda de discos.

## Fuentes de datos

| Fuente      | Qué aporta                                     | Autenticación     |
|-------------|-------------------------------------------------|-------------------|
| Spotify     | Álbumes guardados, artwork, duración, tracks    | OAuth 2.0 (API key) |
| Last.fm     | Scrobbles, primer scrobble, tags de género       | API key            |
| MusicBrainz | Sello discográfico, país, tipo de release        | Ninguna (1 req/s)  |
| Wikipedia   | Extracto introductorio para masterpieces         | Ninguna            |

## Stack técnico

- **Backend:** R (tidyverse, httr2, jsonlite, cli). Scripts independientes que se corren en secuencia.
- **Frontend:** HTML/CSS/JS vanilla en un solo archivo `index.html`. Sin frameworks, sin build step.
- **Hosting:** GitHub Pages (estático).
- **Datos:** JSON como formato principal. CSV como respaldo para Excel/R.
- **Tipografías:** Playfair Display (títulos) + Source Sans 3 (cuerpo). Google Fonts.
- **Estética:** Fondo oscuro, acentos dorados, inspiración editorial/tienda de discos.

## Sistema de categorías

| Categoría      | Significado                   | Icono |
|----------------|-------------------------------|-------|
| `null`         | Sin clasificar                | —     |
| `"good"`       | Buen disco                    | ○     |
| `"great"`      | Disco notable                 | ●     |
| `"masterpiece"`| Obra maestra                  | ◆     |
| `"descartado"` | Fuera de la colección (oculto)| ×     |

Las categorías se editan desde el modal en la web y se guardan en `localStorage`. Se pueden exportar como JSON e importar al caché vía `construir.R`.

## Features del frontend

- **Grilla de portadas** con artista, año y badge de categoría
- **Filtros:** género, década, categoría, búsqueda libre
- **Toggle Collection / All:** oculta descartados por defecto
- **Álbum destacado:** selección aleatoria en cada visita (excluye descartados)
- **"What should I listen to today?":** tags clickeables → sugerencia aleatoria
- **Releases bar:** barra horizontal con releases por día del mes, navegación mensual
- **Modal de detalle:** botones de categoría, "Open in Spotify", sección Wikipedia (masterpieces), notas y tags personales
- **Edición offline:** categoría, notas y tags se guardan en localStorage
- **Exportar JSON:** descarga las ediciones para re-importar al caché

## Arquitectura del backend

Cada script es independiente y se corre en secuencia desde la consola de R:

```r
readRenviron(".Renviron")
source("spotify.R")        # 1. Importar álbumes desde Spotify
source("lastfm.R")         # 2. Enriquecer con scrobbles y tags
source("musicbrainz.R")    # 3. Enriquecer con sello, país, tipo
source("construir.R")      # 4. Generar catalogo.json + CSV
```

Scripts auxiliares (se corren según necesidad):
```r
source("deduplicar.R")     # Detectar y marcar duplicados
source("wikipedia.R")      # Wikipedia para masterpieces
```

### Flujo de datos

```
Spotify API → music_cache.json ← Last.fm API
                    ↑
              MusicBrainz API
                    ↑
              Wikipedia API (solo masterpieces)
                    │
                    ↓
              construir.R
                    │
              ┌─────┴─────┐
              ↓            ↓
        catalogo.json   catalogo_musica.csv
              ↓
         index.html (GitHub Pages)
```

### Caché permanente

`music_cache.json` (~30MB) es el corazón del proyecto. Solo crece, nunca se borra (P1 — inmutabilidad). Cada script agrega datos a los álbumes existentes sin tocar lo que ya está. Si un script se interrumpe, el progreso queda guardado (P3 — checkpointing). Las escrituras usan patrón atómico write-to-temp → rename (P4).

## Principios de desarrollo

Todo el código sigue `principios_desarrollo.md` — 13 principios que cubren inmutabilidad, reproducibilidad, idempotencia, escritura atómica, modularidad, portabilidad, validación, resiliencia, y más.

## Instrucciones para Claude

- Explicar cada decisión antes de escribir código. Sin cajas negras.
- R para todo el backend (no Python).
- HTML single-file para la web. Sin frameworks.
- Seguir estrictamente `principios_desarrollo.md`.
- Dar los archivos listos para descargar.
- Avanzar en bloques incrementales verificables.
- Preguntar antes de asumir cosas sobre mis cuentas de Spotify/Last.fm.

## URLs

- **Repo:** https://github.com/tomgc/discoteca
- **Live:** https://tomgc.github.io/discoteca/
- **Proyecto hermano:** https://github.com/tomgc/cinemateca
