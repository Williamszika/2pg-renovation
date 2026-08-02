import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

/**
 * Rafraîchit le jeton de session à chaque requête et le réécrit dans les
 * cookies. Sans cela, les composants serveur voient une session expirée et
 * renvoient l'utilisateur vers la connexion au bout d'une heure.
 */
export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  const sb = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (liste: { name: string; value: string; options: CookieOptions }[]) => {
          liste.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          liste.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    }
  );

  await sb.auth.getUser();
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
