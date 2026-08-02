/**
 * Recherche d'adresse via l'API Adresse (Base Adresse Nationale).
 *
 * https://api-adresse.data.gouv.fr — service public français, gratuit, sans clé
 * ni compte de facturation, et meilleur que Google sur les adresses françaises
 * puisque c'est la base officielle.
 *
 * Google Places ferait le même travail, mais exige une clé, un compte de
 * facturation et se facture à la session. Pour de la navigation en revanche,
 * on renvoie bien l'ouvrier vers Google Maps ou Waze : c'est ce qu'il connaît.
 */

export type Adresse = {
  label: string;
  /** Numéro et rue, sans code postal ni ville. */
  voie: string;
  codePostal: string;
  ville: string;
  lat: number;
  lon: number;
  /** Score de confiance renvoyé par la BAN, entre 0 et 1. */
  score: number;
  /** « housenumber » est le seul type qui désigne une adresse précise. */
  type: string;
};

type BanFeature = {
  geometry: { coordinates: [number, number] };
  properties: {
    label: string; name: string; postcode: string; city: string;
    score: number; type: string;
  };
};

export async function chercherAdresse(q: string, signal?: AbortSignal): Promise<Adresse[]> {
  const requete = q.trim();
  // La BAN rejette les requêtes de moins de 3 caractères.
  if (requete.length < 3) return [];

  const url = new URL('https://api-adresse.data.gouv.fr/search/');
  url.searchParams.set('q', requete);
  url.searchParams.set('limit', '6');
  url.searchParams.set('autocomplete', '1');

  const r = await fetch(url, { signal });
  if (!r.ok) throw new Error(`Recherche d'adresse indisponible (${r.status})`);

  const j = (await r.json()) as { features: BanFeature[] };
  return j.features.map((f) => ({
    label: f.properties.label,
    voie: f.properties.name,
    codePostal: f.properties.postcode,
    ville: f.properties.city,
    lon: f.geometry.coordinates[0],
    lat: f.geometry.coordinates[1],
    score: f.properties.score,
    type: f.properties.type,
  }));
}
