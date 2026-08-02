#!/usr/bin/env node
/**
 * Test d'intégration contre un vrai projet Supabase.
 *
 * Le patron s'envoie une adresse à lui-même et rejoue le parcours complet.
 * On vérifie ainsi ce que ni le typage ni les tests SQL locaux ne prouvent :
 * que le schéma déployé, les règles de sécurité et les clés fonctionnent
 * ensemble, à travers le réseau.
 *
 *   SUPABASE_URL="https://xxxx.supabase.co" \
 *   SUPABASE_ANON_KEY="eyJ..." \
 *   PATRON_EMAIL="vous@exemple.fr" \
 *   PATRON_MDP="..." \
 *   node supabase/test-projet.mjs
 *
 * N'utilise que la clé « anon », publique par nature — jamais la service_role.
 */

import { createClient } from '@supabase/supabase-js';

const { SUPABASE_URL, SUPABASE_ANON_KEY, PATRON_EMAIL, PATRON_MDP } = process.env;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !PATRON_EMAIL || !PATRON_MDP) {
  console.error(
    'Variables manquantes. Requises : SUPABASE_URL, SUPABASE_ANON_KEY, ' +
      'PATRON_EMAIL, PATRON_MDP.'
  );
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Chantier de test : 12 rue des Lilas, Blagnac.
const LAT = 43.6357;
const LON = 1.3897;
const RAYON = 50;

// 0,0002° de latitude ≈ 22 m ; 0,008° ≈ 890 m.
const PRES = { lat: LAT + 0.0002, lon: LON };
const LOIN = { lat: LAT + 0.008, lon: LON };

let reussis = 0;
let echoues = 0;

function verifier(nom, condition, detail = '') {
  if (condition) {
    console.log(`  \x1b[32mOK\x1b[0m    ${nom}`);
    reussis++;
  } else {
    console.log(`  \x1b[31mECHEC\x1b[0m ${nom}${detail ? ` — ${detail}` : ''}`);
    echoues++;
  }
}

function section(titre) {
  console.log(`\n\x1b[1m${titre}\x1b[0m`);
}

async function main() {
  section('Connexion');
  const { data: auth, error: eAuth } = await sb.auth.signInWithPassword({
    email: PATRON_EMAIL.trim().toLowerCase(),
    password: PATRON_MDP,
  });
  if (eAuth) {
    console.error(`  \x1b[31mConnexion impossible\x1b[0m : ${eAuth.message}`);
    process.exit(1);
  }
  verifier('Authentification du patron', !!auth.user);

  const { data: moi, error: eMoi } = await sb
    .from('utilisateurs')
    .select('id, nom, role, entreprise_id')
    .eq('id', auth.user.id)
    .maybeSingle();

  if (eMoi || !moi) {
    console.error(
      "  \x1b[31mCompte non rattaché\x1b[0m — connectez-vous d'abord au tableau de bord " +
        "pour créer l'entreprise."
    );
    process.exit(1);
  }
  verifier(`Compte rattaché (${moi.nom}, ${moi.role})`, true);
  verifier("Le compte est bien un encadrant", moi.role !== 'ouvrier',
           `role = ${moi.role}`);

  section("Envoi de l'adresse");
  const { data: missionId, error: eMission } = await sb.rpc('creer_mission', {
    p_libelle: 'TEST INSTALLATION',
    p_adresse: '12 rue des Lilas',
    p_code_postal: '31700',
    p_ville: 'Blagnac',
    p_lat: LAT,
    p_lon: LON,
    p_rayon_m: RAYON,
    p_jour: new Date().toISOString().slice(0, 10),
    p_heure_rdv: '08:00',
    p_duree_min: 420,
    p_chantier_id: null,
    p_destinataires: [moi.id],
  });
  verifier('Création de la mission', !eMission && !!missionId, eMission?.message);
  if (!missionId) {
    console.error('\nImpossible de continuer sans mission.');
    process.exit(1);
  }

  section("Lecture côté ouvrier");
  const { data: ma, error: eMa } = await sb.rpc('ma_mission_du_jour');
  verifier("L'adresse est visible", !eMa && ma?.mission?.id === missionId, eMa?.message);
  verifier('Coordonnées correctes',
           Math.abs((ma?.mission?.lat ?? 0) - LAT) < 1e-6, `lat = ${ma?.mission?.lat}`);
  verifier('Temps de service transmis', ma?.mission?.duree_service_min === 420);

  section('Confirmation de présence');
  const { data: r1 } = await sb.rpc('confirmer_arrivee', {
    p_mission_id: missionId, p_lat: LOIN.lat, p_lon: LOIN.lon, p_precision: 8,
  });
  verifier('Refusée à ~890 m', r1?.ok === false && r1?.motif === 'trop_loin',
           JSON.stringify(r1));

  const { data: r2 } = await sb.rpc('confirmer_arrivee', {
    p_mission_id: missionId, p_lat: PRES.lat, p_lon: PRES.lon, p_precision: 80,
  });
  verifier('Refusée avec un GPS à ± 80 m',
           r2?.ok === false && r2?.motif === 'gps_insuffisant', JSON.stringify(r2));

  const { data: r3 } = await sb.rpc('confirmer_arrivee', {
    p_mission_id: missionId, p_lat: PRES.lat, p_lon: PRES.lon, p_precision: 8,
  });
  verifier('Acceptée à ~22 m avec un GPS à ± 8 m', r3?.ok === true, JSON.stringify(r3));
  verifier('Distance calculée par le serveur',
           typeof r3?.distance_m === 'number' && r3.distance_m < RAYON,
           `${r3?.distance_m} m`);

  section('Pointages');
  const { error: ePause } = await sb.rpc('pointer', {
    p_mission_id: missionId, p_type: 'pause_debut',
  });
  verifier('Pause acceptée', !ePause, ePause?.message);

  const { error: eDouble } = await sb.rpc('pointer', {
    p_mission_id: missionId, p_type: 'pause_debut',
  });
  verifier('Deuxième pause consécutive rejetée', !!eDouble, 'aucune erreur levée');

  const { error: eReprise } = await sb.rpc('pointer', {
    p_mission_id: missionId, p_type: 'pause_fin',
  });
  verifier('Reprise acceptée', !eReprise, eReprise?.message);

  section('Suivi côté patron');
  const { data: suivi, error: eSuivi } = await sb.rpc('suivi_mission', {
    p_mission_id: missionId,
  });
  const dest = suivi?.destinataires?.[0];
  verifier('Le suivi remonte', !eSuivi && !!dest, eSuivi?.message);
  verifier('Présence confirmée', dest?.etat === 'confirme', dest?.etat);
  verifier('Source « gps »', dest?.confirme_source === 'gps', dest?.confirme_source);
  verifier('Journée en cours', dest?.en_cours === true);

  const { data: jour, error: eJour } = await sb.rpc('missions_du_jour', {
    p_jour: new Date().toISOString().slice(0, 10),
  });
  verifier('La mission apparaît dans la journée',
           !eJour && Array.isArray(jour) && jour.some((m) => m.mission.id === missionId),
           eJour?.message);

  section('Immuabilité des pointages');
  const { error: eUpd, count } = await sb
    .from('pointages')
    .update({ distance_m: 0 }, { count: 'exact' })
    .eq('mission_id', missionId);
  verifier('Un client ne peut pas modifier un pointage',
           !!eUpd || count === 0, `${count} ligne(s) modifiée(s)`);

  section('Export');
  const jourISO = new Date().toISOString().slice(0, 10);
  const { data: exp, error: eExp } = await sb.rpc('export_mois', {
    p_debut: jourISO, p_fin: jourISO,
  });
  verifier("L'export renvoie la journée",
           !eExp && Array.isArray(exp) && exp.length > 0, eExp?.message);

  console.log(
    `\n\x1b[1m${reussis} contrôle(s) réussi(s), ${echoues} échec(s)\x1b[0m`
  );
  console.log(
    "\nUne mission « TEST INSTALLATION » reste en base. Pour la supprimer, " +
      'dans le SQL Editor :\n' +
      "  delete from pointages where mission_id in (select id from missions where libelle like 'TEST INSTALLATION%');\n" +
      "  delete from missions  where libelle like 'TEST INSTALLATION%';"
  );

  await sb.auth.signOut();
  process.exit(echoues > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('\n\x1b[31mErreur inattendue\x1b[0m :', e.message);
  process.exit(1);
});
