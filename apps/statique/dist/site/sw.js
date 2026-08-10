/**
 * Service worker.
 *
 * Ne met en cache QUE la coquille de l'application — page, manifeste, icônes.
 * Jamais les réponses de Supabase : servir un pointage périmé depuis un cache
 * ferait croire à l'ouvrier que sa journée est enregistrée alors qu'elle ne
 * l'est pas. Tout ce qui touche aux données part sur le réseau, et échoue
 * franchement quand il n'y en a pas — l'application sait gérer ce cas.
 *
 * La page elle-même est servie réseau d'abord, cache en secours. Le cache
 * d'abord ferait qu'après un nouveau dépôt, la première ouverture montre
 * encore l'ancienne version — et personne ne pense à ouvrir deux fois.
 * Le reste de la coquille (icônes, manifeste) change rarement et reste servi
 * depuis le cache, rafraîchi en arrière-plan.
 */
const CACHE = "2pg-coquille-2026-08-10.1842";
const COQUILLE = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icone192.png",
  "./icone512.png",
  "./iconemaskable512.png",
  "./appletouchicon.png",
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

  // L'APK se télécharge une fois, sur un seul téléphone. Le mettre en cache
  // logerait presque un mégaoctet sur celui de chaque ouvrier, pour rien.
  if (url.pathname.endsWith(".apk")) return;

  const memorise = (rep) => {
    if (rep && rep.status === 200) {
      const copie = rep.clone();
      caches.open(CACHE).then((c) => c.put(req, copie));
    }
    return rep;
  };

  // La page : réseau d'abord, pour ne jamais afficher une version périmée
  // quand la connexion est là. Le cache prend le relais hors ligne.
  if (req.mode === "navigate" || url.pathname.endsWith("/") || url.pathname.endsWith("/index.html")) {
    e.respondWith(
      fetch(req).then(memorise).catch(() => caches.match(req).then((c) => c || caches.match("./index.html")))
    );
    return;
  }

  // Icônes et manifeste : cache d'abord, rafraîchi en arrière-plan.
  e.respondWith(
    caches.match(req).then((cache) => {
      const reseau = fetch(req).then(memorise).catch(() => cache);
      return cache || reseau;
    })
  );
});
