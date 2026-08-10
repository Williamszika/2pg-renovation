-- =============================================================================
-- Bloquer un ouvrier, ou le retirer
--
-- La colonne « actif » existait depuis le début, mais n'était lue qu'à l'envoi
-- d'une adresse : un ouvrier désactivé disparaissait de la liste du patron et
-- ne recevait plus rien — tout en continuant à se connecter et à pointer sur
-- les adresses déjà reçues. Bloquer ne bloquait rien.
--
-- Le verrou est posé ici, dans la base, et non dans l'application : un client
-- modifié, une vieille version installée sur un téléphone, un appel direct à
-- l'API, tous se heurtent à la même règle.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Le compte qui appelle est-il actif ?
-- -----------------------------------------------------------------------------
create or replace function suis_actif()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select actif from utilisateurs where id = auth.uid()), false)
$$;

-- -----------------------------------------------------------------------------
-- Aucun pointage d'un compte bloqué
--
-- Un déclencheur plutôt qu'un contrôle recopié dans chaque fonction : toutes
-- les façons d'enregistrer une présence passent par cette table, y compris
-- celles qu'on écrira plus tard. Le contrôle porte sur le compte pointé, pas
-- sur l'appelant : le bureau ne doit pas pouvoir débloquer à la main la
-- présence de quelqu'un qu'il vient de bloquer.
-- -----------------------------------------------------------------------------
create or replace function refuser_pointage_inactif()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not coalesce((select actif from utilisateurs where id = new.utilisateur_id), false) then
    raise exception 'ce compte est bloque : aucun pointage possible'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists pointage_compte_actif on pointages;
create trigger pointage_compte_actif
  before insert on pointages
  for each row execute function refuser_pointage_inactif();

-- -----------------------------------------------------------------------------
-- Plus d'adresse du jour pour un compte bloqué
--
-- Le corps est celui de 0007, avec la garde en tête. Cette fonction s'exécute
-- en « security definer » et ne passe donc pas par les règles de sécurité :
-- le contrôle doit y être écrit.
-- -----------------------------------------------------------------------------
create or replace function ma_mission_du_jour()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not suis_actif() then null
              when m.id is null then null else jsonb_build_object(
    'destinataire_id', d.id,
    'etat',            d.etat,
    'confirme_le',     d.confirme_le,
    'confirme_dist_m', d.confirme_dist_m,
    'confirme_source', d.confirme_source,
    'motif',           d.motif,
    'mission', jsonb_build_object(
      'id',                m.id,
      'libelle',           m.libelle,
      'adresse',           m.adresse,
      'code_postal',       m.code_postal,
      'ville',             m.ville,
      'lat',               st_y(m.position::geometry),
      'lon',               st_x(m.position::geometry),
      'rayon_m',           m.rayon_m,
      'jour',              m.jour,
      'heure_rdv',         m.heure_rdv,
      'duree_service_min', m.duree_service_min
    ),
    'journee', (
      select jsonb_build_object(
        'arrivee',   j.arrivee,
        'depart',    j.depart,
        'pause_min', j.pause_min,
        'duree_min', j.duree_min,
        'en_cours',  j.en_cours,
        'en_pause',  coalesce((
          select p.type = 'pause_debut' from pointages p
           where p.mission_id = m.id and p.utilisateur_id = auth.uid()
           order by p.seq desc limit 1
        ), false)
      )
      from v_journees j
      where j.mission_id = m.id and j.utilisateur_id = auth.uid()
    )
  ) end
  from mission_destinataires d
  join missions m on m.id = d.mission_id
  where d.utilisateur_id = auth.uid()
    and m.jour = current_date
    and m.annulee_le is null
  order by m.heure_rdv
  limit 1
$$;

-- -----------------------------------------------------------------------------
-- Bloquer, débloquer
-- -----------------------------------------------------------------------------
create or replace function definir_actif(p_utilisateur_id uuid, p_actif boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u utilisateurs%rowtype;
begin
  if not est_encadrant() then raise exception 'reserve a l''encadrement'; end if;
  if p_utilisateur_id = auth.uid() then
    raise exception 'on ne peut pas se bloquer soi-meme';
  end if;

  select * into u from utilisateurs
   where id = p_utilisateur_id and entreprise_id = mon_entreprise_id();
  if not found then raise exception 'compte introuvable dans cette entreprise'; end if;

  update utilisateurs set actif = p_actif where id = p_utilisateur_id;

  -- Un blocage doit prendre effet tout de suite, y compris sur une journée
  -- commencée : on retire les adresses du jour qu'il n'a pas encore
  -- confirmées. Celles déjà confirmées restent, elles sont des heures dues.
  if not p_actif then
    delete from mission_destinataires d
     using missions m
     where d.mission_id = m.id
       and d.utilisateur_id = p_utilisateur_id
       and m.jour >= current_date
       and d.etat <> 'confirme';
  end if;

  return jsonb_build_object('ok', true, 'nom', u.nom, 'actif', p_actif);
end $$;

-- -----------------------------------------------------------------------------
-- Retirer définitivement
--
-- Possible seulement tant que la personne n'a aucun pointage. Dès qu'elle en a
-- un, ses heures relèvent de la conservation de cinq ans et la base refuse de
-- les perdre ; on bloque le compte à la place, ce qui produit le même effet
-- pour l'intéressé.
--
-- Ceci retire la fiche d'entreprise. Le compte de connexion, lui, vit dans le
-- schéma d'authentification et ne peut être supprimé qu'avec une clé
-- d'administration : il subsiste donc, mais ne mène nulle part — l'application
-- déconnecte tout compte sans fiche.
-- -----------------------------------------------------------------------------
create or replace function retirer_utilisateur(p_utilisateur_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  u utilisateurs%rowtype;
  v_n int;
begin
  if not est_encadrant() then raise exception 'reserve a l''encadrement'; end if;
  if p_utilisateur_id = auth.uid() then
    raise exception 'on ne peut pas se retirer soi-meme';
  end if;

  select * into u from utilisateurs
   where id = p_utilisateur_id and entreprise_id = mon_entreprise_id();
  if not found then raise exception 'compte introuvable dans cette entreprise'; end if;

  select count(*) into v_n from pointages where utilisateur_id = p_utilisateur_id;
  if v_n > 0 then
    update utilisateurs set actif = false where id = p_utilisateur_id;
    return jsonb_build_object('ok', false, 'motif', 'heures_a_conserver',
                              'nom', u.nom, 'pointages', v_n);
  end if;

  delete from mission_destinataires where utilisateur_id = p_utilisateur_id;
  delete from utilisateurs where id = p_utilisateur_id;
  return jsonb_build_object('ok', true, 'nom', u.nom);
end $$;
