'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { clientNavigateur } from '@/lib/supabase-navigateur';

export default function Login() {
  const sb = clientNavigateur();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [mdp, setMdp] = useState('');
  const [occupe, setOccupe] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  async function entrer(e: React.FormEvent) {
    e.preventDefault();
    setOccupe(true);
    setErreur(null);
    const { error } = await sb.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password: mdp,
    });
    if (error) {
      setErreur(
        /invalid login/i.test(error.message)
          ? 'Identifiant ou mot de passe incorrect.'
          : error.message
      );
      setOccupe(false);
      return;
    }
    router.push('/');
    router.refresh();
  }

  return (
    <main className="login">
      <form className="login-box" onSubmit={entrer}>
        <p className="marque">2PG</p>
        <h1>Suivi de chantier</h1>

        <div className="champ">
          <label htmlFor="e">Adresse e-mail</label>
          <input
            id="e" type="email" autoComplete="username" required
            value={email} onChange={(ev) => setEmail(ev.target.value)}
          />
        </div>
        <div className="champ">
          <label htmlFor="p">Mot de passe</label>
          <input
            id="p" type="password" autoComplete="current-password" required
            value={mdp} onChange={(ev) => setMdp(ev.target.value)}
          />
        </div>

        {erreur && <p className="err">{erreur}</p>}

        <button type="submit" className="envoyer" disabled={!email || !mdp || occupe}>
          {occupe ? 'Connexion…' : 'Se connecter'}
        </button>
      </form>
    </main>
  );
}
