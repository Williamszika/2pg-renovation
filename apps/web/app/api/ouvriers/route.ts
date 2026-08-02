import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';
import { clientServeur } from '@/lib/supabase-serveur';

/**
 * Création d'un compte ouvrier.
 *
 * Créer un utilisateur dans auth.users demande la clé service_role, qui
 * contourne toutes les politiques RLS. Elle ne doit jamais atteindre le
 * navigateur : d'où cette route serveur, qui vérifie d'abord que l'appelant est
 * bien un encadrant de l'entreprise, avec sa propre session.
 */
export async function POST(req: Request) {
  const sb = await clientServeur();

  const { data: { user } } = await sb.auth.getUser();
  if (!user) {
    return NextResponse.json({ erreur: 'Non authentifié' }, { status: 401 });
  }

  const { data: moi } = await sb
    .from('utilisateurs')
    .select('role')
    .eq('id', user.id)
    .single();

  if (!moi || (moi.role !== 'patron' && moi.role !== 'chef_equipe')) {
    return NextResponse.json({ erreur: "Réservé à l'encadrement" }, { status: 403 });
  }

  const body = (await req.json()) as { nom?: string; email?: string; motDePasse?: string };
  const nom = body.nom?.trim() ?? '';
  const email = body.email?.trim().toLowerCase() ?? '';
  const motDePasse = body.motDePasse ?? '';

  if (nom.length < 2) return NextResponse.json({ erreur: 'Nom trop court' }, { status: 400 });
  if (!/.+@.+\..+/.test(email)) return NextResponse.json({ erreur: 'E-mail invalide' }, { status: 400 });
  if (motDePasse.length < 8) {
    return NextResponse.json({ erreur: 'Mot de passe : 8 caractères minimum' }, { status: 400 });
  }

  const cle = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!cle) {
    return NextResponse.json(
      { erreur: 'SUPABASE_SERVICE_ROLE_KEY absente de la configuration serveur' },
      { status: 500 }
    );
  }

  const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, cle, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: cree, error: erreurAuth } = await admin.auth.admin.createUser({
    email,
    password: motDePasse,
    email_confirm: true, // pas de boîte mail à consulter sur un chantier
  });

  if (erreurAuth || !cree.user) {
    const dejaPris = /already been registered|already exists/i.test(erreurAuth?.message ?? '');
    return NextResponse.json(
      { erreur: dejaPris ? 'Cette adresse e-mail a déjà un compte.' : erreurAuth?.message },
      { status: 400 }
    );
  }

  // Le rattachement passe par la session de l'appelant : c'est SON entreprise
  // qui est utilisée, jamais un identifiant fourni par le client.
  const { error: erreurLien } = await sb.rpc('rattacher_utilisateur', {
    p_user_id: cree.user.id,
    p_nom: nom,
    p_role: 'ouvrier',
    p_telephone: null,
  });

  if (erreurLien) {
    // Rattachement impossible : on supprime le compte auth pour ne pas laisser
    // un utilisateur orphelin, incapable de se connecter à quoi que ce soit.
    await admin.auth.admin.deleteUser(cree.user.id);
    return NextResponse.json({ erreur: erreurLien.message }, { status: 400 });
  }

  return NextResponse.json({ ok: true, id: cree.user.id });
}
