// ============================================================================
// Service Worker — Discoteca
// ============================================================================
// Estrategia:
//   - App shell (HTML/CSS/JS): cache-first, se actualiza al cambiar CACHE_VERSION
//   - catalogo.json: stale-while-revalidate (rápido pero se refresca en segundo plano)
//   - artwork (i.scdn.co, coverartarchive): cache-first con expiración suave
// ============================================================================

const CACHE_VERSION = 'discoteca-v3';
const SHELL_CACHE = `${CACHE_VERSION}-shell`;
const DATA_CACHE  = `${CACHE_VERSION}-data`;
const IMG_CACHE   = `${CACHE_VERSION}-img`;

const SHELL_ASSETS = [
  './',
  'index.html',
  'assets/styles.css',
  'assets/app.js',
  'assets/icon.svg',
  'manifest.webmanifest',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE).then((cache) => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => !k.startsWith(CACHE_VERSION))
          .map((k) => caches.delete(k))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // catalogo.json — stale-while-revalidate
  if (url.pathname.endsWith('/datos/catalogo.json')) {
    event.respondWith(staleWhileRevalidate(req, DATA_CACHE));
    return;
  }

  // Artwork (Spotify, Cover Art Archive, etc.) — cache-first
  if (/(scdn\.co|coverartarchive\.org|musicbrainz\.org)/.test(url.host)) {
    event.respondWith(cacheFirst(req, IMG_CACHE));
    return;
  }

  // App shell (mismo origen) — cache-first
  if (url.origin === self.location.origin) {
    event.respondWith(cacheFirst(req, SHELL_CACHE));
    return;
  }

  // Fuentes de Google, embed de Spotify, etc. — network passthrough
});

async function cacheFirst(req, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(req);
  if (hit) return hit;
  try {
    const resp = await fetch(req);
    if (resp.ok) cache.put(req, resp.clone());
    return resp;
  } catch (e) {
    return hit || Response.error();
  }
}

async function staleWhileRevalidate(req, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(req);
  const fetchPromise = fetch(req).then((resp) => {
    if (resp.ok) cache.put(req, resp.clone());
    return resp;
  }).catch(() => hit);
  return hit || fetchPromise;
}
