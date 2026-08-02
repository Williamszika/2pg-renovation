/**
 * Service worker.
 *
 * Ne met en cache QUE la coquille de l'application — page, manifeste, icônes.
 * Jamais les réponses de Supabase : servir un pointage périmé depuis un cache
 * ferait croire à l'ouvrier que sa journée est enregistrée alors qu'elle ne
 * l'est pas. Tout ce qui touche aux données part sur le réseau, et échoue
 * franchement quand il n'y en a pas — l'application sait gérer ce cas.
 */
const CACHE = "2pg-coquille-v1";
const COQUILLE = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icone-192.png",
  "./icone-512.png",
  "./icone-maskable-512.png",
  "./apple-touch-icon.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(COQUILLE)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((noms) => Promise.all(noms.filter((n) => n !== CACHE).map((n) => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  // Supabase et l'API Adresse : réseau uniquement, jamais de cache.
  if (url.origin !== self.location.origin) return;

  // La coquille : on sert le cache d'abord pour un démarrage instantané, et on
  // rafraîchit en arrière-plan pour la prochaine ouverture.
  e.respondWith(
    caches.match(req).then((cache) => {
      const reseau = fetch(req)
        .then((rep) => {
          if (rep && rep.status === 200) {
            const copie = rep.clone();
            caches.open(CACHE).then((c) => c.put(req, copie));
          }
          return rep;
        })
        .catch(() => cache);
      return cache || reseau;
    })
  );
});
