import 'react-native-url-polyfill/auto';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import Constants from 'expo-constants';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';

if (!url || !anonKey) {
  // Mieux vaut un message clair au démarrage qu'un « network request failed »
  // incompréhensible au premier appel.
  console.warn(
    "EXPO_PUBLIC_SUPABASE_URL et EXPO_PUBLIC_SUPABASE_ANON_KEY manquants. " +
      "Copiez .env.example vers .env et relancez « npx expo start -c »."
  );
}

export const supabase = createClient(url, anonKey, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    // Pas de session dans l'URL : on n'est pas dans un navigateur.
    detectSessionInUrl: false,
  },
});

export const appVersion = Constants.expoConfig?.version ?? '1.0.0';

/** Types du domaine, alignés sur le schéma SQL. */
export type EtatDestinataire = 'envoye' | 'vue' | 'confirme' | 'probleme' | 'refuse';

export type Mission = {
  id: string;
  libelle: string;
  adresse: string;
  code_postal: string | null;
  ville: string | null;
  lat: number;
  lon: number;
  rayon_m: number;
  jour: string;
  heure_rdv: string;
  duree_service_min: number;
};

export type MaMission = {
  mission: Mission;
  destinataire_id: string;
  etat: EtatDestinataire;
  confirme_le: string | null;
  confirme_dist_m: number | null;
  confirme_source: 'gps' | 'bureau' | null;
  motif: string | null;
};
