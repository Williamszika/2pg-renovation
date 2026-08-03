import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import * as Application from 'expo-application';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import type { Session } from '@supabase/supabase-js';

import { supabase } from './src/lib/supabase';
import { preparerNotifications, arreterSurveillance } from './src/lib/location';
import LoginScreen from './src/screens/LoginScreen';
import MissionScreen from './src/screens/MissionScreen';
import { usePalette, type Palette } from './src/theme';

type Profil = { nom: string; role: string; appareil_valide_le: string | null };

export default function App() {
  const c = usePalette();
  const s = styles(c);
  const [session, setSession] = useState<Session | null>(null);
  const [profil, setProfil] = useState<Profil | null>(null);
  const [pret, setPret] = useState(false);
  const [bloque, setBloque] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      if (!data.session) setPret(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setSession(s);
      if (!s) { setProfil(null); setPret(true); arreterSurveillance(); }
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) return;
    (async () => {
      // Un compte, un téléphone : le premier appareil s'enregistre, tout
      // changement ultérieur demande une validation du bureau.
      const appareilId =
        (await Application.getAndroidId()) ??
        (await Application.getIosIdForVendorAsync()) ??
        'inconnu';
      const { data: verdict } = await supabase.rpc('enregistrer_appareil', {
        p_appareil_id: appareilId,
        p_appareil_nom: `${Device.brand ?? ''} ${Device.modelName ?? ''}`.trim() || 'Téléphone',
      });
      setBloque(verdict?.autorise === false);

      const { data: u, error } = await supabase
        .from('utilisateurs')
        .select('nom, role, appareil_valide_le')
        .eq('id', session.user.id)
        .single();

      if (error) {
        Alert.alert(
          'Compte non rattaché',
          "Votre compte existe mais n'est rattaché à aucune entreprise. Contactez le bureau."
        );
      } else {
        setProfil(u as Profil);
      }

      await preparerNotifications();
      try {
        const t = await Notifications.getExpoPushTokenAsync();
        await supabase.rpc('enregistrer_push_token', { p_token: t.data });
      } catch {
        // Les notifications push ne fonctionnent pas dans Expo Go sur iOS ;
        // le reste de l'application n'en dépend pas.
      }
      setPret(true);
    })();
  }, [session]);

  if (!pret) {
    return (
      <View style={[s.plein, { backgroundColor: c.fond }]}>
        <ActivityIndicator color={c.pigment} />
      </View>
    );
  }

  return (
    <SafeAreaProvider>
      <StatusBar style="auto" />
      {!session ? (
        <LoginScreen />
      ) : bloque ? (
        <View style={[s.plein, s.pad, { backgroundColor: c.fond }]}>
          <Text style={s.titre}>Nouvel appareil</Text>
          <Text style={s.texte}>
            Ce compte était utilisé sur un autre téléphone. Le bureau doit valider ce
            changement avant que vous puissiez pointer.
          </Text>
          <Pressable style={s.lien} onPress={() => supabase.auth.signOut()}>
            <Text style={s.lienT}>Se déconnecter</Text>
          </Pressable>
        </View>
      ) : profil && profil.role !== 'ouvrier' ? (
        // Cette application est celle de l'ouvrier : elle n'affiche qu'une
        // adresse du jour. Un encadrant qui s'y connecte n'a aucune mission
        // reçue et lirait « rien pour aujourd'hui » — autant le dire.
        <View style={[s.plein, s.pad, { backgroundColor: c.fond }]}>
          <Text style={s.titre}>Compte d'encadrement</Text>
          <Text style={s.texte}>
            Cette application affiche l'adresse du jour et enregistre les arrivées :
            elle est faite pour les ouvriers.
          </Text>
          <Text style={s.texte}>
            Le suivi des équipes, l'envoi des adresses et l'ajout des comptes se
            font depuis le tableau de bord, dans le navigateur.
          </Text>
          <Pressable style={s.lien} onPress={() => supabase.auth.signOut()}>
            <Text style={s.lienT}>Se déconnecter</Text>
          </Pressable>
        </View>
      ) : profil ? (
        <MissionScreen nom={profil.nom} />
      ) : (
        <View style={[s.plein, s.pad, { backgroundColor: c.fond }]}>
          <Text style={s.titre}>Compte non rattaché</Text>
          <Text style={s.texte}>
            Votre compte n'est rattaché à aucune entreprise. Contactez le bureau.
          </Text>
          <Pressable style={s.lien} onPress={() => supabase.auth.signOut()}>
            <Text style={s.lienT}>Se déconnecter</Text>
          </Pressable>
        </View>
      )}
    </SafeAreaProvider>
  );
}

const styles = (c: Palette) =>
  StyleSheet.create({
    plein: { flex: 1, alignItems: 'center', justifyContent: 'center' },
    pad: { paddingHorizontal: 32, gap: 12 },
    titre: { fontSize: 21, fontWeight: '700', color: c.encre, textAlign: 'center' },
    texte: { fontSize: 15, color: c.encreDouce, textAlign: 'center', lineHeight: 22 },
    lien: { marginTop: 10 },
    lienT: { fontSize: 15, fontWeight: '700', color: c.pigment },
  });
