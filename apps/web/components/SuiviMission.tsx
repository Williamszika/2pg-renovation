'use client';

import { duree, ecart, heure, heureCourte, metres } from '@/lib/format';
import type { Destinataire, SuiviMission as Suivi } from '@/lib/types';

function Etat({ d, heureRdv }: { d: Destinataire; heureRdv: string }) {
  if (d.etat === 'confirme') {
    if (d.depart) return <span className="pastille idle">Journée close</span>;
    return <span className="pastille ok">Sur le chantier</span>;
  }
  if (d.etat === 'probleme') return <span className="pastille bad">Ne peut pas confirmer</span>;

  // En retard : l'heure de rendez-vous est dépassée de plus de 30 min.
  const [h, m] = heureRdv.split(':').map(Number);
  const rdv = new Date();
  rdv.setHours(h, m, 0, 0);
  if (Date.now() > rdv.getTime() + 30 * 60000) {
    return <span className="pastille bad">Absent</span>;
  }
  if (d.vue_le) return <span className="pastille pig">Vue {heure(d.vue_le)}</span>;
  return <span className="pastille idle">Envoyée</span>;
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
                  <td className="n">{heure(d.arrivee ?? d.confirme_le)}</td>
                  <td className="n">
                    {d.confirme_source === 'bureau'
                      ? 'validé bureau'
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
                    {d.etat !== 'confirme' && (
                      <button
                        type="button"
                        className={`btn-x ${d.etat === 'probleme' ? 'solide' : ''}`}
                        onClick={() => onValider(d.destinataire_id)}
                      >
                        Valider
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
