import { createBrowserClient } from '@supabase/ssr';

/**
 * Client navigateur — soumis aux politiques RLS.
 *
 * Ce fichier n'importe rien de `next/headers` : il est chargé par les
 * composants client, où les API serveur n'existent pas.
 */
export function clientNavigateur() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
