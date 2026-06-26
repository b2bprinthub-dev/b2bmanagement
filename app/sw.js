// B2B Print Hub — Service Worker
// Strategy: Cache-first for app shell, network-first for API calls

var CACHE_NAME = 'b2bprinthub-v10';
var SHELL_FILES = [
  './',
  './index.html',
  './manifest.json'
];

// Install: cache the app shell
self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(SHELL_FILES);
    }).then(function() {
      return self.skipWaiting();
    })
  );
});

// Activate: clean up old caches
self.addEventListener('activate', function(e) {
  e.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(keys.filter(function(k) { return k !== CACHE_NAME; }).map(function(k) { return caches.delete(k); }));
    }).then(function() {
      return self.clients.claim();
    })
  );
});

// Fetch: network-first for Supabase API, cache-first for app shell
self.addEventListener('fetch', function(e) {
  var url = e.request.url;

  // Always go network for Supabase / Google auth calls
  if (url.includes('supabase.co') || url.includes('google') || url.includes('googleapis') || url.includes('cdn.jsdelivr') || url.includes('cdnjs')) {
    e.respondWith(
      fetch(e.request).catch(function() {
        // If network fails and it's an API call, return a structured offline response
        if (url.includes('supabase.co')) {
          return new Response(JSON.stringify({ error: 'offline', message: 'No network connection. Data will sync when reconnected.' }), {
            status: 503,
            headers: { 'Content-Type': 'application/json' }
          });
        }
      })
    );
    return;
  }

  // Cache-first for app shell files
  e.respondWith(
    caches.match(e.request).then(function(cached) {
      if (cached) return cached;
      return fetch(e.request).then(function(response) {
        // Cache valid responses for shell files
        if (response && response.status === 200 && e.request.method === 'GET') {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function(cache) { cache.put(e.request, clone); });
        }
        return response;
      }).catch(function() {
        // Fallback to index.html for navigation requests
        if (e.request.mode === 'navigate') {
          return caches.match('./index.html');
        }
      });
    })
  );
});

// Background sync: flush queued writes when connection restores
self.addEventListener('sync', function(e) {
  if (e.tag === 'b2b-sync-queue') {
    e.waitUntil(flushSyncQueue());
  }
});

function flushSyncQueue() {
  // Notify all clients to flush their IndexedDB queue
  return self.clients.matchAll().then(function(clients) {
    clients.forEach(function(client) {
      client.postMessage({ type: 'FLUSH_SYNC_QUEUE' });
    });
  });
}

// Listen for messages from the app
self.addEventListener('message', function(e) {
  if (e.data && e.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  if (e.data && e.data.type === 'CACHE_UPDATE') {
    caches.open(CACHE_NAME).then(function(cache) {
      cache.add('./index.html');
    });
  }
});
