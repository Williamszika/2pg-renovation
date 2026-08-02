/** Formatage en français, partagé par tout le tableau de bord. */

const dd = (n: number) => (n < 10 ? `0${n}` : String(n));

export function heure(d: string | Date | null | undefined): string {
  if (!d) return '—';
  const x = typeof d === 'string' ? new Date(d) : d;
  return `${dd(x.getHours())}:${dd(x.getMinutes())}`;
}

/** « 8 h 20 », « 45 min ». */
export function duree(minutes: number | null | undefined): string {
  if (minutes == null) return '—';
  const m = Math.max(0, Math.round(minutes));
  const h = Math.floor(m / 60);
  return h === 0 ? `${m} min` : `${h} h ${dd(m % 60)}`;
}

/** Écart signé, avec le vrai signe moins typographique. */
export function ecart(minutes: number): string {
  if (Math.abs(minutes) < 1) return "à l'heure";
  return `${minutes > 0 ? '+' : '−'} ${duree(Math.abs(minutes))}`;
}

export function heureCourte(t: string | null | undefined): string {
  return t ? t.slice(0, 5) : '—';
}

export function metres(m: number | null | undefined): string {
  if (m == null) return '—';
  return m >= 1000 ? `${(m / 1000).toFixed(1).replace('.', ',')} km` : `${Math.round(m)} m`;
}

export function heuresDec(minutes: number | null | undefined): string {
  if (minutes == null) return '—';
  return `${(Math.round((minutes / 60) * 10) / 10).toString().replace('.', ',')} h`;
}

/** « dimanche 2 août » — seule la première lettre prend la majuscule. */
export function dateLongue(d: Date = new Date()): string {
  const s = d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function jourISO(d: Date = new Date()): string {
  return `${d.getFullYear()}-${dd(d.getMonth() + 1)}-${dd(d.getDate())}`;
}
