// ============================================================================
// DISCOTECA — JavaScript
// ============================================================================
// Flujo: carga catalogo.json → aplica ediciones de localStorage → renderiza.
// Las ediciones (rating, favorito, notas, tags) se guardan en localStorage.
// "Exportar JSON" genera un archivo descargable con las ediciones.
// ============================================================================

// --- 1. CONFIGURACIÓN Y CONSTANTES (P11) -----------------------------------
// Todos los valores parametrizables viven aquí. Ningún string de UI ni
// número mágico debería aparecer suelto más abajo en el código.

const CONFIG = {
  dataFile: 'datos/catalogo.json',
  storageKey: 'discoteca_ediciones',
  storageVersion: 2,                             // versión del formato de ediciones
  requiredFields: ['id', 'artista', 'album'],
};

// Sistema de categorías (reemplaza rating + favorito)
const CATEGORIES = {
  masterpiece: { label: 'Masterpiece', icon: '◆', order: 1 },
  great:       { label: 'Great',       icon: '●', order: 2 },
  good:        { label: 'Good',        icon: '○', order: 3 },
  descartado:  { label: 'Dismiss',     icon: '×', order: 4 },
};
const VALID_CATEGORIES = Object.keys(CATEGORIES);

// Campos editables por el usuario desde la web
const EDITABLE_FIELDS = ['categoria', 'notas', 'tags_propios'];

// Textos de la interfaz (centralizados para futura traducción)
const UI = {
  subtitle:         'Personal record collection',
  searchPlaceholder:'Search artist, album, tag…',
  genreDefault:     'Genre',
  decadeDefault:    'Decade',
  categoryDefault:  'Category',
  toggleCollection: 'Collection',
  toggleAll:        'All',
  exportBtn:        'Export JSON',
  featureLabel:     'From the collection',
  emptyTitle:       'No results',
  emptyHint:        'Try changing the filters',
  tagsPlaceholder:  'Add tag and press Enter',
  tagsHint:         'Press Enter to add',
  notesPlaceholder: 'Your personal notes about this album…',
  yearsAgo:         (n) => `${n} year${n !== 1 ? 's' : ''} ago`,
  counterFormat:    (shown, total) => `${shown} / ${total}`,
};

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const DAYS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];


// --- 2. ESTADO DE LA APLICACIÓN ---------------------------------------------

let catalogo = [];
let ediciones = {};  // { id: { categoria, notas, tags_propios } }
let currentId = null;
let viewMode = 'collection';  // 'collection' (oculta descartados) | 'all'


// --- 3. FUNCIONES UTILITARIAS (P8, P9, P13) ---------------------------------

// P13 — Logging: mensajes de consola informativos para diagnóstico
function log(msg) { console.log(`[Discoteca] ${msg}`); }
function warn(msg) { console.warn(`[Discoteca] ${msg}`); }

// P8 — Validación: verifica campos obligatorios después de load el JSON
function validateCatalog(data) {
  let valid = 0;
  let issues = 0;
  data.forEach((item, i) => {
    const missing = CONFIG.requiredFields.filter(f => !item[f]);
    if (missing.length > 0) {
      warn(`Álbum índice ${i}: faltan campos [${missing.join(', ')}]`);
      issues++;
    } else {
      valid++;
    }
  });
  log(`Validación: ${valid} álbumes OK, ${issues} con campos faltantes`);
  return issues;
}

// P9 — Resiliencia: localStorage con protección contra errores
function safeGetItem(key) {
  try {
    return localStorage.getItem(key);
  } catch (e) {
    warn(`Error leyendo localStorage key "${key}": ${e.message}`);
    return null;
  }
}

function safeSetItem(key, value) {
  try {
    localStorage.setItem(key, value);
    return true;
  } catch (e) {
    warn(`Error escribiendo localStorage key "${key}": ${e.message}`);
    return false;
  }
}

