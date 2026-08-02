-- =============================================================================
-- Amorçage
--
-- Le tout premier compte crée son entreprise et devient patron. Les ouvriers
-- sont ensuite créés depuis le tableau de bord, qui passe par l'API Admin
-- (clé service_role, côté serveur) puis appelle rattacher_utilisateur().
-- =============================================================================

create or replace function bootstrap_entreprise(p_nom text, p_mon_nom text, p_siret text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_ent uuid;
begin
  if auth.uid() is null then raise exception 'authentification requise'; end if;
  if exists (select 1 from utilisateurs where id = auth.uid()) then
    raise exception 'ce compte est deja rattache a une entreprise';
  end if;

  insert into entreprises (nom, siret) values (p_nom, p_siret) returning id into v_ent;
  insert into utilisateurs (id, entreprise_id, nom, role)
  values (auth.uid(), v_ent, p_mon_nom, 'patron');
  return v_ent;
end $$;

-- Appelée par le tableau de bord juste après la création du compte auth de
-- l'ouvrier (côté serveur, avec la clé service_role).
create or replace function rattacher_utilisateur(
  p_user_id uuid, p_nom text, p_role role_utilisateur, p_telephone text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not est_encadrant() then raise exception 'reserve a l''encadrement'; end if;
  insert into utilisateurs (id, entreprise_id, nom, role, telephone)
  values (p_user_id, mon_entreprise_id(), p_nom, coalesce(p_role, 'ouvrier'), p_telephone)
  on conflict (id) do update
    set nom = excluded.nom, role = excluded.role, telephone = excluded.telephone;
end $$;

-- Un compte supprimé côté auth emporte sa ligne utilisateurs (ON DELETE CASCADE),
-- mais ses pointages restent : ils sont soumis à l'obligation de conservation
-- de 5 ans. D'où le ON DELETE RESTRICT sur pointages.utilisateur_id — désactiver
-- un compte se fait avec actif = false, pas en le supprimant.

-- -----------------------------------------------------------------------------
-- Jeu d'essai — à exécuter seulement sur un projet de test
-- -----------------------------------------------------------------------------
-- select bootstrap_entreprise('2PG Renovation', 'Votre nom');
--
-- insert into chantiers (entreprise_id, libelle, client_nom, adresse, code_postal, ville,
--                        position, heures_devisees, statut)
-- values (mon_entreprise_id(), 'Mme Durand — salle de bains', 'Mme Durand',
--         '12 rue des Lilas', '31700', 'Blagnac',
--         st_setsrid(st_makepoint(1.3897, 43.6357), 4326)::geography, 40, 'en_cours');
