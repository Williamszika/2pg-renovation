import { redirect } from 'next/navigation';
import { clientServeur } from '@/lib/supabase-serveur';
import Dashboard from '@/components/Dashboard';
import Bootstrap from '@/components/Bootstrap';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const sb = await clientServeur();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) redirect('/login');

  const { data: moi } = await sb
    .from('utilisateurs')
    .select('nom, role, entreprise_id')
    .eq('id', user.id)
    .maybeSingle();

  // Premier lancement : le compte existe côté auth mais n'est rattaché à
  // aucune entreprise. On lui propose de créer la sienne.
  if (!moi) return <Bootstrap email={user.email ?? ''} />;

  if (moi.role === 'ouvrier') {
    return (
      <div className="login">
        <div className="login-box">
          <h1>Tableau de bord réservé</h1>
          <p style={{ textAlign: 'center', color: 'var(--encre-douce)' }}>
            Votre compte est un compte ouvrier. Le pointage se fait depuis
            l&apos;application mobile 2PG Pointage.
          </p>
        </div>
      </div>
    );
  }

  const { data: ent } = await sb
    .from('entreprises')
    .select('nom')
    .eq('id', moi.entreprise_id)
    .single();

  return <Dashboard nom={moi.nom} entreprise={ent?.nom ?? '2PG Rénovation'} />;
}
