import AsyncStorage from '@react-native-async-storage/async-storage';
import { supabase } from './supabase';

/**
 * File d'attente hors ligne.
 *
 * Les chantiers en sous-sol et les parkings n'ont pas de réseau. Un pointage
 * refusé pour cette raison serait perdu — donc on l'empile localement et on
 * le rejoue à la reconnexion.
 *
 * L'heure locale est transmise à titre indicatif seulement : le serveur
 * horodate à la réception et enregistre l'écart, pour que le patron puisse
 * arbitrer. L'heure du téléphone ne fait jamais foi, elle est modifiable par
 * son porteur.
 */

const CLE = 'file-pointages-v1';

export type PointageEnAttente = {
  mission_id: string;
  type: 'pause_debut' | 'pause_fin' | 'depart';
  lat: number | null;
  lon: number | null;
  precision: number | null;
  motif: string | null;
  mock: boolean;
  /** Heure du téléphone au moment du geste. */
  horodatage_local: string;
};

async function lire(): Promise<PointageEnAttente[]> {
  const brut = await AsyncStorage.getItem(CLE);
  if (!brut) return [];
  try {
    return JSON.parse(brut) as PointageEnAttente[];
  } catch {
    await AsyncStorage.removeItem(CLE);
    return [];
  }
}

async function ecrire(f: PointageEnAttente[]): Promise<void> {
  await AsyncStorage.setItem(CLE, JSON.stringify(f));
}

export async function empiler(p: PointageEnAttente): Promise<void> {
  const f = await lire();
  f.push(p);
  await ecrire(f);
}

export async function nombreEnAttente(): Promise<number> {
  return (await lire()).length;
}

/**
 * Rejoue la file dans l'ordre. On s'arrête au premier échec réseau pour
 * préserver la chronologie : rejouer un départ avant la pause qui le précède
 * produirait une journée incohérente.
 */
export async function vider(): Promise<{ envoyes: number; restants: number }> {
  const f = await lire();
  let envoyes = 0;

  while (f.length > 0) {
    const p = f[0];
    const { error } = await supabase.rpc('pointer', {
      p_mission_id: p.mission_id,
      p_type: p.type,
      p_lat: p.lat,
      p_lon: p.lon,
      p_precision: p.precision,
      p_motif: p.motif,
      p_hors_ligne: true,
      p_horodatage_local: p.horodatage_local,
      p_mock: p.mock,
    });

    if (error) {
      // Erreur métier (séquence incohérente, journée déjà close) : le pointage
      // ne passera jamais, on le jette pour ne pas bloquer la file derrière lui.
      // Erreur réseau : on garde tout et on réessaiera.
      const reseau = /network|fetch|timeout/i.test(error.message);
      if (reseau) break;
      f.shift();
      await ecrire(f);
      continue;
    }

    f.shift();
    await ecrire(f);
    envoyes++;
  }

  return { envoyes, restants: f.length };
}
