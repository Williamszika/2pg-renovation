'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { clientNavigateur } from '@/lib/supabase-navigateur';

/**
 * Premier lancement : le compte existe côté auth mais n'appartient à aucune
 * entreprise. Il crée la sienne et en devient patron.
 */
export default function Bootstrap({ email }: { email: string }) {
  const sb = clientNavigateur();
  const router = useRouter();
  const [entreprise, setEntreprise] = useState('2PG Rénovation');
  const [nom, setNom] = useState('');
  const [siret, setSiret] = useState('');
  const [occupe, setOccupe] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  async function creer(e: React.FormEvent) {
    e.preventDefault();
    setOccupe(true);
    setErreur(null);
    const { error } = await sb.rpc('bootstrap_entreprise', {
      p_nom: entreprise.trim(),
      p_mon_nom: nom.trim(),
      p_siret: siret.trim() || null,
    });
    if (error) { setErreur(error.message); setOccupe(false); return; }
    router.refresh();
  }

  return (
    <main className="login">
      <form className="login-box" onSubmit={creer}>
        <p className="marque">2PG</p>
        <h1>Créer votre entreprise</h1>
        <p style={{ fontSize: '0.86rem', color: 'var(--encre-douce)', textAlign: 'center' }}>
          Connecté avec {email}. Ce premier compte devient celui du patron.
        </p>

        <div className="champ">
          <label htmlFor="ent">Nom de l&apos;entreprise</label>
          <input id="ent" type="text" required value={entreprise}
                 onChange={(ev) => setEntreprise(ev.target.value)} />
        </div>
        <div className="champ">
          <label htmlFor="n">Votre nom</label>
          <input id="n" type="text" required value={nom}
                 onChange={(ev) => setNom(ev.target.value)} />
        </div>
        <div className="champ">
          <label htmlFor="s">SIRET (facultatif)</label>
          <input id="s" type="text" value={siret}
                 onChange={(ev) => setSiret(ev.target.value)} />
        </div>

        {erreur && <p className="err">{erreur}</p>}

        <button type="submit" className="envoyer"
                disabled={!entreprise.trim() || !nom.trim() || occupe}>
          {occupe ? 'Création…' : 'Créer'}
        </button>
      </form>
    </main>
  );
}
