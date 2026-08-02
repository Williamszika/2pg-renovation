'use client';

import { useState } from 'react';
import { clientNavigateur } from '@/lib/supabase-navigateur';
import type { Utilisateur } from '@/lib/types';

export default function Equipe({
  equipe,
  onChange,
}: {
  equipe: Utilisateur[];
  onChange: () => void;
}) {
  const sb = clientNavigateur();
  const [ouvert, setOuvert] = useState(false);
  const [nom, setNom] = useState('');
  const [email, setEmail] = useState('');
  const [mdp, setMdp] = useState('');
  const [occupe, setOccupe] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function creer() {
    setOccupe(true);
    setMsg(null);
    try {
      // La création d'un compte auth demande la clé service_role, qui ne doit
      // jamais atteindre le navigateur : elle vit dans la route serveur.
      const r = await fetch('/api/ouvriers', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ nom, email, motDePasse: mdp }),
      });
      const j = await r.json();
      if (!r.ok) throw new Error(j.erreur ?? 'Création impossible');
      setMsg(`${nom} peut se connecter avec ${email}.`);
      setNom(''); setEmail(''); setMdp('');
      onChange();
    } catch (e) {
      setMsg((e as Error).message);
    } finally {
      setOccupe(false);
    }
  }

  async function validerAppareil(u: Utilisateur) {
    // Le téléphone a déjà enregistré son identifiant : on ne fait que lever le
    // blocage en réattribuant l'appareil courant.
    const { error } = await sb
      .from('utilisateurs')
      .update({ appareil_valide_le: new Date().toISOString() })
      .eq('id', u.id);
    if (error) { alert(error.message); return; }
    onChange();
  }

  const pret = nom.trim().length > 1 && /.+@.+\..+/.test(email) && mdp.length >= 8 && !occupe;

  return (
    <section className="panel">
      <div className="panel-head">
        <h2>Équipe · {equipe.length}</h2>
        <button type="button" className="btn-x" onClick={() => setOuvert((o) => !o)}>
          {ouvert ? 'Fermer' : 'Ajouter un ouvrier'}
        </button>
      </div>

      {ouvert && (
        <div className="corps" style={{ borderBottom: '1px solid var(--trait)' }}>
          <div className="deux">
            <div className="champ">
              <label htmlFor="n">Nom complet</label>
              <input id="n" type="text" value={nom} onChange={(e) => setNom(e.target.value)} />
            </div>
            <div className="champ">
              <label htmlFor="e">Adresse e-mail</label>
              <input
                id="e" type="email" autoComplete="off"
                value={email} onChange={(e) => setEmail(e.target.value)}
              />
            </div>
          </div>
          <div className="champ">
            <label htmlFor="p">Mot de passe provisoire</label>
            <input
              id="p" type="text" autoComplete="off"
              value={mdp} onChange={(e) => setMdp(e.target.value)}
              placeholder="8 caractères minimum"
            />
            <p className="aide">
              À remettre à l&apos;ouvrier avec l&apos;adresse e-mail. C&apos;est avec ces deux
              informations qu&apos;il se connecte à l&apos;application.
            </p>
          </div>
          {msg && <p className="aide">{msg}</p>}
          <button type="button" className="envoyer" disabled={!pret} onClick={creer}>
            {occupe ? 'Création…' : 'Créer le compte'}
          </button>
        </div>
      )}

      <div className="tw">
        <table>
          <thead>
            <tr>
              <th>Nom</th><th>Rôle</th><th>Téléphone</th><th>Appareil</th><th />
            </tr>
          </thead>
          <tbody>
            {equipe.map((u) => (
              <tr key={u.id}>
                <td><b>{u.nom}</b></td>
                <td>
                  {u.role === 'patron' ? 'Patron' : u.role === 'chef_equipe' ? "Chef d'équipe" : 'Ouvrier'}
                </td>
                <td>{u.telephone ?? '—'}</td>
                <td>
                  {u.appareil_nom ?? '—'}
                  {u.appareil_nom && !u.appareil_valide_le && (
                    <span className="pastille bad" style={{ marginLeft: 8 }}>À valider</span>
                  )}
                </td>
                <td className="n">
                  {u.appareil_nom && !u.appareil_valide_le && (
                    <button type="button" className="btn-x solide" onClick={() => validerAppareil(u)}>
                      Valider l&apos;appareil
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {equipe.length === 0 && (
              <tr><td colSpan={5} className="vide-msg">Aucun compte pour l&apos;instant.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}
