/** Formatage en français. Une seule source, pour éviter les divergences. */

export function deuxChiffres(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

export function heure(d: Date | string | null | undefined): string {
  if (!d) return '—';
  const x = typeof d === 'string' ? new Date(d) : d;
  return `${deuxChiffres(x.getHours())}:${deuxChiffres(x.getMinutes())}`;
}

/** « 8 h 20 », « 45 min ». */
export function duree(minutes: number | null | undefined): string {
  if (minutes == null) return '—';
  const m = Math.max(0, Math.round(minutes));
  const h = Math.floor(m / 60);
  return h === 0 ? `${m} min` : `${h} h ${deuxChiffres(m % 60)}`;
}

/** « 08:00 » à partir de « 08:00:00 ». */
export function heureCourte(t: string | null | undefined): string {
  return t ? t.slice(0, 5) : '—';
}

/** « dimanche 2 août » — en français, seule la première lettre prend la majuscule. */
export function dateLongue(d: Date = new Date()): string {
  const s = d.toLocaleDateString('fr-FR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function metres(m: number | null | undefined): string {
  if (m == null) return '—';
  return m >= 1000 ? `${(m / 1000).toFixed(1).replace('.', ',')} km` : `${Math.round(m)} m`;
}