// P9 — Resiliencia: escapar HTML para evitar inyección accidental
function escapeHtml(str) {
  if (typeof str !== 'string') return str;
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// --- CARGA -----------------------------------------------------------------

// Migración: convierte rating/favorito del formato viejo a categoria
// Misma lógica que construir.R aplica en el backend
function migrateToCategory(obj) {
  if (obj.categoria !== undefined) return; // ya migrado
  if (obj.favorito) {
    obj.categoria = 'masterpiece';
  } else if (obj.rating >= 4) {
    obj.categoria = 'great';
  } else if (obj.rating >= 2) {
    obj.categoria = 'good';
  } else {
    obj.categoria = null;
  }
  // Limpiar campos viejos
  delete obj.rating;
  delete obj.favorito;
}

async function load() {
  try {
    const resp = await fetch(CONFIG.dataFile);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    catalogo = await resp.json();
    log(`Catálogo cargado: ${catalogo.length} álbumes`);
  } catch (e) {
    warn(`Error cargando catálogo: ${e.message}`);
    catalogo = [];
  }

  // P8 — Validar integridad del catálogo
  validateCatalog(catalogo);

  // Migrar datos del catálogo si vienen con formato viejo
  catalogo.forEach(a => migrateToCategory(a));

  // Normalizar campos: jsonlite serializa NULL como {} (objeto vacío).
  // Lo convertimos a null/vacío para que el frontend lo trate uniformemente.
  // Afecta: categoria, primer_scrobble, sello, pais, notas, wikipedia_extract, wikipedia_url
  let normalizadas = 0;
  catalogo.forEach(a => {
    ['categoria', 'primer_scrobble', 'sello', 'pais', 'notas',
     'wikipedia_extract', 'wikipedia_url', 'fecha_lanzamiento'].forEach(campo => {
      if (a[campo] && typeof a[campo] === 'object') {
        a[campo] = (campo === 'categoria') ? null : '';
        normalizadas++;
      }
    });
  });
  if (normalizadas > 0) {
    log(`Normalizados ${normalizadas} campos ({} → null/vacío)`);
  }

  // Cargar ediciones de localStorage (P9 — con protección)
  const raw = safeGetItem(CONFIG.storageKey);
  if (raw) {
    try {
      ediciones = JSON.parse(raw);
    } catch (e) {
      warn(`Error parseando ediciones de localStorage: ${e.message}`);
      ediciones = {};
    }
  }

  // Migrar ediciones viejas en localStorage (una sola vez)
  let migradas = 0;
  Object.values(ediciones).forEach(ed => {
    if (ed.rating !== undefined || ed.favorito !== undefined) {
      migrateToCategory(ed);
      migradas++;
    }
  });
  if (migradas > 0) {
    log(`Migradas ${migradas} ediciones de rating/favorito → categoria`);
    safeSetItem(CONFIG.storageKey, JSON.stringify(ediciones));
  }

  // Aplicar ediciones al catálogo
  let edicionesAplicadas = 0;
  catalogo.forEach(a => {
    const ed = ediciones[a.id];
    if (ed) {
      EDITABLE_FIELDS.forEach(campo => {
        if (ed[campo] !== undefined) a[campo] = ed[campo];
      });
      edicionesAplicadas++;
    }
  });
  if (edicionesAplicadas > 0) {
    log(`Ediciones aplicadas desde localStorage: ${edicionesAplicadas} álbumes`);
  }

  populateFilters();
  render();
  renderFeature();
  renderListenToday();
  initCalendar();
  updateTriageButton();
  openFromUrl();
}

// --- URL SHARING ----------------------------------------------------------

function openFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const id = params.get('album');
  if (id && catalogo.some(a => a.id === id)) {
    openModal(id);
  }
}

function setUrlAlbum(id) {
  const url = new URL(window.location.href);
  if (id) url.searchParams.set('album', id);
  else url.searchParams.delete('album');
  history.replaceState(null, '', url.toString());
  updateMetadata(id ? catalogo.find(a => a.id === id) : null);
}

// Actualiza <title> y meta tags OG/Twitter al abrir/cerrar álbum.
// Solo es visible para scrapers que ejecutan JS (Slack, Discord, Telegram).
function updateMetadata(album) {
  const setMeta = (selector, value) => {
    const el = document.querySelector(selector);
    if (el) el.setAttribute(el.hasAttribute('property') ? 'content' : 'content', value);
  };

  if (album) {
    const title = `${album.album} — ${album.artista} · Discoteca`;
    const desc  = [album.anio, album.sello, album.generos?.slice(0, 3).join(', ')]
                    .filter(Boolean).join(' · ') || 'Personal record collection';
    document.title = title;
    setMeta('meta[property="og:title"]',       title);
    setMeta('meta[property="og:description"]', desc);
    setMeta('meta[property="og:image"]',       album.artwork_url || '');
    setMeta('meta[property="og:url"]',         window.location.href);
    setMeta('meta[name="twitter:title"]',      title);
    setMeta('meta[name="twitter:description"]',desc);
    setMeta('meta[name="twitter:image"]',      album.artwork_url || '');
  } else {
    document.title = 'Discoteca';
    setMeta('meta[property="og:title"]',       'Discoteca');
    setMeta('meta[property="og:description"]', 'Personal record collection');
    setMeta('meta[property="og:image"]',       'https://tomgc.github.io/discoteca/assets/icon.svg');
    setMeta('meta[property="og:url"]',         'https://tomgc.github.io/discoteca/');
    setMeta('meta[name="twitter:title"]',      'Discoteca');
    setMeta('meta[name="twitter:description"]','Personal record collection');
    setMeta('meta[name="twitter:image"]',      'https://tomgc.github.io/discoteca/assets/icon.svg');
  }
}

window.addEventListener('popstate', () => {
  const params = new URLSearchParams(window.location.search);
  const id = params.get('album');
  if (id) openModal(id);
  else if (currentId) closeModal();
});

// --- FILTROS ---------------------------------------------------------------

function populateFilters() {
  // Géneros
  const generos = new Set();
  catalogo.forEach(a => (a.generos || []).forEach(g => generos.add(g)));
  const selGen = document.getElementById('filter-genero');
  [...generos].sort().forEach(g => {
    const opt = document.createElement('option');
    opt.value = g; opt.textContent = g;
    selGen.appendChild(opt);
  });

  // Décadas
  const decadas = new Set();
  catalogo.forEach(a => {
    if (a.anio) decadas.add(Math.floor(a.anio / 10) * 10);
  });
  const selDec = document.getElementById('filter-decada');
  [...decadas].sort().forEach(d => {
    const opt = document.createElement('option');
    opt.value = d; opt.textContent = d + 's';
    selDec.appendChild(opt);
  });

  // Categorías
  const selCat = document.getElementById('filter-categoria');
  VALID_CATEGORIES.forEach(key => {
    const opt = document.createElement('option');
    opt.value = key;
    opt.textContent = CATEGORIES[key].label;
    selCat.appendChild(opt);
  });
}

