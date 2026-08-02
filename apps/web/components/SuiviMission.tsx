'use client';

import { duree, ecart, heure, heureCourte, metres } from '@/lib/format';
import type { Destinataire, SuiviMission as Suivi } from '@/lib/types';

/**
 * Minutes depuis minuit, pour une heure « 08:00 » comme pour une date.
 *
 * On reconnaît une heure seule à sa forme, pas à son type : un horodatage ISO
 * est lui aussi une chaîne, et « 2026-08-02T10:21:00Z ».split(':')[0] vaut
 * « 2026-08-02T10 », dont Number() ne tire que NaN.
 */
function minutesDuJour(v: string): number {
  if (/^\d{1,2}:\d{2}/.test(v)) {
    const [h, m] = v.split(':').map(Number);
    return h * 60 + m;
  }
  const d = new Date(v);
  return d.getHours() * 60 + d.getMinutes();
}

/** Retard à l'arrivée, en minutes. Null si pas encore arrivé. */
function retardArrivee(d: Destinataire, heureRdv: string): number | null {
  const t = d.arrivee ?? d.confirme_le;
  if (!t) return null;
  return minutesDuJour(t) - minutesDuJour(heureRdv || '08:00');
}

/**
 * L'état se déduit des faits, personne ne le décide.
 *
 *   arrivé              → vert, avec le retard signalé s'il y en a un
 *   pas encore arrivé   → gris avant l'heure, orange après, rouge à +30 min
 *   GPS insuffisant     → le seul cas où un humain doit trancher
 */
function Etat({ d, heureRdv }: { d: Destinataire; heureRdv: string }) {
  if (d.etat === 'confirme') {
    if (d.depart) return <span className="pastille idle">Journée close</span>;
    const r = retardArrivee(d, heureRdv);
    return (
      <>
        <span className="pastille ok">Sur le chantier</span>
        {r != null && r > 5 && (
          <span className="pastille warn" style={{ marginLeft: 6 }}>Arrivé en retard</span>
        )}
      </>
    );
  }
  if (d.etat === 'probleme') return <span className="pastille bad">GPS insuffisant</span>;

  const ecoule = minutesDuJour(
    `${String(new Date().getHours()).padStart(2, '0')}:${String(new Date().getMinutes()).padStart(2, '0')}`
  ) - minutesDuJour(heureRdv || '08:00');

  if (ecoule > 30) return <span className="pastille bad">Absent</span>;
  if (ecoule > 5) return <span className="pastille warn">En retard · {duree(ecoule)}</span>;
  if (d.vue_le) return <span className="pastille pig">Vue {heure(d.vue_le)}</span>;
  return <span className="pastille idle">Attendu {heureCourte(heureRdv)}</span>;
}

/** Heure d'arrivée, et le retard juste en dessous s'il y en a un. */
function Arrivee({ d, heureRdv }: { d: Destinataire; heureRdv: string }) {
  const t = d.arrivee ?? d.confirme_le;
  if (!t) return <>—</>;
  const r = retardArrivee(d, heureRdv);
  return (
    <>
      {heure(t)}
      {r != null && r > 5 && (
        <span style={{ display: 'block', fontSize: '0.72rem', fontWeight: 650, color: 'var(--alerte)' }}>
          + {duree(r)} de retard
        </span>
      )}
    </>
  );
}

function Avancement({ fait, prevu }: { fait: number | null; prevu: number }) {
  if (fait == null) return <span style={{ color: 'var(--encre-pale)' }}>—</span>;
  const over = fait > prevu;
  const pct = Math.round((fait / prevu) * 100);
  const largeurQ = over ? (prevu / fait) * 100 : Math.min(100, pct);
  return (
    <div className="barre">
      <div className="piste">
        <i className={over ? 'q' : 'u'} style={{ width: `${largeurQ}%` }} />
        {over && <i className="o" style={{ width: `${100 - largeurQ}%` }} />}
      </div>
      <span>{pct} %</span>
    </div>
  );
}

export default function SuiviMission({
  suivi,
  onValider,
}: {
  suivi: Suivi;
  onValider: (destinataireId: string) => void;
}) {
  const { mission, destinataires } = suivi;

  return (
    <section className="panel">
      <div className="panel-head">
        <h2>
          {mission.libelle} · {heureCourte(mission.heure_rdv)} · service {duree(mission.duree_service_min)}
        </h2>
        <span className="pastille pig nodot">Confirmation sous {mission.rayon_m} m</span>
      </div>

      <div style={{ padding: '12px 16px', borderBottom: '1px solid var(--trait-pale)' }}>
        <p style={{ fontSize: '0.85rem', color: 'var(--encre-douce)' }}>
          {mission.adresse}
          {(mission.code_postal || mission.ville) &&
            `, ${[mission.code_postal, mission.ville].filter(Boolean).join(' ')}`}
        </p>
      </div>

      <div className="tw">
        <table>
          <thead>
            <tr>
              <th>Ouvrier</th>
              <th className="n">Arrivé</th>
              <th className="n">Distance</th>
              <th className="n">Pause</th>
              <th className="n">Départ</th>
              <th className="n">Réalisé</th>
              <th style={{ width: 130 }}>Avancement</th>
              <th className="n">Écart</th>
              <th>État</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {destinataires.map((d) => {
              const fait = d.duree_min != null ? Number(d.duree_min) : null;
              return (
                <tr key={d.destinataire_id}>
                  <td className="qui-cell">
                    <b>{d.nom}</b>
                    {d.motif && <span title={d.motif}>« {d.motif} »</span>}
                  </td>
                  <td className="n"><Arrivee d={d} heureRdv={mission.heure_rdv} /></td>
                  <td className="n">
                    {d.confirme_source === 'bureau'
                      ? 'débloqué'
                      : metres(d.confirme_dist_m)}
                  </td>
                  <td className="n">{d.pause_min ? `${Math.round(Number(d.pause_min))} min` : '—'}</td>
                  <td className="n">{heure(d.depart)}</td>
                  <td className="n">{duree(fait)}</td>
                  <td><Avancement fait={fait} prevu={mission.duree_service_min} /></td>
                  <td className="n">
                    {fait == null ? '—' : (
                      <span style={{ color: fait > mission.duree_service_min ? 'var(--arret)' : undefined }}>
                        {ecart(fait - mission.duree_service_min)}
                      </span>
                    )}
                  </td>
                  <td><Etat d={d} heureRdv={mission.heure_rdv} /></td>
                  <td className="n">
                    {/* Un seul cas demande une décision humaine : le GPS ne permet pas
                        de confirmer et l'ouvrier l'a signalé. Le reste se règle seul. */}
                    {d.etat === 'probleme' && (
                      <button
                        type="button"
                        className="btn-x solide"
                        title="Le GPS ne permet pas de confirmer sa présence"
                        onClick={() => onValider(d.destinataire_id)}
                      >
                        Débloquer
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}
