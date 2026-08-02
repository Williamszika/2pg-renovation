import React, { useCallback, useEffect, useRef, useState } from 'react';
import * as Location from 'expo-location';
import {
  ActivityIndicator, Alert, AppState, Linking, Platform, Pressable,
  RefreshControl, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '../lib/supabase';
import { duree, dateLongue, heure, heureCourte, metres } from '../lib/format';
import {
  appareilCompromis, arreterSurveillance, demanderPermissionArrierePlan,
  demanderPermissionPremierPlan, distanceM, positionActuelle, rayonApproche,
  surveillerApproche,
} from '../lib/location';
import { empiler, nombreEnAttente, vider } from '../lib/queue';
import { usePalette, type Palette } from '../theme';

type Journee = {
  arrivee: string | null;
  depart: string | null;
  pause_min: number;
  duree_min: number | null;
  en_cours: boolean;
  en_pause: boolean;
};

type MaMission = {
  destinataire_id: string;
  etat: 'envoye' | 'vue' | 'confirme' | 'probleme' | 'refuse';
  confirme_le: string | null;
  confirme_dist_m: number | null;
  confirme_source: 'gps' | 'bureau' | null;
  motif: string | null;
  mission: {
    id: string; libelle: string; adresse: string;
    code_postal: string | null; ville: string | null;
    lat: number; lon: number; rayon_m: number;
    jour: string; heure_rdv: string; duree_service_min: number;
  };
  journee: Journee | null;
};

export default function MissionScreen({ nom }: { nom: string }) {
  const c = usePalette();
  const s = styles(c);
  const insets = useSafeAreaInsets();

  const [data, setData] = useState<MaMission | null>(null);
  const [chargement, setChargement] = useState(true);
  const [rafraichit, setRafraichit] = useState(false);
  const [action, setAction] = useState(false);
  const [dist, setDist] = useState<number | null>(null);
  const [precision, setPrecision] = useState<number | null>(null);
  const [permis, setPermis] = useState(true);
  const [enAttente, setEnAttente] = useState(0);
  const [tick, setTick] = useState(0);
  const [feuille, setFeuille] = useState<null | 'probleme' | 'depart'>(null);
  const [motif, setMotif] = useState('');

  const suivi = useRef<{ remove: () => void } | null>(null);
  // Une confirmation automatique déjà partie : sans ce garde, chaque relevé de
  // position en relancerait une.
  const autoEnCours = useRef(false);
  const [confirmeAuto, setConfirmeAuto] = useState(false);

  // ---- données -------------------------------------------------------------

  const charger = useCallback(async () => {
    const { data: r, error } = await supabase.rpc('ma_mission_du_jour');
    if (error) {
      Alert.alert('Impossible de récupérer votre adresse', error.message);
      return;
    }
    const m = (r as MaMission | null) ?? null;
    setData(m);
    if (m && m.etat === 'envoye') await supabase.rpc('marquer_vue', { p_mission_id: m.mission.id });
    setEnAttente(await nombreEnAttente());
  }, []);

  useEffect(() => {
    (async () => {
      setPermis(await demanderPermissionPremierPlan());
      await charger();
      setChargement(false);
      const { restants } = await vider();
      setEnAttente(restants);
    })();
  }, [charger]);

  // Recharger au retour au premier plan : le patron a pu envoyer une adresse
  // ou valider une présence pendant que le téléphone était en poche.
  useEffect(() => {
    const sub = AppState.addEventListener('change', (e) => {
      if (e === 'active') {
        charger();
        vider().then(({ restants }) => setEnAttente(restants));
      }
    });
    return () => sub.remove();
  }, [charger]);

  // Le chrono avance sans requête réseau : la durée se recalcule à partir de
  // l'heure d'arrivée, qui vient du serveur.
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(id);
  }, []);

  // ---- position ------------------------------------------------------------

  useEffect(() => {
    if (!data || !permis) return;
    const { lat, lon, rayon_m, libelle } = data.mission;
    let vivant = true;

    (async () => {
      const sub = await Location.watchPositionAsync(
        { accuracy: Location.Accuracy.High, distanceInterval: 5, timeInterval: 4000 },
        (p) => {
          if (!vivant) return;
          const d = distanceM(p.coords.latitude, p.coords.longitude, lat, lon);
          setDist(d);
          setPrecision(p.coords.accuracy ?? null);
          confirmerSiArrive(p, d);
        }
      );
      suivi.current = sub;

      // Le signal d'approche n'a de sens que tant que la présence n'est pas
      // confirmée. Une fois sur place, on coupe la surveillance.
      if (data.etat !== 'confirme') {
        if (await demanderPermissionArrierePlan()) {
          await surveillerApproche(lat, lon, rayon_m, libelle);
        }
      } else {
        await arreterSurveillance();
      }
    })();

    return () => {
      vivant = false;
      suivi.current?.remove();
      suivi.current = null;
    };
  }, [data?.mission.id, data?.etat, permis]);

  // ---- actions -------------------------------------------------------------

  /**
   * Confirmation automatique dès l'entrée dans le périmètre.
   *
   * L'ouvrier n'a rien à faire : franchir la limite du chantier suffit, et le
   * bureau le voit immédiatement. Le bouton reste affiché comme secours, pour
   * le cas où il ouvre l'application alors qu'il est déjà sur place et que la
   * position n'a pas encore bougé.
   *
   * Le serveur revérifie tout — position, rayon, précision. Une position
   * falsifiée ne passerait pas davantage ici qu'avec un appui sur le bouton.
   */
  async function confirmerSiArrive(p: Location.LocationObject, d: number) {
    if (autoEnCours.current || action) return;
    if (!data || data.etat === 'confirme') return;
    const r = data.mission.rayon_m;
    if (d > r) return;
    if (p.coords.accuracy != null && p.coords.accuracy > r) return;

    autoEnCours.current = true;
    try {
      const { data: res, error } = await supabase.rpc('confirmer_arrivee', {
        p_mission_id: data.mission.id,
        p_lat: p.coords.latitude,
        p_lon: p.coords.longitude,
        p_precision: p.coords.accuracy,
        p_mock: (p as { mocked?: boolean }).mocked === true,
        p_root: false,
      });
      if (!error && (res as { ok?: boolean })?.ok) {
        setConfirmeAuto(true);
        await charger();
      }
      // Refus du serveur ou réseau absent : on laisse l'ouvrier appuyer
      // lui-même, et on réessaiera au prochain relevé de position.
    } finally {
      autoEnCours.current = false;
    }
  }

  async function confirmer() {
    if (!data) return;
    setAction(true);
    try {
      const p = await positionActuelle();
      const root = await appareilCompromis();
      const { data: r, error } = await supabase.rpc('confirmer_arrivee', {
        p_mission_id: data.mission.id,
        p_lat: p.lat, p_lon: p.lon, p_precision: p.precision,
        p_mock: p.mock, p_root: root,
      });
      if (error) throw error;

      const res = r as { ok: boolean; motif?: string; distance_m?: number; precision_m?: number };
      if (!res.ok) {
        Alert.alert(
          res.motif === 'gps_insuffisant' ? 'GPS trop imprécis' : 'Vous êtes trop loin',
          res.motif === 'gps_insuffisant'
            ? `Le GPS annonce ± ${res.precision_m} m : il ne peut pas prouver que vous êtes à moins de ${data.mission.rayon_m} m.`
            : `Vous êtes à ${metres(res.distance_m ?? null)} du chantier. Approchez-vous.`
        );
        return;
      }
      await charger();
    } catch (e) {
      Alert.alert('Échec de la confirmation', (e as Error).message);
    } finally {
      setAction(false);
    }
  }

  async function pointer(type: 'pause_debut' | 'pause_fin' | 'depart', motifTexte?: string) {
    if (!data) return;
    setAction(true);
    try {
      let p: { lat: number; lon: number; precision: number | null; mock: boolean } | null = null;
      try {
        p = await positionActuelle();
      } catch {
        // Pas de GPS (sous-sol) : on pointe quand même, le serveur enregistre
        // simplement une position inconnue.
      }

      const { data: r, error } = await supabase.rpc('pointer', {
        p_mission_id: data.mission.id,
        p_type: type,
        p_lat: p?.lat ?? null, p_lon: p?.lon ?? null, p_precision: p?.precision ?? null,
        p_motif: motifTexte ?? null,
        p_hors_ligne: false, p_horodatage_local: null, p_mock: p?.mock ?? false,
      });

      if (error) {
        if (/network|fetch|timeout/i.test(error.message)) {
          await empiler({
            mission_id: data.mission.id, type,
            lat: p?.lat ?? null, lon: p?.lon ?? null, precision: p?.precision ?? null,
            motif: motifTexte ?? null, mock: p?.mock ?? false,
            horodatage_local: new Date().toISOString(),
          });
          setEnAttente(await nombreEnAttente());
          Alert.alert(
            'Enregistré sur le téléphone',
            "Pas de réseau ici. Votre pointage part automatiquement dès que la connexion revient."
          );
          return;
        }
        throw error;
      }

      const res = r as { ok: boolean; motif?: string; distance_m?: number; rayon_m?: number };
      if (!res.ok && res.motif === 'motif_requis') {
        setFeuille('depart');
        setMotif('');
        return;
      }
      await charger();
    } catch (e) {
      Alert.alert('Échec du pointage', (e as Error).message);
    } finally {
      setAction(false);
    }
  }

  async function envoyerProbleme() {
    if (!data || motif.trim().length < 3) return;
    setAction(true);
    try {
      let p: { lat: number; lon: number; precision: number | null } | null = null;
      try { p = await positionActuelle(); } catch { /* position indisponible */ }
      const { error } = await supabase.rpc('signaler_probleme', {
        p_mission_id: data.mission.id,
        p_motif: motif.trim(),
        p_lat: p?.lat ?? null, p_lon: p?.lon ?? null, p_precision: p?.precision ?? null,
      });
      if (error) throw error;
      setFeuille(null); setMotif('');
      await charger();
    } catch (e) {
      Alert.alert('Envoi impossible', (e as Error).message);
    } finally {
      setAction(false);
    }
  }

  function ouvrirItineraire() {
    if (!data) return;
    const { lat, lon, adresse, code_postal, ville } = data.mission;
    const label = encodeURIComponent(
      [adresse, code_postal, ville].filter(Boolean).join(' ')
    );
    // On passe les coordonnées ET le libellé : l'application de navigation
    // affiche le nom de la rue plutôt qu'un point sans contexte.
    const url = Platform.select({
      ios: `maps://?daddr=${lat},${lon}&q=${label}`,
      android: `geo:${lat},${lon}?q=${lat},${lon}(${label})`,
      default: `https://www.google.com/maps/dir/?api=1&destination=${lat},${lon}`,
    })!;
    Linking.openURL(url).catch(() =>
      Linking.openURL(`https://www.google.com/maps/dir/?api=1&destination=${lat},${lon}`)
    );
  }

  // ---- rendu ---------------------------------------------------------------

  if (chargement) {
    return (
      <View style={[s.plein, { backgroundColor: c.fond }]}>
        <ActivityIndicator color={c.pigment} />
      </View>
    );
  }

  const m = data?.mission;
  const j = data?.journee ?? null;
  const rayon = m?.rayon_m ?? 50;
  const assezPres = dist != null && dist <= rayon;
  const gpsFiable = precision == null || precision <= rayon;
  const peutConfirmer = assezPres && gpsFiable;
  const approche = dist != null && dist <= rayonApproche(rayon);

  const minutesFaites = j?.arrivee
    ? Math.max(
        0,
        (Date.now() - new Date(j.arrivee).getTime()) / 60000 - (j.pause_min ?? 0)
      )
    : 0;

  const finPrevue = j?.arrivee && m
    ? new Date(
        new Date(j.arrivee).getTime() +
          (m.duree_service_min + (j.pause_min ?? 0)) * 60000
      )
    : null;

  return (
    <View style={[s.plein, { backgroundColor: c.fond, paddingTop: insets.top }]}>
      <View style={s.entete}>
        <Text style={s.bonjour}>Bonjour {nom.split(' ')[0]}</Text>
        <Text style={s.date}>{dateLongue()}</Text>
      </View>

      <ScrollView
        contentContainerStyle={[s.corps, { paddingBottom: insets.bottom + 28 }]}
        refreshControl={
          <RefreshControl
            refreshing={rafraichit}
            onRefresh={async () => { setRafraichit(true); await charger(); setRafraichit(false); }}
            tintColor={c.pigment}
          />
        }
      >
        {enAttente > 0 && (
          <View style={[s.bandeau, { backgroundColor: c.alertePale }]}>
            <Text style={[s.bandeauT, { color: c.alerte }]}>
              {enAttente} pointage{enAttente > 1 ? 's' : ''} en attente de réseau
            </Text>
          </View>
        )}

        {!permis && (
          <View style={[s.bandeau, { backgroundColor: c.arretPale }]}>
            <Text style={[s.bandeauT, { color: c.arret }]}>
              L'accès à la position est refusé. Sans lui, impossible de confirmer votre arrivée.
            </Text>
            <Pressable onPress={() => Linking.openSettings()}>
              <Text style={[s.bandeauLien, { color: c.arret }]}>Ouvrir les réglages</Text>
            </Pressable>
          </View>
        )}

        {!data || !m ? (
          <View style={s.vide}>
            <Text style={s.videT}>Rien pour aujourd'hui</Text>
            <Text style={s.videS}>Le bureau ne vous a envoyé aucune adresse.</Text>
          </View>
        ) : (
          <>
            {approche && data.etat !== 'confirme' && (
              <View style={[s.notif, { backgroundColor: c.pigment }]}>
                <Text style={s.notifT}>Vous approchez du chantier</Text>
                <Text style={s.notifS}>{metres(dist)} — {m.libelle}</Text>
              </View>
            )}

            <Pressable style={s.adresse} onPress={ouvrirItineraire}>
              <View style={s.adresseTxt}>
                <Text style={s.adresseNom}>{m.libelle}</Text>
                <Text style={s.adresseRue}>{m.adresse}</Text>
                {(m.code_postal || m.ville) && (
                  <Text style={s.adresseVille}>
                    {[m.code_postal, m.ville].filter(Boolean).join(' ')}
                  </Text>
                )}
              </View>
              <View style={s.adresseGo}>
                <Text style={s.adresseFleche}>➤</Text>
                <Text style={s.adresseGoT}>ITINÉRAIRE</Text>
              </View>
            </Pressable>

            {data.etat !== 'confirme' ? (
              <>
                <Text style={s.rdv}>
                  Rendez-vous <Text style={s.rdvFort}>{heureCourte(m.heure_rdv)}</Text>
                  {'  ·  '}{duree(m.duree_service_min)} de service
                </Text>

                <View
                  style={[
                    s.geo,
                    { backgroundColor: assezPres ? c.okPale : c.alertePale },
                  ]}
                >
                  <View style={s.geoLigne}>
                    <Text style={[s.geoT, { color: assezPres ? c.ok : c.alerte }]}>
                      {assezPres ? "Vous êtes sur l'adresse" : "Approchez-vous de l'adresse"}
                    </Text>
                    <Text style={s.geoD}>{dist == null ? 'recherche…' : metres(dist)}</Text>
                  </View>
                  {!gpsFiable && (
                    <Text style={[s.geoP, { color: c.arret }]}>
                      Précision GPS ± {Math.round(precision!)} m — insuffisante
                    </Text>
                  )}
                </View>

                {peutConfirmer ? (
                  <Pressable
                    style={[s.gros, { backgroundColor: c.ok }]}
                    onPress={confirmer}
                    disabled={action}
                  >
                    {action ? (
                      <ActivityIndicator color="#fff" />
                    ) : (
                      <>
                        <Text style={s.grosT}>Je suis arrivé</Text>
                        <Text style={s.grosS}>Confirmation en cours… · à {metres(dist)}</Text>
                      </>
                    )}
                  </Pressable>
                ) : (
                  <View style={[s.gros, { backgroundColor: c.surface2 }]}>
                    <Text style={[s.grosT, { color: c.encrePale }]}>
                      {!gpsFiable
                        ? 'GPS trop imprécis'
                        : dist == null
                          ? 'Recherche du signal…'
                          : `Encore ${metres(dist - rayon)}`}
                    </Text>
                    <Text style={[s.grosS, { color: c.encrePale }]}>
                      {!gpsFiable
                        ? `± ${Math.round(precision!)} m pour un seuil de ${rayon} m`
                        : `Le bouton s'active à moins de ${rayon} m`}
                    </Text>
                  </View>
                )}

                {data.etat === 'probleme' ? (
                  <View style={[s.note, { backgroundColor: c.alertePale }]}>
                    <Text style={[s.noteT, { color: c.encre }]}>Demande envoyée au bureau</Text>
                    <Text style={s.noteS}>« {data.motif} »</Text>
                  </View>
                ) : (
                  !peutConfirmer && (
                    <Pressable
                      style={s.secondaire}
                      onPress={() => { setFeuille('probleme'); setMotif(''); }}
                    >
                      <Text style={s.secondaireT}>Je n'arrive pas à confirmer</Text>
                    </Pressable>
                  )
                )}
              </>
            ) : j && !j.en_cours ? (
              <View style={s.fin}>
                <View style={[s.finRond, { backgroundColor: c.okPale }]}>
                  <Text style={[s.finCheck, { color: c.ok }]}>✓</Text>
                </View>
                <Text style={s.finT}>Journée terminée</Text>
                <Text style={s.finD}>{duree(j.duree_min)} sur le chantier</Text>
                <Text style={s.finH}>{heure(j.arrivee)} – {heure(j.depart)}</Text>
              </View>
            ) : (
              <>
                {confirmeAuto && (
                  <View style={[s.note, { backgroundColor: c.okPale }]}>
                    <Text style={[s.noteT, { color: c.encre }]}>Présence confirmée automatiquement</Text>
                    <Text style={s.noteS}>
                      Vous êtes entré dans le périmètre du chantier. Le bureau en a été informé.
                    </Text>
                  </View>
                )}
                <View style={s.chrono}>
                  <Text style={s.chronoL}>
                    {j?.en_pause ? 'En pause' : 'Sur le chantier depuis'}
                  </Text>
                  <Text style={[s.chronoV, j?.en_pause && { color: c.alerte }]}>
                    {duree(minutesFaites)}
                  </Text>
                  <View style={s.chronoSub}>
                    <Text style={s.chronoS}>Arrivé {heure(j?.arrivee)}</Text>
                    {finPrevue && <Text style={s.chronoS}>Fin prévue {heure(finPrevue)}</Text>}
                  </View>
                </View>

                {j?.en_pause ? (
                  <Pressable
                    style={[s.gros, { backgroundColor: c.ok }]}
                    onPress={() => pointer('pause_fin')}
                    disabled={action}
                  >
                    <Text style={s.grosT}>Reprendre</Text>
                    <Text style={s.grosS}>{heure(new Date())}</Text>
                  </Pressable>
                ) : (
                  <>
                    <Pressable
                      style={[s.gros, { backgroundColor: c.arret }]}
                      onPress={() => pointer('depart')}
                      disabled={action}
                    >
                      <Text style={s.grosT}>J'ai terminé</Text>
                      <Text style={s.grosS}>{heure(new Date())}</Text>
                    </Pressable>
                    <Pressable
                      style={s.secondaire}
                      onPress={() => pointer('pause_debut')}
                      disabled={action}
                    >
                      <Text style={s.secondaireT}>Prendre ma pause</Text>
                    </Pressable>
                  </>
                )}
              </>
            )}
          </>
        )}
      </ScrollView>

      <Text style={s.pied}>Position relevée uniquement à l'arrivée et au départ.</Text>

      {feuille && (
        <View style={s.modaleFond}>
          <View style={[s.modale, { paddingBottom: insets.bottom + 18 }]}>
            <Text style={s.modaleT}>
              {feuille === 'probleme'
                ? 'Signaler au bureau'
                : `Départ à ${metres(dist)} du chantier`}
            </Text>
            <Text style={s.modaleS}>
              {feuille === 'probleme'
                ? `${metres(dist)} · précision ± ${precision ? Math.round(precision) : '?'} m`
                : 'Indiquez le motif.'}
            </Text>
            <TextInput
              style={s.champ}
              value={motif}
              onChangeText={setMotif}
              multiline
              autoFocus
              placeholder={
                feuille === 'probleme'
                  ? 'Ex. : je suis devant la porte mais le GPS ne descend pas'
                  : "Ex. : j'ai déjà chargé la camionnette"
              }
              placeholderTextColor={c.encrePale}
            />
            <View style={s.modaleActions}>
              <Pressable
                style={[s.modaleBtn, s.modaleAnnule]}
                onPress={() => { setFeuille(null); setMotif(''); }}
              >
                <Text style={s.modaleAnnuleT}>Annuler</Text>
              </Pressable>
              <Pressable
                style={[
                  s.modaleBtn,
                  { backgroundColor: c.pigment, opacity: motif.trim().length < 3 ? 0.4 : 1 },
                ]}
                disabled={motif.trim().length < 3 || action}
                onPress={() => {
                  if (feuille === 'probleme') envoyerProbleme();
                  else { const t = motif.trim(); setFeuille(null); setMotif(''); pointer('depart', t); }
                }}
              >
                <Text style={s.modaleOkT}>Envoyer</Text>
              </Pressable>
            </View>
          </View>
        </View>
      )}
    </View>
  );
}