function getFiltered() {
  const q = document.getElementById('search').value.toLowerCase().trim();
  const genero = document.getElementById('filter-genero').value;
  const decada = document.getElementById('filter-decada').value;
  const categoria = document.getElementById('filter-categoria').value;

  return catalogo.filter(a => {
    // Toggle Collection/All: Collection oculta descartados
    if (viewMode === 'collection' && a.categoria === 'descartado') return false;
    if (genero && !(a.generos || []).includes(genero)) return false;
    if (decada && Math.floor(a.anio / 10) * 10 !== parseInt(decada)) return false;
    if (categoria && a.categoria !== categoria) return false;
    if (q) {
      const blob = [
        a.artista, a.album, ...(a.generos || []),
        ...(a.tags_lastfm || []), ...(a.tags_propios || []),
        a.sello || '', a.notas || '', a.categoria || ''
      ].join(' ').toLowerCase();
      if (!blob.includes(q)) return false;
    }
    return true;
  });
}

// --- RENDER ----------------------------------------------------------------

function renderCategoryBadge(cat) {
  if (!cat || !CATEGORIES[cat]) return '';
  const c = CATEGORIES[cat];
  return `<span class="card-cat cat-${cat}">${c.icon}</span>`;
}

function render() {
  const filtrados = getFiltered();
  const grid = document.getElementById('grid');
  const empty = document.getElementById('empty');

  document.getElementById('counter').textContent =
    UI.counterFormat(filtrados.length, catalogo.length);

  if (filtrados.length === 0) {
    grid.innerHTML = '';
    empty.style.display = 'block';
    return;
  }
  empty.style.display = 'none';

  grid.innerHTML = filtrados.map(a => {
    const dimClass = a.categoria === 'descartado' ? ' card-dismissed' : '';
    const accName = `${a.artista} — ${a.album}${a.anio ? ' (' + a.anio + ')' : ''}`;
    return `
    <div class="card${dimClass}" data-id="${a.id}" role="button" tabindex="0" aria-label="${escapeHtml(accName)}">
      <div class="card-art">
        ${a.artwork_url
          ? `<img src="${a.artwork_url}" alt="" loading="lazy">`
          : `<div class="placeholder" aria-hidden="true">${escapeHtml(a.album.charAt(0))}</div>`
        }
        ${a.categoria === 'masterpiece' ? '<span class="card-fav" aria-hidden="true">◆</span>' : ''}
      </div>
      <div class="card-info">
        <div class="card-artist">${escapeHtml(a.artista)}</div>
        <div class="card-album">${escapeHtml(a.album)}</div>
        <div class="card-meta">
          <span class="card-year">${a.anio || ''}</span>
          ${renderCategoryBadge(a.categoria)}
        </div>
      </div>
    </div>`;
  }).join('');

  // Event listeners para abrir modal (click y teclado)
  grid.querySelectorAll('.card').forEach(card => {
    card.addEventListener('click', () => openModal(card.dataset.id));
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        openModal(card.dataset.id);
      }
    });
  });

  // Ocultar feature cuando hay filtros activos
  updateFeatureVisibility();
}

// --- MODAL -----------------------------------------------------------------

