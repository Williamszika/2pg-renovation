import 'server-only';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';

/**
 * Client serveur, lié aux cookies de session. Soumis aux politiques RLS.
 *
 * `server-only` fait échouer la compilation si un composant client importe ce
 * fichier par erreur — plutôt qu'au premier appel, en production.
 */
export async function clientServeur() {
  const jar = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => jar.getAll(),
        setAll: (liste: { name: string; value: string; options: CookieOptions }[]) => {
          try {
            liste.forEach(({ name, value, options }) => jar.set(name, value, options));
          } catch {
            // Appelé depuis un composant serveur : le middleware rafraîchit
            // déjà la session, on peut ignorer.
          }
        },
      },
    }
  );
}