const styles = (c: Palette) =>
  StyleSheet.create({
    plein: { flex: 1 },
    entete: { paddingHorizontal: 20, paddingTop: 10, paddingBottom: 14 },
    bonjour: { fontSize: 21, fontWeight: '700', color: c.encre, letterSpacing: -0.3 },
    date: { fontSize: 13, color: c.encrePale, marginTop: 2 },
    corps: { paddingHorizontal: 20, gap: 14 },

    bandeau: { borderRadius: 12, padding: 12, gap: 4 },
    bandeauT: { fontSize: 13, fontWeight: '600' },
    bandeauLien: { fontSize: 13, fontWeight: '700', textDecorationLine: 'underline' },

    vide: { paddingVertical: 60, alignItems: 'center', gap: 6 },
    videT: { fontSize: 17, fontWeight: '700', color: c.encreDouce },
    videS: { fontSize: 14, color: c.encrePale, textAlign: 'center' },

    notif: { borderRadius: 12, padding: 14 },
    notifT: { fontSize: 15, fontWeight: '700', color: '#fff' },
    notifS: { fontSize: 13, color: '#fff', opacity: 0.9, marginTop: 2 },

    adresse: {
      flexDirection: 'row', alignItems: 'center', gap: 12,
      backgroundColor: c.surface, borderWidth: 1, borderColor: c.trait,
      borderRadius: 16, padding: 16,
    },
    adresseTxt: { flex: 1 },
    adresseNom: { fontSize: 13, fontWeight: '600', color: c.encrePale },
    adresseRue: { fontSize: 21, fontWeight: '700', color: c.encre, marginTop: 3, letterSpacing: -0.3 },
    adresseVille: { fontSize: 17, color: c.encre },
    adresseGo: { alignItems: 'center', gap: 2 },
    adresseFleche: { fontSize: 24, color: c.pigment, transform: [{ rotate: '-45deg' }] },
    adresseGoT: { fontSize: 10, fontWeight: '800', color: c.pigment, letterSpacing: 0.6 },

    rdv: { fontSize: 13, color: c.encreDouce, textAlign: 'center' },
    rdvFort: { fontWeight: '700', color: c.encre },

    geo: { borderRadius: 12, padding: 14, gap: 6 },
    geoLigne: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline' },
    geoT: { fontSize: 15, fontWeight: '700', flex: 1 },
    geoD: { fontSize: 13, fontWeight: '600', color: c.encreDouce },
    geoP: { fontSize: 12, fontWeight: '600' },

    gros: { borderRadius: 14, paddingVertical: 20, paddingHorizontal: 16, alignItems: 'center', gap: 3 },
    grosT: { fontSize: 19, fontWeight: '700', color: '#fff' },
    grosS: { fontSize: 13, color: '#fff', opacity: 0.88 },

    secondaire: {
      borderWidth: 1, borderColor: c.trait, borderRadius: 12,
      paddingVertical: 13, alignItems: 'center', backgroundColor: c.surface,
    },
    secondaireT: { fontSize: 15, fontWeight: '600', color: c.encreDouce },

    chrono: {
      backgroundColor: c.surface, borderWidth: 1, borderColor: c.trait,
      borderRadius: 16, paddingVertical: 22, alignItems: 'center',
    },
    chronoL: {
      fontSize: 11, fontWeight: '700', color: c.encrePale,
      letterSpacing: 1.2, textTransform: 'uppercase',
    },
    chronoV: { fontSize: 44, fontWeight: '700', color: c.encre, letterSpacing: -1.5, marginTop: 4 },
    chronoSub: { flexDirection: 'row', gap: 18, marginTop: 12 },
    chronoS: { fontSize: 13, color: c.encreDouce },

    fin: { alignItems: 'center', paddingVertical: 48, gap: 4 },
    finRond: { width: 56, height: 56, borderRadius: 28, alignItems: 'center', justifyContent: 'center', marginBottom: 10 },
    finCheck: { fontSize: 26, fontWeight: '700' },
    finT: { fontSize: 18, fontWeight: '700', color: c.encre },
    finD: { fontSize: 32, fontWeight: '700', color: c.encre, letterSpacing: -1, marginTop: 4 },
    finH: { fontSize: 14, color: c.encrePale },

    note: { borderRadius: 12, padding: 13, gap: 3 },
    noteT: { fontSize: 14, fontWeight: '700' },
    noteS: { fontSize: 13, color: c.encreDouce },

    pied: {
      textAlign: 'center', fontSize: 11, color: c.encrePale,
      paddingVertical: 10, borderTopWidth: 1, borderTopColor: c.traitPale,
      backgroundColor: c.surface2,
    },

    modaleFond: {
      ...StyleSheet.absoluteFillObject,
      backgroundColor: 'rgba(15,17,21,0.45)', justifyContent: 'flex-end',
    },
    modale: {
      backgroundColor: c.surface, borderTopLeftRadius: 18, borderTopRightRadius: 18,
      padding: 20, gap: 12,
    },
    modaleT: { fontSize: 18, fontWeight: '700', color: c.encre },
    modaleS: { fontSize: 14, color: c.encreDouce },
    champ: {
      minHeight: 84, borderWidth: 1, borderColor: c.trait, borderRadius: 10,
      padding: 12, fontSize: 15, color: c.encre, backgroundColor: c.surface2,
      textAlignVertical: 'top',
    },
    modaleActions: { flexDirection: 'row', gap: 10 },
    modaleBtn: { flex: 1, borderRadius: 10, paddingVertical: 14, alignItems: 'center' },
    modaleAnnule: { borderWidth: 1, borderColor: c.trait },
    modaleAnnuleT: { fontSize: 15, fontWeight: '600', color: c.encreDouce },
    modaleOkT: { fontSize: 15, fontWeight: '700', color: '#fff' },
  });