function openModal(id) {
  const a = catalogo.find(x => x.id === id);
  if (!a) return;
  currentId = id;

  // Artwork
  document.getElementById('modal-art').innerHTML = a.artwork_url
    ? `<img src="${a.artwork_url}" alt="${escapeHtml(a.album)}">`
    : '';

  // Info (textContent ya es seguro — no necesita escape)
  document.getElementById('modal-artist').textContent = a.artista;
  document.getElementById('modal-album').textContent = a.album;

  // Detalles
  const detalles = [];
  if (a.anio) detalles.push(`<span>${a.anio}</span>`);
  if (a.sello) detalles.push(`<span>${escapeHtml(a.sello)}</span>`);
  if (a.pais) detalles.push(`<span>${escapeHtml(a.pais)}</span>`);
  if (a.num_tracks) detalles.push(`<span>${a.num_tracks} tracks</span>`);
  if (a.duracion_total_min) detalles.push(`<span>${a.duracion_total_min} min</span>`);
  if (a.scrobbles > 0) detalles.push(`<span><strong>${a.scrobbles}</strong> scrobbles</span>`);
  if (a.primer_scrobble) detalles.push(`<span>desde ${escapeHtml(a.primer_scrobble)}</span>`);
  document.getElementById('modal-details').innerHTML = detalles.join('');

  // Link a Spotify
  const spotifyLink = document.getElementById('modal-spotify');
  if (a.spotify_url) {
    spotifyLink.href = a.spotify_url;
    spotifyLink.style.display = 'inline-flex';
  } else {
    spotifyLink.style.display = 'none';
  }

  // Tracklist via Spotify embed
  // Extrae el album ID de la URL (https://open.spotify.com/album/{id})
  // y carga un iframe embed compacto que muestra la lista de tracks
  const tracklistSection = document.getElementById('section-tracklist');
  const tracklistContainer = document.getElementById('modal-tracklist');
  const spotifyId = a.spotify_url ? a.spotify_url.split('/album/')[1] : '';
  if (spotifyId) {
    tracklistContainer.innerHTML =
      `<div class="modal-tracklist-embed">
        <iframe src="https://open.spotify.com/embed/album/${spotifyId}?theme=0"
          width="100%" height="352" frameborder="0"
          allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture"
          loading="lazy"></iframe>
      </div>`;
    tracklistSection.style.display = 'block';
  } else {
    tracklistContainer.innerHTML = '';
    tracklistSection.style.display = 'none';
  }

  // Wikipedia (para álbumes great/masterpiece con extracto)
  const wikiSection = document.getElementById('section-wikipedia');
  if (a.wikipedia_extract && a.wikipedia_extract.length > 0) {
    document.getElementById('modal-wikipedia').textContent = a.wikipedia_extract;
    const wikiLink = document.getElementById('modal-wiki-link');
    if (a.wikipedia_url) {
      wikiLink.href = a.wikipedia_url;
      wikiLink.style.display = 'inline-block';
    } else {
      wikiLink.style.display = 'none';
    }
    wikiSection.style.display = 'block';
  } else {
    wikiSection.style.display = 'none';
  }

  // Categoría (botones clickeables)
  renderCategoryButtons(a.categoria);

  // Tags Last.fm
  const tagsLfm = a.tags_lastfm || [];
  const sectionLfm = document.getElementById('section-tags-lastfm');
  if (tagsLfm.length > 0) {
    sectionLfm.style.display = 'block';
    document.getElementById('modal-tags-lastfm').innerHTML =
      tagsLfm.map(t => `<span class="tag">${escapeHtml(t)}</span>`).join('');
  } else {
    sectionLfm.style.display = 'none';
  }

  // Tags propios
  renderOwnTags(a.tags_propios || []);

  // Notas
  document.getElementById('modal-notes').value = a.notas || '';

  // Abrir
  document.getElementById('modal-overlay').classList.add('open');
  document.body.style.overflow = 'hidden';
  setUrlAlbum(id);
}

function renderCategoryButtons(currentCat) {
  const container = document.getElementById('modal-categories');
  container.innerHTML = VALID_CATEGORIES.map(key => {
    const c = CATEGORIES[key];
    const isActive = currentCat === key;
    const dismissClass = key === 'descartado' ? ' dismiss' : '';
    return `<button class="modal-cat-btn${dismissClass}${isActive ? ' active' : ''}" 
            data-cat="${key}">${c.icon} ${c.label}</button>`;
  }).join('');

  // Event listeners
  container.querySelectorAll('.modal-cat-btn').forEach(btn => {
    btn.addEventListener('click', () => setCategory(btn.dataset.cat));
  });
}

function setCategory(cat) {
  const a = catalogo.find(x => x.id === currentId);
  if (!a) return;
  // Click en la misma categoría = desclasificar (volver a null)
  a.categoria = (a.categoria === cat) ? null : cat;
  saveEdit(currentId, 'categoria', a.categoria);
  renderCategoryButtons(a.categoria);
  render();
}

function closeModal() {
  // Guardar notas al cerrar
  if (currentId) {
    const notas = document.getElementById('modal-notes').value;
    saveEdit(currentId, 'notas', notas);
  }
  currentId = null;
  document.getElementById('modal-overlay').classList.remove('open');
  document.body.style.overflow = '';
  setUrlAlbum(null);

  // Si estamos en triage, refrescar el batch (pudo haberse clasificado desde el modal)
  if (triageActive) {
    renderTriageBatch();
    updateTriageCounter();
  }
}

function renderOwnTags(tags) {
  document.getElementById('modal-tags-own').innerHTML =
    tags.map((t, i) => `<span class="tag tag-own">${escapeHtml(t)} <span style="cursor:pointer;margin-left:3px" data-idx="${i}">&times;</span></span>`).join('');

  // Borrar tag al clickear la X
  document.querySelectorAll('#modal-tags-own [data-idx]').forEach(el => {
    el.addEventListener('click', (e) => {
      e.stopPropagation();
      const a = catalogo.find(x => x.id === currentId);
      if (!a) return;
      const idx = parseInt(el.dataset.idx);
      a.tags_propios.splice(idx, 1);
      saveEdit(currentId, 'tags_propios', [...a.tags_propios]);
      renderOwnTags(a.tags_propios);
    });
  });
}

function addTag(e) {
  if (e.key !== 'Enter') return;
  const input = e.target;
  const val = input.value.trim();
  if (!val) return;

  const a = catalogo.find(x => x.id === currentId);
  if (!a) return;
  if (!a.tags_propios) a.tags_propios = [];
  if (!a.tags_propios.includes(val)) {
    a.tags_propios.push(val);
    saveEdit(currentId, 'tags_propios', [...a.tags_propios]);
    renderOwnTags(a.tags_propios);
  }
  input.value = '';
}

// --- FEATURE PRESENTATION --------------------------------------------------
// Muestra un disco aleatorio como "pieza destacada" al entrar.
// Cambia cada vez que recargas la página.

