'use client';

import { useCallback, useEffect, useState } from 'react';
import { clientNavigateur } from '@/lib/supabase-navigateur';
import { dateLongue, heure, heuresDec, jourISO } from '@/lib/format';
import type {
  Alerte, Chantier, MargeChantier, NouvelleMission,
  SuiviMission as Suivi, Utilisateur,
} from '@/lib/types';
import EnvoiAdresse from './EnvoiAdresse';
import SuiviMissionVue from './SuiviMission';
import Equipe from './Equipe';

export default function Dashboard({ nom, entreprise }: { nom: string; entreprise: string }) {
  const sb = clientNavigateur();

  const [equipe, setEquipe] = useState<Utilisateur[]>([]);
  const [chantiers, setChantiers] = useState<Chantier[]>([]);
  const [missions, setMissions] = useState<Suivi[]>([]);
  const [alertes, setAlertes] = useState<Alerte[]>([]);
  const [marges, setMarges] = useState<MargeChantier[]>([]);
  const [csv, setCsv] = useState<string | null>(null);
  const [pret, setPret] = useState(false);

  const charger = useCallback(async () => {
    const [u, c, m, a, mg] = await Promise.all([
      sb.from('utilisateurs').select('*').eq('actif', true).order('nom'),
      sb.from('chantiers').select('*').in('statut', ['prevu', 'en_cours']).order('libelle'),
      sb.rpc('missions_du_jour', { p_jour: jourISO() }),
      sb.from('alertes').select('*').eq('lue', false).order('cree_le', { ascending: false }).limit(30),
      sb.from('v_marge_chantier').select('*'),
    ]);
    if (u.data) setEquipe(u.data as Utilisateur[]);
    if (c.data) setChantiers(c.data as Chantier[]);
    if (m.data) setMissions(m.data as Suivi[]);
    if (a.data) setAlertes(a.data as Alerte[]);
    if (mg.data) setMarges(mg.data as MargeChantier[]);
    setPret(true);
  }, [sb]);

  useEffect(() => { charger(); }, [charger]);

  // Temps réel : un pointage arrive côté ouvrier, le tableau se met à jour sans
  // rechargement. Le rafraîchissement périodique reste le filet de sécurité
  // — les durées en cours avancent même sans nouvel évènement.
  useEffect(() => {
    const canal = sb
      .channel('suivi')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'pointages' }, charger)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'mission_destinataires' }, charger)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'alertes' }, charger)
      .subscribe();
    const id = setInterval(charger, 60000);
    return () => { sb.removeChannel(canal); clearInterval(id); };
  }, [sb, charger]);

  async function envoyer(m: NouvelleMission) {
    const { error } = await sb.rpc('creer_mission', {
      p_libelle: m.libelle,
      p_adresse: m.adresse,
      p_code_postal: m.codePostal,
      p_ville: m.ville,
      p_lat: m.lat,
      p_lon: m.lon,
      p_rayon_m: m.rayon,
      p_jour: jourISO(),
      p_heure_rdv: m.heure,
      p_duree_min: m.duree,
      p_chantier_id: m.chantierId,
      p_destinataires: m.destinataires,
    });
    if (error) throw new Error(error.message);
    await charger();
  }

  async function valider(destinataireId: string) {
    const { error } = await sb.rpc('valider_presence', { p_dest_id: destinataireId });
    if (error) { alert(error.message); return; }
    await charger();
  }

  async function marquerLue(id: string) {
    await sb.from('alertes').update({ lue: true }).eq('id', id);
    setAlertes((a) => a.filter((x) => x.id !== id));
  }

  async function exporter() {
    if (csv) { setCsv(null); return; }
    const d = new Date();
    const debut = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
    const { data, error } = await sb.rpc('export_mois', { p_debut: debut, p_fin: jourISO() });
    if (error) { alert(error.message); return; }
    const lignes = (data ?? []) as Record<string, unknown>[];
    if (lignes.length === 0) { setCsv('Aucune journée sur la période.'); return; }
    const cols = Object.keys(lignes[0]);
    setCsv([
      cols.join(';'),
      ...lignes.map((l) =>
        cols.map((k) => (l[k] ?? '').toString().replace('.', ',')).join(';')
      ),
    ].join('\n'));
  }

  function telecharger() {
    if (!csv) return;
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `pointages-${jourISO()}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }

  // Compteurs du jour, tous destinataires confondus.
  const tous = missions.flatMap((m) => m.destinataires);
  const surPlace = tous.filter((d) => d.etat === 'confirme' && !d.depart).length;
  const attente = tous.filter((d) => d.etat === 'envoye' || d.etat === 'vue').length;
  const bloques = tous.filter((d) => d.etat === 'probleme').length;
  const realise = tous.reduce((s, d) => s + Number(d.duree_min ?? 0), 0);
  // Le prévu ne compte que ceux qui ont confirmé : un ouvrier qui n'est jamais
  // arrivé ne doit pas gonfler l'objectif de la journée.
  const prevu = missions.reduce(
    (s, m) =>
      s + m.mission.duree_service_min * m.destinataires.filter((d) => d.etat === 'confirme').length,
    0
  );

  return (
    <div className="wrap">
      <header className="top">
        <div>
          <p className="eyebrow">{entreprise}</p>
          <h1>Suivi de chantier</h1>
          <p className="jour">{dateLongue()} · connecté en tant que {nom}</p>
        </div>
        <button
          type="button"
          className="btn-x"
          onClick={async () => { await sb.auth.signOut(); location.href = '/login'; }}
        >
          Se déconnecter
        </button>
      </header>

      <div className="pile">
        <div className="kpis">
          <div className="kpi ok"><span>Sur le chantier</span><b>{surPlace}</b></div>
          <div className="kpi warn"><span>En attente</span><b>{attente}</b></div>
          <div className="kpi bad"><span>Bloqués</span><b>{bloques}</b></div>
          <div className="kpi">
            <span>Réalisé / prévu</span>
            <b>{heuresDec(realise)}<em> / {heuresDec(prevu)}</em></b>
          </div>
        </div>

        <EnvoiAdresse equipe={equipe} chantiers={chantiers} onEnvoyer={envoyer} />

        <section className="panel">
          <div className="panel-head">
            <h2>Alertes</h2>
            <span className={`pastille ${alertes.length ? 'warn' : 'idle'}`}>{alertes.length}</span>
          </div>
          {alertes.length === 0 ? (
            <p className="vide-msg">Rien à signaler.</p>
          ) : (
            alertes.map((a) => (
              <div key={a.id} className="alerte-i">
                <span className={`pastille ${a.type === 'absence' || a.type === 'hors_zone' || a.type === 'gps_insuffisant' || a.type === 'gps_suspect' ? 'bad' : 'warn'}`} />
                <div className="txt">
                  {a.titre}
                  {a.detail && <span>{a.detail}</span>}
                </div>
                <time>{heure(a.cree_le)}</time>
                <button type="button" className="btn-x" onClick={() => marquerLue(a.id)}>
                  Vu
                </button>
              </div>
            ))
          )}
        </section>

        {!pret ? (
          <p className="vide-msg">Chargement…</p>
        ) : missions.length === 0 ? (
          <section className="panel">
            <div className="panel-head"><h2>Journée</h2></div>
            <p className="vide-msg">
              Aucune adresse envoyée aujourd&apos;hui.<br />
              Le suivi apparaîtra ici dès le premier envoi.
            </p>
          </section>
        ) : (
          missions.map((m) => (
            <SuiviMissionVue key={m.mission.id} suivi={m} onValider={valider} />
          ))
        )}

        <section className="panel">
          <div className="panel-head">
            <h2>Chantiers · devisé vs réalisé</h2>
            <button type="button" className="btn-x" onClick={exporter}>
              {csv ? "Masquer l'export" : 'Exporter le mois'}
            </button>
          </div>

          {csv && (
            <div className="csv">
              <div className="h">
                <b>pointages-{jourISO()}.csv</b>
                <button type="button" className="btn-x" onClick={telecharger}>Télécharger</button>
              </div>
              <pre>{csv}</pre>
            </div>
          )}

          {marges.length === 0 ? (
            <p className="vide-msg">Aucun chantier enregistré.</p>
          ) : (
            <div className="chantiers">
              {marges.map((c) => {
                const devise = Number(c.heures_devisees ?? 0);
                const reel = Number(c.heures_realisees ?? 0);
                const over = devise > 0 && reel > devise;
                return (
                  <article key={c.id} className="chantier">
                    <div className="h">
                      <div>
                        <b>{c.libelle}</b>
                        {c.client_nom && <span>{c.client_nom}</span>}
                      </div>
                      {c.ecart_pct != null && (
                        <span className={`pastille ${over ? 'bad' : 'ok'}`}>
                          {Number(c.ecart_pct) >= 0 ? '+' : '−'}
                          {Math.abs(Number(c.ecart_pct))} %
                        </span>
                      )}
                    </div>
                    <div className="m">
                      <div><span>Devisé</span><b>{devise ? `${devise} h` : '—'}</b></div>
                      <div className={over ? 'over' : ''}><span>Réalisé</span><b>{reel} h</b></div>
                      {devise > 0 && (
                        <div className={over ? 'over' : ''}>
                          <span>{over ? 'Dépassement' : 'Reste'}</span>
                          <b>{Math.abs(Math.round((devise - reel) * 10) / 10)} h</b>
                        </div>
                      )}
                    </div>
                  </article>
                );
              })}
            </div>
          )}
        </section>

        <Equipe equipe={equipe} onChange={charger} />
      </div>
    </div>
  );
}
