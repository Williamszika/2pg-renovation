/**
 * Sert l'application web depuis Supabase, et rien que Supabase.
 *
 * Pourquoi cette fonction existe
 * -----------------------------
 * Storage renvoie tout fichier HTML en « text/plain », quel que soit le type
 * declare a l'envoi. C'est une protection deliberee contre l'hebergement de
 * pages d'hameconnage, et elle ne se desactive pas. Un index.html depose dans
 * un bucket s'affiche donc en code source au lieu de s'executer.
 *
 * Cette fonction lit les fichiers dans le bucket et les renvoie avec le type
 * qui convient. Les fichiers restent dans Storage — pour mettre l'application
 * a jour, on remplace index.html dans le bucket, la fonction ne bouge pas.
 *
 * Deploiement : Dashboard > Edge Functions > Deploy a new function > Via Editor.
 * La verification du JWT doit etre DESACTIVEE : un navigateur qui ouvre une
 * page n'envoie pas d'en-tete Authorization.
 */

const NOM = "app";        // nom de cette fonction, tel que deploye
const BUCKET = "app";     // bucket public qui contient les fichiers
const DEFAUT = "index.html";

/**
 * Types MIME. Deux comptent vraiment :
 *   .html          sans lui, rien ne s'affiche — c'est la raison d'etre du fichier
 *   .webmanifest   sans lui, Safari refuse d'installer l'application
 */
const TYPES: Record<string, string> = {
  // Pas « text/html » : la passerelle de Supabase reecrit toute reponse
  // text/html en text/plain et y ajoute une politique de securite qui
  // interdit toute execution — protection anti-hameconnage, appliquee aussi
  // bien aux fichiers de Storage qu'aux reponses des fonctions. Les
  // navigateurs affichent application/xhtml+xml comme une page ordinaire.
  html: "application/xhtml+xml; charset=utf-8",
  js: "text/javascript; charset=utf-8",
  json: "application/json; charset=utf-8",
  webmanifest: "application/manifest+json; charset=utf-8",
  png: "image/png",
  jpg: "image/jpeg",
  svg: "image/svg+xml",
  ico: "image/x-icon",
  css: "text/css; charset=utf-8",
  apk: "application/vnd.android.package-archive",
  txt: "text/plain; charset=utf-8",
};

/**
 * Ce qui peut vieillir en cache, et ce qui ne le peut pas.
 *
 * La page et le service worker portent la version de l'application : servis
 * depuis un cache, un nouveau depot resterait invisible. Les icones, elles,
 * ne changent jamais.
 */
function cache(nom: string): string {
  if (nom === "index.html" || nom === "sw.js") return "no-cache";
  if (nom.endsWith(".png") || nom.endsWith(".ico")) return "public, max-age=604800";
  return "public, max-age=3600";
}

function typeDe(nom: string): string {
  const ext = nom.includes(".") ? nom.split(".").pop()!.toLowerCase() : "";
  return TYPES[ext] ?? "application/octet-stream";
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Le chemin arrive soit complet — /functions/v1/app/sw.js — soit deja reduit
  // a /app/sw.js selon la version de la plateforme. On se repere donc sur le
  // nom de la fonction plutot que sur un nombre de segments fixe.
  const segments = url.pathname.split("/").filter(Boolean);
  const base = segments.lastIndexOf(NOM);
  const prefixe = base === -1 ? 0 : base + 1;
  const fichier = segments.slice(prefixe).join("/") || DEFAUT;

  // Sans barre oblique finale, « sw.js » se resoudrait un cran trop haut et le
  // service worker ne s'enregistrerait pas. On redirige plutot que d'echouer
  // silencieusement.
  if (segments.length === prefixe && !url.pathname.endsWith("/")) {
    return Response.redirect(url.origin + url.pathname + "/" + url.search, 301);
  }

  // Remonter l'arborescence sortirait du bucket.
  if (fichier.includes("..")) {
    return new Response("Chemin refuse", { status: 400 });
  }

  const source = `${Deno.env.get("SUPABASE_URL")}/storage/v1/object/public/${BUCKET}/${fichier}`;
  const amont = await fetch(source);

  if (!amont.ok) {
    return new Response(
      `Fichier introuvable : ${fichier}\n\n` +
        `Verifiez qu'il est bien depose dans le bucket « ${BUCKET} » ` +
        `et que ce bucket est public.`,
      { status: amont.status === 400 ? 404 : amont.status,
        headers: { "content-type": "text/plain; charset=utf-8" } },
    );
  }

  const entetes = new Headers({
    "content-type": typeDe(fichier),
    "cache-control": cache(fichier),
  });

  // L'APK doit atterrir dans les telechargements sous un nom lisible, pas
  // s'ouvrir dans un onglet.
  if (fichier.endsWith(".apk")) {
    entetes.set("content-disposition", `attachment; filename="${fichier}"`);
  }

  return new Response(amont.body, { status: 200, headers: entetes });
});