function renderFeature() {
  if (catalogo.length === 0) {
    document.getElementById('feature').style.display = 'none';
    return;
  }

  // Elegir disco: excluir descartados, priorizar los que tienen categoría
  const candidatos = catalogo.filter(a => a.categoria !== 'descartado');
  if (candidatos.length === 0) {
    document.getElementById('feature').style.display = 'none';
    return;
  }
  const clasificados = candidatos.filter(a => a.categoria);
  const pool = clasificados.length > 0 ? clasificados : candidatos;
  const a = pool[Math.floor(Math.random() * pool.length)];

  const featureEl = document.getElementById('feature');
  featureEl.style.display = 'flex';
  featureEl.onclick = () => openModal(a.id);

  // Artwork
  document.getElementById('feature-art').innerHTML = a.artwork_url
    ? `<img src="${a.artwork_url}" alt="${escapeHtml(a.album)}">`
    : '';

  // Info (textContent ya es seguro)
  document.getElementById('feature-album').textContent = a.album;
  document.getElementById('feature-artist').textContent = a.artista;

  // Meta (incluye categoría si tiene)
  const metaParts = [a.anio, a.sello, a.num_tracks ? a.num_tracks + ' tracks' : '']
    .filter(Boolean);
  if (a.categoria && CATEGORIES[a.categoria]) {
    metaParts.push(CATEGORIES[a.categoria].icon + ' ' + CATEGORIES[a.categoria].label);
  }
  document.getElementById('feature-meta').textContent = metaParts.join(' · ');

  // Notas (si tiene)
  const notesEl = document.getElementById('feature-notes');
  if (a.notas) {
    notesEl.textContent = '« ' + a.notas + ' »';
    notesEl.style.display = 'block';
  } else {
    notesEl.style.display = 'none';
  }

  // Tags propios
  const tagsEl = document.getElementById('feature-tags');
  if (a.tags_propios && a.tags_propios.length > 0) {
    tagsEl.innerHTML = a.tags_propios
      .map(t => `<span class="tag tag-own">${escapeHtml(t)}</span>`).join('');
  } else {
    tagsEl.innerHTML = '';
  }
}

// Ocultar feature y listen-today cuando hay búsqueda activa
function updateFeatureVisibility() {
  const q = document.getElementById('search').value.trim();
  const genero = document.getElementById('filter-genero').value;
  const decada = document.getElementById('filter-decada').value;
  const categoria = document.getElementById('filter-categoria').value;
  const hasFilter = q || genero || decada || categoria || viewMode === 'all';

  document.getElementById('feature').style.display = hasFilter ? 'none' : 'flex';
  document.getElementById('listen-today').style.display = hasFilter ? 'none' : 'block';
}

// --- "WHAT SHOULD I LISTEN TO TODAY?" ----------------------------------------
// Muestra tags populares como botones. Click en uno → sugiere un disco aleatorio
// de la colección que tenga ese tag. Usa tags de Last.fm y tags propios.

function renderListenToday() {
  if (catalogo.length === 0) {
    document.getElementById('listen-today').style.display = 'none';
    return;
  }

  // Recolectar tags y contar frecuencia (excluir descartados)
  const tagCount = {};
  catalogo.forEach(a => {
    if (a.categoria === 'descartado') return;
    const allTags = [...(a.tags_lastfm || []), ...(a.tags_propios || [])];
    allTags.forEach(t => {
      const key = t.toLowerCase();
      if (!tagCount[key]) tagCount[key] = { label: t, count: 0 };
      tagCount[key].count++;
    });
  });

  // Ordenar por frecuencia y tomar los top 12
  const sorted = Object.values(tagCount)
    .filter(t => t.count >= 3)  // mínimo 3 álbumes con ese tag
    .sort((a, b) => b.count - a.count)
    .slice(0, 12);

  // Mezclar para variedad (shuffle parcial)
  for (let i = sorted.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [sorted[i], sorted[j]] = [sorted[j], sorted[i]];
  }
  const displayed = sorted.slice(0, 8);

  const container = document.getElementById('listen-today-tags');
  container.innerHTML = displayed.map(t =>
    `<span class="listen-today-tag" data-tag="${escapeHtml(t.label)}">${escapeHtml(t.label)}</span>`
  ).join('');

  // Event listeners
  container.querySelectorAll('.listen-today-tag').forEach(btn => {
    btn.addEventListener('click', () => suggestAlbum(btn.dataset.tag));
  });
}

function suggestAlbum(tag) {
  const tagLower = tag.toLowerCase();
  const matches = catalogo.filter(a => {
    if (a.categoria === 'descartado') return false;
    const allTags = [...(a.tags_lastfm || []), ...(a.tags_propios || [])]
      .map(t => t.toLowerCase());
    return allTags.includes(tagLower);
  });

  const result = document.getElementById('listen-today-result');
  if (matches.length === 0) {
    result.classList.remove('visible');
    return;
  }

  const a = matches[Math.floor(Math.random() * matches.length)];
  result.innerHTML = `
    ${a.artwork_url ? `<img src="${a.artwork_url}" alt="${escapeHtml(a.album)}">` : ''}
    <div class="listen-today-result-info">
      <div class="listen-today-result-album">${escapeHtml(a.album)}</div>
      <div class="listen-today-result-meta">${escapeHtml(a.artista)} · ${a.anio}</div>
    </div>`;
  result.classList.add('visible');
  result.onclick = () => openModal(a.id);
}

