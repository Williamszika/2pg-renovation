'use client';

import { useEffect, useRef, useState } from 'react';
import { chercherAdresse, type Adresse } from '@/lib/adresse';
import { duree } from '@/lib/format';
import type { Chantier, NouvelleMission, Utilisateur } from '@/lib/types';

type Props = {
  equipe: Utilisateur[];
  chantiers: Chantier[];
  onEnvoyer: (m: NouvelleMission) => Promise<void>;
};

const RAYONS = [
  { v: 20, l: 'strict' },
  { v: 50, l: 'conseillé' },
  { v: 100, l: 'ville dense' },
];

export default function EnvoiAdresse({ equipe, chantiers, onEnvoyer }: Props) {
  const [q, setQ] = useState('');
  const [sug, setSug] = useState<Adresse[]>([]);
  const [cherche, setCherche] = useState(false);
  const [pick, setPick] = useState<Adresse | null>(null);
  const [chantierId, setChantierId] = useState<string | null>(null);
  const [libelle, setLibelle] = useState('');
  const [heure, setHeure] = useState('08:00');
  const [dureeMin, setDureeMin] = useState(480);
  const [rayon, setRayon] = useState(50);
  const [dest, setDest] = useState<Record<string, boolean>>({});
  const [envoi, setEnvoi] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  const champ = useRef<HTMLInputElement>(null);

  // Recherche à la frappe. Le délai évite de bombarder la BAN à chaque
  // caractère, et l'AbortController garantit que la réponse d'une frappe
  // périmée n'écrase pas celle de la frappe courante.
  useEffect(() => {
    if (pick || q.trim().length < 3) { setSug([]); return; }
    const ctrl = new AbortController();
    const t = setTimeout(async () => {
      setCherche(true);
      try {
        setSug(await chercherAdresse(q, ctrl.signal));
      } catch (e) {
        if ((e as Error).name !== 'AbortError') setSug([]);
      } finally {
        setCherche(false);
      }
    }, 220);
    return () => { clearTimeout(t); ctrl.abort(); };
  }, [q, pick]);

  const nb = Object.values(dest).filter(Boolean).length;
  const pret = !!pick && nb > 0 && !envoi;

  function choisir(a: Adresse) {
    setPick(a);
    setQ(a.label);
    setSug([]);
    if (!libelle.trim()) setLibelle(a.voie);
  }

  function raccourci(c: Chantier) {
    // Un chantier connu porte déjà ses coordonnées : on n'a pas à re-géocoder.
    setChantierId(c.id);
    setLibelle(c.libelle);
    setQ([c.adresse, c.code_postal, c.ville].filter(Boolean).join(' '));
    setPick(null);
    champ.current?.focus();
  }

  async function envoyer() {
    if (!pick) return;
    setEnvoi(true);
    setErreur(null);
    try {
      await onEnvoyer({
        libelle: libelle.trim() || pick.voie,
        adresse: pick.voie,
        codePostal: pick.codePostal || null,
        ville: pick.ville || null,
        lat: pick.lat,
        lon: pick.lon,
        rayon,
        heure,
        duree: dureeMin,
        chantierId,
        destinataires: Object.entries(dest).filter(([, v]) => v).map(([k]) => k),
      });
      setPick(null); setQ(''); setLibelle(''); setChantierId(null);
    } catch (e) {
      setErreur((e as Error).message);
    } finally {
      setEnvoi(false);
    }
  }

  return (
    <section className="panel accent">
      <div className="panel-head">
        <h2>Envoyer une adresse</h2>
      </div>
      <div className="corps">
        <div className="champ">
          <label htmlFor="adr">Adresse du chantier</label>
          <div className="ac">
            {pick ? (
              <div className="choisie">
                <div className="t">
                  <b>{pick.voie}</b>
                  <span>{pick.codePostal} {pick.ville}</span>
                </div>
                <span className="geo">{pick.lat.toFixed(4)}, {pick.lon.toFixed(4)}</span>
                <button
                  type="button"
                  className="btn-x"
                  onClick={() => { setPick(null); setQ(''); setChantierId(null); champ.current?.focus(); }}
                >
                  Modifier
                </button>
              </div>
            ) : (
              <input
                id="adr"
                ref={champ}
                type="text"
                autoComplete="off"
                spellCheck={false}
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="Tapez une rue, une ville…"
              />
            )}

            {!pick && q.trim().length >= 3 && (
              <ul className="sug">
                {cherche && sug.length === 0 && <li className="vide">Recherche…</li>}
                {!cherche && sug.length === 0 && <li className="vide">Aucune adresse trouvée</li>}
                {sug.map((a, i) => (
                  <li key={`${a.label}-${i}`}>
                    <button type="button" onClick={() => choisir(a)}>
                      <span className="v">{a.voie}</span>
                      <span className="c">
                        {a.codePostal} {a.ville}
                        {a.type !== 'housenumber' && ' · adresse approximative'}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>

        {!pick && chantiers.length > 0 && (
          <div className="champ">
            <span className="label">Chantiers en cours</span>
            <div style={{ display: 'flex', gap: 7, flexWrap: 'wrap' }}>
              {chantiers.map((c) => (
                <button key={c.id} type="button" className="btn-x" onClick={() => raccourci(c)}>
                  {c.libelle}
                </button>
              ))}
            </div>
            <p className="aide">
              Le raccourci remplit le champ ; validez la proposition pour confirmer les coordonnées.
            </p>
          </div>
        )}

        <div className="champ">
          <label htmlFor="lib">Client ou libellé</label>
          <input
            id="lib"
            type="text"
            value={libelle}
            onChange={(e) => setLibelle(e.target.value)}
            placeholder="Ex. : Mme Durand — salle de bains"
          />
        </div>

        <div className="deux">
          <div className="champ">
            <label htmlFor="h">Heure de rendez-vous</label>
            <input id="h" type="time" value={heure} onChange={(e) => setHeure(e.target.value)} />
          </div>
          <div className="champ">
            <label htmlFor="d">Temps de service</label>
            <select id="d" value={dureeMin} onChange={(e) => setDureeMin(Number(e.target.value))}>
              {Array.from({ length: 21 }, (_, i) => 60 + i * 30).map((d) => (
                <option key={d} value={d}>{duree(d)}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="champ">
          <span className="label">Seuil de confirmation</span>
          <div className="seg" role="group" aria-label="Seuil de confirmation">
            {RAYONS.map((r) => (
              <button
                key={r.v}
                type="button"
                aria-pressed={rayon === r.v}
                onClick={() => setRayon(r.v)}
              >
                {r.v} m<em>{r.l}</em>
              </button>
            ))}
          </div>
          {rayon <= 20 && <p className="aide warn">Souvent hors de portée du GPS.</p>}
        </div>

        <div className="champ">
          <span className="label">Envoyer à</span>
          <div className="dest">
            {equipe.map((u) => (
              <label key={u.id}>
                <input
                  type="checkbox"
                  checked={!!dest[u.id]}
                  onChange={(e) => setDest((d) => ({ ...d, [u.id]: e.target.checked }))}
                />
                <span className="qui">
                  {u.nom.split(' ')[0]}
                  <span>{u.role === 'ouvrier' ? 'Ouvrier' : u.role === 'chef_equipe' ? "Chef d'équipe" : 'Patron'}</span>
                </span>
              </label>
            ))}
          </div>
          {equipe.length === 0 && (
            <p className="aide">Aucun ouvrier enregistré. Créez-les depuis la section Équipe.</p>
          )}
        </div>

        {erreur && <p className="aide warn">{erreur}</p>}

        <button type="button" className="envoyer" disabled={!pret} onClick={envoyer}>
          {envoi
            ? 'Envoi…'
            : !pick
              ? 'Choisissez une adresse'
              : nb === 0
                ? 'Sélectionnez au moins un ouvrier'
                : `Envoyer l'adresse à ${nb} ouvrier${nb > 1 ? 's' : ''}`}
        </button>
      </div>
    </section>
  );
}
