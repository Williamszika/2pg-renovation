import React, { useState } from 'react';
import {
  ActivityIndicator, KeyboardAvoidingView, Platform, Pressable,
  StyleSheet, Text, TextInput, View,
} from 'react-native';
import { supabase } from '../lib/supabase';
import { usePalette, type Palette } from '../theme';

export default function LoginScreen() {
  const c = usePalette();
  const s = styles(c);
  const [email, setEmail] = useState('');
  const [mdp, setMdp] = useState('');
  const [occupe, setOccupe] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  async function entrer() {
    setOccupe(true);
    setErreur(null);
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password: mdp,
    });
    if (error) {
      setErreur(
        /invalid login/i.test(error.message)
          ? 'Identifiant ou mot de passe incorrect.'
          : error.message
      );
    }
    setOccupe(false);
  }

  return (
    <KeyboardAvoidingView
      style={[s.plein, { backgroundColor: c.fond }]}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <View style={s.centre}>
        <Text style={s.marque}>2PG</Text>
        <Text style={s.titre}>Pointage chantier</Text>

        <TextInput
          style={s.champ}
          value={email}
          onChangeText={setEmail}
          placeholder="Adresse e-mail"
          placeholderTextColor={c.encrePale}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="email-address"
          textContentType="emailAddress"
        />
        <TextInput
          style={s.champ}
          value={mdp}
          onChangeText={setMdp}
          placeholder="Mot de passe"
          placeholderTextColor={c.encrePale}
          secureTextEntry
          textContentType="password"
          onSubmitEditing={entrer}
        />

        {erreur && <Text style={s.erreur}>{erreur}</Text>}

        <Pressable
          style={[s.bouton, { opacity: !email || !mdp || occupe ? 0.5 : 1 }]}
          disabled={!email || !mdp || occupe}
          onPress={entrer}
        >
          {occupe ? <ActivityIndicator color="#fff" /> : <Text style={s.boutonT}>Se connecter</Text>}
        </Pressable>

        <Text style={s.aide}>
          Vos identifiants vous sont remis par le bureau. En cas d'oubli, contactez-le
          directement — l'application ne permet pas de réinitialiser le mot de passe seul.
        </Text>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = (c: Palette) =>
  StyleSheet.create({
    plein: { flex: 1 },
    centre: { flex: 1, justifyContent: 'center', paddingHorizontal: 28, gap: 12 },
    marque: {
      fontSize: 13, fontWeight: '800', color: c.pigment,
      letterSpacing: 2.5, textAlign: 'center',
    },
    titre: {
      fontSize: 26, fontWeight: '700', color: c.encre,
      textAlign: 'center', marginBottom: 18, letterSpacing: -0.4,
    },
    champ: {
      borderWidth: 1, borderColor: c.trait, borderRadius: 12,
      paddingHorizontal: 15, paddingVertical: 15, fontSize: 16,
      color: c.encre, backgroundColor: c.surface,
    },
    erreur: { color: c.arret, fontSize: 14, fontWeight: '600' },
    bouton: {
      backgroundColor: c.pigment, borderRadius: 12,
      paddingVertical: 17, alignItems: 'center', marginTop: 4,
    },
    boutonT: { color: '#fff', fontSize: 17, fontWeight: '700' },
    aide: { fontSize: 12, color: c.encrePale, textAlign: 'center', marginTop: 16, lineHeight: 18 },
  });