// --- PERSISTENCIA ----------------------------------------------------------

function saveEdit(id, campo, valor) {
  if (!ediciones[id]) ediciones[id] = {};
  ediciones[id][campo] = valor;
  safeSetItem(CONFIG.storageKey, JSON.stringify(ediciones));
}

function exportJSON() {
  // Genera un array con todos los álbumes que tienen ediciones
  const exportData = catalogo
    .filter(a => ediciones[a.id])
    .map(a => {
      const obj = { id: a.id };
      // P10 — Claves ordenadas alfabéticamente para diffs Git limpios
      EDITABLE_FIELDS.forEach(campo => {
        if (a[campo] !== undefined) obj[campo] = a[campo];
      });
      return obj;
    });

  // P10 — Claves ordenadas en el JSON exportado
  const jsonStr = JSON.stringify(exportData, Object.keys(exportData[0] || {}).sort(), 2);
  const blob = new Blob([jsonStr], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = 'ediciones_web.json';
  link.click();
  URL.revokeObjectURL(url);
}

// --- EVENTOS ---------------------------------------------------------------

document.getElementById('search').addEventListener('input', render);
document.getElementById('filter-genero').addEventListener('change', render);
document.getElementById('filter-decada').addEventListener('change', render);
document.getElementById('filter-categoria').addEventListener('change', render);

document.getElementById('btn-collection').addEventListener('click', () => {
  viewMode = 'collection';
  document.getElementById('btn-collection').classList.add('active');
  document.getElementById('btn-collection').setAttribute('aria-pressed', 'true');
  document.getElementById('btn-all').classList.remove('active');
  document.getElementById('btn-all').setAttribute('aria-pressed', 'false');
  render();
});
document.getElementById('btn-all').addEventListener('click', () => {
  viewMode = 'all';
  document.getElementById('btn-all').classList.add('active');
  document.getElementById('btn-all').setAttribute('aria-pressed', 'true');
  document.getElementById('btn-collection').classList.remove('active');
  document.getElementById('btn-collection').setAttribute('aria-pressed', 'false');
  render();
});

document.getElementById('modal-share').addEventListener('click', async () => {
  if (!currentId) return;
  const url = window.location.href;
  try {
    await navigator.clipboard.writeText(url);
    const btn = document.getElementById('modal-share');
    btn.classList.add('copied');
    btn.textContent = '✓';
    setTimeout(() => {
      btn.classList.remove('copied');
      btn.textContent = '⎘';
    }, 1200);
  } catch (e) {
    warn(`No se pudo copiar: ${e.message}`);
  }
});

document.getElementById('modal-close').addEventListener('click', closeModal);
document.getElementById('modal-overlay').addEventListener('click', (e) => {
  if (e.target === e.currentTarget) closeModal();
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeModal();
});

document.getElementById('modal-tags-input').addEventListener('keydown', addTag);
document.getElementById('btn-export').addEventListener('click', exportJSON);

// ============================================================================
// TRIAGE MODE — Clasificación rápida de álbumes
// ============================================================================
// Muestra lotes de 8 discos sin clasificar. Click para seleccionar,
// luego asignar categoría con botones o atajos de teclado:
//   1 = Good, 2 = Great, 3 = Masterpiece, X = Dismiss, S = Skip
//   → = Next batch, Esc = Exit triage
// ============================================================================

const TRIAGE = {
  batchSize: 10,
  keyMap: {
    '1': 'good',
    '2': 'great',
    '3': 'masterpiece',
    'x': 'descartado',
  }
};

let triageActive = false;
let triagePool = [];      // todos los álbumes sin clasificar
let triageOffset = 0;     // posición actual en el pool
let triageBatch = [];     // lote actual (máx 8)
let triageSelected = null; // id del álbum seleccionado

function getUnclassified() {
  return catalogo.filter(a => {
    // jsonlite serializa NULL como {} (objeto vacío) — no es un string válido
    const cat = a.categoria;
    if (!cat) return true;                          // null, undefined, ""
    if (typeof cat === 'object') return true;        // {} de jsonlite
    if (!VALID_CATEGORIES.includes(cat)) return true; // valor inválido
    return false;
  });
}

function enterTriage() {
  triageActive = true;
  triagePool = getUnclassified();
  triageOffset = 0;
  triageSelected = null;

  if (triagePool.length === 0) {
    warn('No hay álbumes sin clasificar');
    triageActive = false;
    return;
  }

  // Ocultar vista normal, mostrar triage
  document.getElementById('main-layout').style.display = 'none';
  document.getElementById('releases-bar').style.display = 'none';
  document.getElementById('triage-bar').classList.add('active');
  document.getElementById('triage-grid').classList.add('active');

  log(`Triage iniciado: ${triagePool.length} álbumes sin clasificar`);
  loadTriageBatch();
}

function exitTriage() {
  triageActive = false;
  triageSelected = null;

  // Restaurar vista normal
  document.getElementById('triage-bar').classList.remove('active');
  document.getElementById('triage-grid').classList.remove('active');
  document.getElementById('main-layout').style.display = '';
  document.getElementById('releases-bar').style.display = '';

  // Re-renderizar la grilla principal con las clasificaciones aplicadas
  render();
  renderFeature();
  updateTriageButton();
}

function loadTriageBatch() {
  // Recalcular pool (algunos pueden haberse clasificado)
  triagePool = getUnclassified();
  triageBatch = triagePool.slice(triageOffset, triageOffset + TRIAGE.batchSize);

  // Si no quedan más, volver al inicio o salir
  if (triageBatch.length === 0) {
    if (triageOffset > 0) {
      // Hay más al inicio (se clasificaron algunos, el pool se contrajo)
      triageOffset = 0;
      triagePool = getUnclassified();
      triageBatch = triagePool.slice(0, TRIAGE.batchSize);
    }
    if (triageBatch.length === 0) {
      exitTriage();
      return;
    }
  }

  triageSelected = null;
  renderTriageBatch();
  updateTriageCounter();
  updateTriageCatButtons();
}

function nextTriageBatch() {
  triageOffset += TRIAGE.batchSize;
  // Recalcular pool por si se clasificaron algunos
  triagePool = getUnclassified();
  if (triageOffset >= triagePool.length) triageOffset = 0;
  loadTriageBatch();
}

function renderTriageBatch() {
  const grid = document.getElementById('triage-grid');

  grid.innerHTML = triageBatch.map(a => {
    const classified = a.categoria ? ' classified' : '';
    const badge = a.categoria && CATEGORIES[a.categoria]
      ? `<span class="triage-card-badge">${CATEGORIES[a.categoria].icon} ${CATEGORIES[a.categoria].label}</span>`
      : '';

    return `
    <div class="triage-card${classified}" data-id="${a.id}">
      <div class="triage-card-art">
        ${a.artwork_url
          ? `<img src="${a.artwork_url}" alt="${escapeHtml(a.album)}" loading="lazy">`
          : `<div class="placeholder" style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;font-family:var(--font-display);font-size:2.5rem;color:var(--accent-dim)">${escapeHtml(a.album.charAt(0))}</div>`
        }
        ${badge}
      </div>
      <div class="triage-card-info">
        <div class="triage-card-artist">${escapeHtml(a.artista)}</div>
        <div class="triage-card-album">${escapeHtml(a.album)}</div>
      </div>
    </div>`;
  }).join('');

  // Click para seleccionar, doble-click para abrir modal (ver tracklist, etc.)
  grid.querySelectorAll('.triage-card').forEach(card => {
    card.addEventListener('click', () => selectTriageCard(card.dataset.id));
    card.addEventListener('dblclick', () => openModal(card.dataset.id));
  });
}

function selectTriageCard(id) {
  // Si clickeas el mismo, deseleccionar
  if (triageSelected === id) {
    triageSelected = null;
  } else {
    triageSelected = id;
  }

  // Actualizar visual
  document.querySelectorAll('.triage-card').forEach(card => {
    card.classList.toggle('selected', card.dataset.id === triageSelected);
  });

  updateTriageCatButtons();
}

function triageClassify(cat) {
  if (!triageSelected) return;

  const a = catalogo.find(x => x.id === triageSelected);
  if (!a) return;

  // Toggle: si ya tiene esta categoría, desclasificar
  a.categoria = (a.categoria === cat) ? null : cat;
  saveEdit(triageSelected, 'categoria', a.categoria);

  // Actualizar la card visualmente
  const card = document.querySelector(`.triage-card[data-id="${triageSelected}"]`);
  if (card) {
    if (a.categoria) {
      card.classList.add('classified');
      const badge = card.querySelector('.triage-card-badge');
      const c = CATEGORIES[a.categoria];
      if (badge) {
        badge.textContent = `${c.icon} ${c.label}`;
      } else {
        const art = card.querySelector('.triage-card-art');
        art.insertAdjacentHTML('beforeend', `<span class="triage-card-badge">${c.icon} ${c.label}</span>`);
      }
    } else {
      card.classList.remove('classified');
      const badge = card.querySelector('.triage-card-badge');
      if (badge) badge.remove();
    }
  }

  // Auto-avanzar: seleccionar el siguiente sin clasificar
  const currentIdx = triageBatch.findIndex(x => x.id === triageSelected);
  triageSelected = null;
  card?.classList.remove('selected');

  // Buscar siguiente sin clasificar en el batch
  for (let i = currentIdx + 1; i < triageBatch.length; i++) {
    if (!triageBatch[i].categoria) {
      selectTriageCard(triageBatch[i].id);
      break;
    }
  }

  updateTriageCounter();
  updateTriageCatButtons();
}

function updateTriageCounter() {
  const remaining = getUnclassified().length;
  const classified = triageBatch.filter(a => a.categoria).length;
  document.getElementById('triage-counter').textContent =
    `${classified}/${triageBatch.length} this batch · ${remaining} remaining`;
}

function updateTriageCatButtons() {
  const enabled = triageSelected !== null;
  document.querySelectorAll('.triage-cat-btn').forEach(btn => {
    btn.disabled = !enabled;
  });
}

function updateTriageButton() {
  const btn = document.getElementById('btn-triage');
  const unclassified = getUnclassified().length;
  btn.style.display = unclassified > 0 ? '' : 'none';
  btn.textContent = `Triage (${unclassified})`;
}

// Eventos del triage
document.getElementById('btn-triage').addEventListener('click', enterTriage);
document.getElementById('triage-exit').addEventListener('click', exitTriage);
document.getElementById('triage-next').addEventListener('click', nextTriageBatch);

// Botones de categoría en la barra de triage
document.querySelectorAll('.triage-cat-btn').forEach(btn => {
  btn.addEventListener('click', () => triageClassify(btn.dataset.cat));
});

// Atajos de teclado (solo cuando triage está activo y modal cerrado)
document.addEventListener('keydown', (e) => {
  if (!triageActive) return;
  // No interferir con modal o inputs
  if (document.getElementById('modal-overlay').classList.contains('open')) return;
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

  const key = e.key.toLowerCase();

  if (TRIAGE.keyMap[key]) {
    e.preventDefault();
    triageClassify(TRIAGE.keyMap[key]);
  } else if (key === 's') {
    e.preventDefault();
    triageSelected = null;
    document.querySelectorAll('.triage-card').forEach(c => c.classList.remove('selected'));
    updateTriageCatButtons();
  } else if (key === 'arrowright') {
    e.preventDefault();
    nextTriageBatch();
  } else if (key === 'escape') {
    e.preventDefault();
    exitTriage();
  }
});

// ============================================================================
// RELEASES BAR — Barra horizontal con releases del mes
// ============================================================================
// Fusiona el antiguo sidebar (lista cronológica) y el today-banner en una
// sola barra horizontal scrolleable. Muestra releases agrupados por día,
// con el día actual destacado visualmente.
// ============================================================================

let calYear, calMonth; // Estado del mes visible

function initCalendar() {
  const hoy = new Date();
  calYear = hoy.getFullYear();
  calMonth = hoy.getMonth();
  renderReleasesBar();
}

// Construye un mapa: "MM-DD" → [array de álbumes que se lanzaron ese día]
function buildReleaseMap() {
  const map = {};
  catalogo.forEach(a => {
    if (a.fecha_precision !== 'day' || !a.fecha_lanzamiento) return;
    const parts = a.fecha_lanzamiento.split('-');
    if (parts.length < 3) return;
    const key = parts[1] + '-' + parts[2]; // "05-02"
    if (!map[key]) map[key] = [];
    map[key].push(a);
  });
  return map;
}

function renderReleasesBar() {
  const releaseMap = buildReleaseMap();
  const hoy = new Date();
  const diasEnMes = new Date(calYear, calMonth + 1, 0).getDate();
  const mm = String(calMonth + 1).padStart(2, '0');
  const anioActual = hoy.getFullYear();

  // Label del mes
  document.getElementById('cal-month-label').textContent =
    MONTHS[calMonth] + ' ' + calYear;

  let html = '';
  let totalReleases = 0;

  for (let day = 1; day <= diasEnMes; day++) {
    const dd = String(day).padStart(2, '0');
    const key = mm + '-' + dd;
    const releases = releaseMap[key] || [];
    if (releases.length === 0) continue;

    const isToday = (calMonth === hoy.getMonth() &&
                     calYear === hoy.getFullYear() &&
                     day === hoy.getDate());

    const labelClass = isToday ? 'releases-bar-day-label is-today' : 'releases-bar-day-label';
    const dayLabel = MONTHS[calMonth].slice(0, 3) + ' ' + day;

    html += `<div class="releases-bar-day-group">`;
    html += `<div class="${labelClass}">${dayLabel}</div>`;
    html += `<div class="releases-bar-day-items">`;

    releases.forEach(a => {
      const aniosAtras = anioActual - a.anio;
      html += `
        <div class="release-bar-item" onclick="openModal('${a.id}')">
          ${a.artwork_url ? `<img src="${a.artwork_url}" alt="${escapeHtml(a.album)}">` : ''}
          <div class="release-bar-item-info">
            <div class="release-bar-item-album">${escapeHtml(a.album)}</div>
            <div class="release-bar-item-meta">${escapeHtml(a.artista)} · ${a.anio} (${UI.yearsAgo(aniosAtras)})</div>
          </div>
        </div>`;
    });

    html += `</div></div>`;
    totalReleases += releases.length;
  }

  if (totalReleases === 0) {
    html = `<div class="releases-bar-empty">No releases in ${MONTHS[calMonth]}</div>`;
  }

  document.getElementById('releases-bar-items').innerHTML = html;

  // Auto-scroll al día de hoy si estamos en el mes actual
  if (calMonth === hoy.getMonth() && calYear === hoy.getFullYear()) {
    const todayLabel = document.querySelector('.releases-bar-day-label.is-today');
    if (todayLabel) {
      const container = document.getElementById('releases-bar-items');
      const group = todayLabel.closest('.releases-bar-day-group');
      if (group && container) {
        // Scroll suave para centrar el día de hoy
        const offset = group.offsetLeft - container.offsetLeft - 20;
        container.scrollLeft = Math.max(0, offset);
      }
    }
  }
}

// Navegación de mes
document.getElementById('cal-prev').addEventListener('click', () => {
  calMonth--;
  if (calMonth < 0) { calMonth = 11; calYear--; }
  renderReleasesBar();
});
document.getElementById('cal-next').addEventListener('click', () => {
  calMonth++;
  if (calMonth > 11) { calMonth = 0; calYear++; }
  renderReleasesBar();
});

// --- SERVICE WORKER --------------------------------------------------------
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch(e => warn(`SW: ${e.message}`));
  });
}

// --- INICIO ----------------------------------------------------------------
load();
