-- =============================================================================
-- Qui a accès à l'application, et dans quel état
--
-- À coller dans le SQL Editor de Supabase.
--
-- Les mots de passe n'apparaissent pas et n'apparaîtront jamais : Supabase ne
-- stocke qu'une empreinte bcrypt, une transformation qu'on ne sait pas
-- inverser. Un mot de passe oublié se remplace, il ne se retrouve pas.
-- =============================================================================

select
  a.email                                                   as "E-mail",
  coalesce(u.nom, '— compte non rattaché —')                as "Nom",
  coalesce(u.role::text, '—')                               as "Rôle",
  case
    when u.id is null                then 'NE PEUT PAS ENTRER — aucune fiche'
    when not u.actif                 then 'DÉSACTIVÉ'
    when a.email_confirmed_at is null then 'BLOQUÉ — e-mail non confirmé'
    else 'actif'
  end                                                       as "État",
  to_char(a.last_sign_in_at, 'DD/MM/YYYY HH24:MI')          as "Dernière connexion",
  to_char(a.created_at, 'DD/MM/YYYY')                       as "Créé le"
from auth.users a
left join utilisateurs u on u.id = a.id
order by
  case coalesce(u.role::text, 'zzz')
    when 'patron' then 1 when 'chef_equipe' then 2 when 'ouvrier' then 3 else 4
  end,
  u.nom nulls last;

-- -----------------------------------------------------------------------------
-- Lire la colonne « État »
-- -----------------------------------------------------------------------------
-- actif                          rien à faire
--
-- BLOQUÉ — e-mail non confirmé   le compte existe mais la connexion échoue.
--                                Authentication > Sign In / Providers > Email
--                                > décocher « Confirm email », puis recréer le
--                                compte, ou confirmer celui-ci à la main dans
--                                Authentication > Users.
--
-- NE PEUT PAS ENTRER             un compte de connexion sans fiche d'entreprise.
--                                L'application le déconnecte avec « Ce compte
--                                n'est rattaché à aucune entreprise ». Se
--                                produit quand quelqu'un s'inscrit tout seul.
--                                Voir le rattachement plus bas.
--
-- DÉSACTIVÉ                      retiré volontairement. Ses pointages passés
--                                restent : ils sont soumis à la conservation
--                                de 5 ans, la base refuse de les supprimer.

-- -----------------------------------------------------------------------------
-- Changer un mot de passe
-- -----------------------------------------------------------------------------
-- Pas en SQL. Authentication > Users > les trois points au bout de la ligne :
--   « Send password recovery »  envoie un lien à l'intéressé
--   « Reset password »          en fixe un nouveau, à lui transmettre
--
-- Le patron peut aussi simplement recréer le compte depuis le tableau de bord
-- avec un nouveau mot de passe provisoire.

-- -----------------------------------------------------------------------------
-- Rattacher un compte resté orphelin — remplacer l'adresse
-- -----------------------------------------------------------------------------
-- insert into utilisateurs (id, entreprise_id, nom, role)
-- select a.id,
--        (select id from entreprises order by cree_le limit 1),
--        'Nom Prénom', 'ouvrier'
--   from auth.users a
--  where a.email = 'a.remplacer@exemple.fr'
-- on conflict (id) do update set nom = excluded.nom, role = excluded.role
-- returning nom, role;

-- -----------------------------------------------------------------------------
-- Retirer quelqu'un — sans effacer ses heures
-- -----------------------------------------------------------------------------
-- update utilisateurs u
--    set actif = false
--   from auth.users a
--  where a.id = u.id and a.email = 'parti@exemple.fr'
-- returning u.nom, u.actif;
