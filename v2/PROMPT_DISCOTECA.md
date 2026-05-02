# Proyecto: Discoteca — Catálogo de Discos Favoritos

## Contexto

Soy Tomás (tomgc en GitHub). Trabajo principalmente con R (Positron), Excel/PowerBI, y GitHub Pages. No tengo experiencia en Python. Me gusta entender qué hace cada línea de código antes de ejecutarla, y prefiero analogías para conceptos nuevos.

Ya tengo un proyecto similar funcionando: **Cinemateca** (catálogo de películas), alojado en `https://github.com/tomgc/cinemateca` y servido en GitHub Pages. La arquitectura de ese proyecto es:

- Scripts de R para escaneo + enriquecimiento vía API (TMDb)
- Caché local en JSON (`tmdb_cache.json`) para no re-consultar la API
- Plataforma web en un solo `index.html` que lee un `catalogo.json`
- Cambios desde la web se guardan en localStorage + botón "Exportar JSON"
- Estética oscura tipo cinemateca con tipografía editorial (Playfair Display + Source Sans 3)

## Qué quiero construir

Un catálogo personal de mis **discos/álbumes favoritos**, con la misma filosofía pero adaptado a música. Lo llamo **Discoteca**.

## Fuentes de datos

No tengo archivos locales — mis datos están en:

1. **Last.fm** — Mi perfil tiene historial de escuchas (scrobbles), artistas más escuchados, álbumes top. La API de Last.fm es gratuita con API key.
2. **Spotify** — Tengo playlists, álbumes guardados, y la API ofrece datos ricos: audio features (energía, tempo, valencia/mood), géneros, popularidad, artwork de alta resolución.

El script de R debería conectarse a ambas APIs para importar mi biblioteca y enriquecer los datos.

## Caché permanente

Igual que Cinemateca, necesito un archivo de caché local (`music_cache.json`) que acumule los metadatos de cada álbum. Solo se agregan datos, nunca se borran. Así puedo re-correr el enriquecimiento sin abusar de las APIs.

## Estructura del catálogo (metadatos por álbum)

Básicos: artista, nombre del álbum, año, artwork (URL), sello discográfico, géneros/tags.

De escucha: scrobbles totales (Last.fm), fecha de primer scrobble (cuándo lo descubrí).

De Spotify: popularidad, duración total, número de tracks, audio features promedio del álbum (energy, valence, danceability, acousticness, instrumentalness, tempo).

Personales (editables desde la web):
- **Rating personal** (1-5 estrellas)
- **Favorito de favoritos** (flag booleano, tipo "Hall of Fame")
- **Notas personales** (texto libre, para anotar recuerdos, contexto, por qué me gusta)
- **Tags propios** (etiquetas custom: "para programar", "roadtrip", "melancolía nocturna")

## Plataforma web

Misma filosofía que Cinemateca pero adaptada a música:

- **Grilla de portadas** con artista, álbum, año, rating
- **Filtros**: por artista, género, década, rating personal, favoritos, tags propios
- **Detalle modal**: portada grande, tracklist, audio features visualizadas (radar chart o barras), datos de escucha, notas personales
- **Sistema de descubrimiento tipo "¿Qué escucho hoy?"**: basado en mood → mapear a audio features de Spotify (valence alta = alegre, energy baja = relajado, etc.)
- **Agregar manualmente**: buscar en Spotify/Last.fm desde la web, agregar al catálogo
- **Editar desde la web**: rating, favorito, notas, tags — todo con localStorage + exportar JSON
- **Toggle "Hall of Fame" / "Todos"**: similar al Pendientes/Colección de Cinemateca

## Estética

Mantener el mismo lenguaje visual de Cinemateca (oscuro, editorial, dorado) pero con identidad propia. Que se sienta como el hermano musical de la cinemateca. Mismo approach: un solo `index.html`, cero dependencias de framework, Google Fonts, todo inline.

## Estructura del proyecto

```
~/Desktop/Discoteca/
├── importar.R              ← importa desde Last.fm y Spotify
├── enriquecimiento.R       ← enriquece con metadatos de ambas APIs  
├── index.html              ← plataforma web
├── datos/
│   ├── music_cache.json    ← caché permanente de metadatos
│   ├── catalogo.json       ← datos para la web
│   └── catalogo_musica.csv ← referencia para R/Excel
```

GitHub repo: `https://github.com/tomgc/discoteca`
GitHub Pages: `https://tomgc.github.io/discoteca/`

## Instrucciones para Claude

- Explícame cada decisión antes de escribir código
- Muéstrame qué hace cada parte del script, sin cajas negras
- Usa R para todo el backend (no Python)
- Un archivo HTML single-file para la web
- Caché local que solo crece, nunca se borra
- Pregúntame antes de asumir cosas sobre mi cuenta de Last.fm o Spotify
- Dame los archivos listos para descargar
- Todas las rutas apuntan a ~/Desktop/Discoteca/
