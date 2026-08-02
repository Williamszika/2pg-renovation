-- =============================================================================
-- Fonctions appelées par les applications
--
-- Tout ce qui écrit un pointage passe par ici, en security definer. Le client
-- n'envoie qu'une position brute : c'est le serveur qui calcule la distance,
-- tranche si elle est dans la zone, et horodate. L'application n'a aucun moyen
-- de mentir sur l'une de ces trois choses.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Appareil : un compte, un téléphone
-- -----------------------------------------------------------------------------

create or replace function enregistrer_appareil(p_appareil_id text, p_appareil_nom text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u utilisateurs%rowtype;
begin
  select * into u from utilisateurs where id = auth.uid();
  if not found then raise exception 'compte inconnu'; end if;

  if u.appareil_id is null then
    -- Premier appareil : accepté d'office.
    update utilisateurs
       set appareil_id = p_appareil_id, appareil_nom = p_appareil_nom, appareil_valide_le = now()
     where id = auth.uid();
    return jsonb_build_object('autorise', true, 'premier', true);
  end if;

  if u.appareil_id = p_appareil_id then
    return jsonb_build_object('autorise', true, 'premier', false);
  end if;

  -- Changement d'appareil : le patron doit trancher.
  update utilisateurs set appareil_valide_le = null where id = auth.uid();
  return jsonb_build_object('autorise', false, 'motif', 'appareil_non_valide');
end $$;

create or replace function valider_appareil(p_utilisateur_id uuid, p_appareil_id text, p_appareil_nom text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not est_encadrant() then raise exception 'reserve a l''encadrement'; end if;
  update utilisateurs
     set appareil_id = p_appareil_id, appareil_nom = p_appareil_nom, appareil_valide_le = now()
   where id = p_utilisateur_id and entreprise_id = mon_entreprise_id();
end $$;

-- -----------------------------------------------------------------------------
-- Envoi d'une adresse
-- -----------------------------------------------------------------------------

create or replace function creer_mission(
  p_libelle      text,
  p_adresse      text,
  p_code_postal  text,
  p_ville        text,
  p_lat          double precision,
  p_lon          double precision,
  p_rayon_m      int,
  p_jour         date,
  p_heure_rdv    time,
  p_duree_min    int,
  p_chantier_id  uuid,
  p_destinataires uuid[]
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_ent uuid := mon_entreprise_id();
  v_dest uuid;
begin
  if not est_encadrant() then raise exception 'reserve a l''encadrement'; end if;
  if array_length(p_destinataires, 1) is null then raise exception 'aucun destinataire'; end if;

  insert into missions (entreprise_id, chantier_id, libelle, adresse, code_postal, ville,
                        position, rayon_m, jour, heure_rdv, duree_service_min, envoyee_par)
  values (v_ent, p_chantier_id, p_libelle, p_adresse, p_code_postal, p_ville,
          st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography,
          coalesce(p_rayon_m, 50), coalesce(p_jour, current_date),
          coalesce(p_heure_rdv, '08:00'), coalesce(p_duree_min, 480), auth.uid())
  returning id into v_id;

  foreach v_dest in array p_destinataires loop
    -- On ignore silencieusement un identifiant d'une autre entreprise plutôt
    -- que de faire échouer tout l'envoi.
    insert into mission_destinataires (mission_id, utilisateur_id)
    select v_id, v_dest
    where exists (select 1 from utilisateurs where id = v_dest and entreprise_id = v_ent and actif);
  end loop;

  return v_id;
end $$;

-- -----------------------------------------------------------------------------
-- Confirmation de présence
--
-- Deux conditions, et les deux comptent :
--   1. être dans le rayon ;
--   2. un GPS assez précis pour l'affirmer.
-- Un GPS annoncé à ± 60 m ne prouve pas une présence à 50 m. On refuse plutôt
-- que d'enregistrer une présence fausse — l'ouvrier passe alors par
-- signaler_probleme() et le bureau tranche.
-- -----------------------------------------------------------------------------

create or replace function confirmer_arrivee(
  p_mission_id uuid,
  p_lat        double precision,
  p_lon        double precision,
  p_precision  real default null,
  p_mock       boolean default false,
  p_root       boolean default false
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m missions%rowtype;
  d mission_destinataires%rowtype;
  v_dist int;
  v_pos geography;
begin
  select * into m from missions where id = p_mission_id and annulee_le is null;
  if not found then raise exception 'mission introuvable'; end if;

  select * into d from mission_destinataires
   where mission_id = p_mission_id and utilisateur_id = auth.uid();
  if not found then raise exception 'cette adresse ne vous a pas ete envoyee'; end if;
  if d.etat = 'confirme' then
    return jsonb_build_object('ok', true, 'deja', true);
  end if;

  v_pos  := st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography;
  v_dist := round(st_distance(v_pos, m.position))::int;

  if v_dist > m.rayon_m then
    return jsonb_build_object('ok', false, 'motif', 'trop_loin',
                              'distance_m', v_dist, 'rayon_m', m.rayon_m);
  end if;

  if p_precision is not null and p_precision > m.rayon_m then
    return jsonb_build_object('ok', false, 'motif', 'gps_insuffisant',
                              'precision_m', round(p_precision), 'rayon_m', m.rayon_m);
  end if;

  insert into pointages (entreprise_id, mission_id, utilisateur_id, type,
                         position, precision_m, distance_m, dans_zone,
                         mock_detecte, appareil_root)
  values (m.entreprise_id, m.id, auth.uid(), 'arrivee',
          v_pos, p_precision, v_dist, true, p_mock, p_root);

  update mission_destinataires
     set etat = 'confirme', confirme_le = now(), confirme_dist_m = v_dist,
         confirme_source = 'gps', motif = null
   where id = d.id;

  if p_mock or p_root then
    perform pousser_alerte(m.entreprise_id, m.id, auth.uid(), 'gps_suspect',
      'Position suspecte — ' || nom_utilisateur(auth.uid()),
      case when p_mock then 'Position simulee detectee. ' else '' end ||
      case when p_root then 'Appareil deverrouille (root/jailbreak).' else '' end);
  end if;

  -- Retard : comparé à l'heure de rendez-vous de la mission.
  if now()::time > m.heure_rdv + interval '15 minutes' then
    perform pousser_alerte(m.entreprise_id, m.id, auth.uid(), 'retard',
      nom_utilisateur(auth.uid()) || ' est arrive en retard',
      'Attendu a ' || to_char(m.heure_rdv, 'HH24:MI') ||
      ', arrive a ' || to_char(now(), 'HH24:MI') || ' (' || v_dist || ' m)');
  end if;

  return jsonb_build_object('ok', true, 'distance_m', v_dist, 'horodatage', now());
end $$;

-- L'ouvrier ne peut pas confirmer : il explique, le bureau tranche.
create or replace function signaler_probleme(
  p_mission_id uuid,
  p_motif      text,
  p_lat        double precision default null,
  p_lon        double precision default null,
  p_precision  real default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  m missions%rowtype;
  v_dist int;
begin
  select * into m from missions where id = p_mission_id;
  if not found then raise exception 'mission introuvable'; end if;
  if coalesce(length(trim(p_motif)), 0) < 3 then raise exception 'motif requis'; end if;

  if p_lat is not null then
    v_dist := round(st_distance(st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, m.position))::int;
  end if;

  update mission_destinataires
     set etat = 'probleme', motif = trim(p_motif)
   where mission_id = p_mission_id and utilisateur_id = auth.uid();

  perform pousser_alerte(m.entreprise_id, m.id, auth.uid(), 'gps_insuffisant',
    nom_utilisateur(auth.uid()) || ' ne peut pas confirmer sa presence',
    coalesce(v_dist || ' m', 'position inconnue') ||
    coalesce(' - precision +-' || round(p_precision) || ' m', '') ||
    ' - seuil ' || m.rayon_m || ' m : ' || trim(p_motif));
end $$;

-- Validation manuelle par le bureau : la présence est enregistrée, mais la
-- source le dit — « validation bureau », jamais « gps ».
create or replace function valider_presence(p_dest_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  d mission_destinataires%rowtype;
  m missions%rowtype;
begin
  if not est_encadrant() then raise exception 'reserve a l''encadrement'; end if;

  select * into d from mission_destinataires where id = p_dest_id;
  if not found then raise exception 'destinataire introuvable'; end if;
  select * into m from missions where id = d.mission_id and entreprise_id = mon_entreprise_id();
  if not found then raise exception 'mission hors de votre entreprise'; end if;
  if d.etat = 'confirme' then return jsonb_build_object('ok', true, 'deja', true); end if;

  insert into pointages (entreprise_id, mission_id, utilisateur_id, type,
                         dans_zone, motif)
  values (m.entreprise_id, m.id, d.utilisateur_id, 'arrivee',
          null, 'Presence validee par le bureau');

  update mission_destinataires
     set etat = 'confirme', confirme_le = now(), confirme_source = 'bureau',
         confirme_par = auth.uid(), confirme_dist_m = null
   where id = d.id;

  return jsonb_build_object('ok', true);
end $$;

-- -----------------------------------------------------------------------------
-- Pause, reprise, départ
--
-- Le départ tolère un rayon plus large que l'arrivée : on pointe souvent depuis
-- le trottoir ou la camionnette. Au-delà, le pointage passe quand même, mais
-- avec un motif et une alerte.
-- -----------------------------------------------------------------------------

create or replace function pointer(
  p_mission_id       uuid,
  p_type             type_pointage,
  p_lat              double precision default null,
  p_lon              double precision default null,
  p_precision        real default null,
  p_motif            text default null,
  p_hors_ligne       boolean default false,
  p_horodatage_local timestamptz default null,
  p_mock             boolean default false
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m missions%rowtype;
  v_pos geography;
  v_dist int;
  v_dans boolean;
  v_rayon_depart int;
  v_fin timestamptz;
  v_dernier type_pointage;
begin
  if p_type = 'arrivee' then raise exception 'utilisez confirmer_arrivee()'; end if;

  select * into m from missions where id = p_mission_id;
  if not found then raise exception 'mission introuvable'; end if;

  if not exists (select 1 from mission_destinataires
                 where mission_id = p_mission_id and utilisateur_id = auth.uid()
                   and etat = 'confirme') then
    raise exception 'presence non confirmee sur cette adresse';
  end if;

  -- Cohérence de la séquence : pas deux pauses de suite, pas de reprise sans pause.
  select type into v_dernier from pointages
   where mission_id = p_mission_id and utilisateur_id = auth.uid()
   order by horodatage desc limit 1;

  if v_dernier = 'depart' then raise exception 'journee deja cloturee'; end if;
  if p_type = 'pause_debut' and v_dernier = 'pause_debut' then raise exception 'pause deja en cours'; end if;
  if p_type = 'pause_fin' and v_dernier is distinct from 'pause_debut' then raise exception 'aucune pause en cours'; end if;

  if p_lat is not null then
    v_pos  := st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography;
    v_dist := round(st_distance(v_pos, m.position))::int;
  end if;

  if p_type = 'depart' then
    v_rayon_depart := greatest(100, m.rayon_m);
    v_dans := case when v_dist is null then null else v_dist <= v_rayon_depart end;
    if v_dans is false and coalesce(length(trim(p_motif)), 0) < 3 then
      return jsonb_build_object('ok', false, 'motif', 'motif_requis',
                                'distance_m', v_dist, 'rayon_m', v_rayon_depart);
    end if;
  end if;

  -- Une pause en cours est refermée d'office par le départ.
  if p_type = 'depart' and v_dernier = 'pause_debut' then
    insert into pointages (entreprise_id, mission_id, utilisateur_id, type, dans_zone, motif)
    values (m.entreprise_id, m.id, auth.uid(), 'pause_fin', null, 'Cloturee par le depart');
  end if;

  insert into pointages (entreprise_id, mission_id, utilisateur_id, type,
                         position, precision_m, distance_m, dans_zone,
                         motif, hors_ligne, horodatage_local, mock_detecte,
                         ecart_horloge_s)
  values (m.entreprise_id, m.id, auth.uid(), p_type,
          v_pos, p_precision, v_dist, v_dans,
          nullif(trim(coalesce(p_motif, '')), ''), p_hors_ligne, p_horodatage_local, p_mock,
          case when p_horodatage_local is not null
               then round(extract(epoch from (p_horodatage_local - now())))::int end);

  if p_type = 'depart' then
    if v_dans is false then
      perform pousser_alerte(m.entreprise_id, m.id, auth.uid(), 'hors_zone',
        'Depart pointe hors zone — ' || nom_utilisateur(auth.uid()),
        v_dist || ' m du chantier (tolerance ' || v_rayon_depart || ' m) : ' || coalesce(p_motif, ''));
    end if;

    select fin_prevue into v_fin from v_fin_prevue
     where mission_id = m.id and utilisateur_id = auth.uid();

    if v_fin is not null and now() < v_fin - interval '15 minutes' then
      perform pousser_alerte(m.entreprise_id, m.id, auth.uid(), 'depart_anticipe',
        'Depart avant la fin du service — ' || nom_utilisateur(auth.uid()),
        'Parti a ' || to_char(now(), 'HH24:MI') || ' pour une fin prevue a ' ||
        to_char(v_fin, 'HH24:MI'));
    end if;
  end if;

  return jsonb_build_object('ok', true, 'distance_m', v_dist, 'horodatage', now());
end $$;

-- -----------------------------------------------------------------------------
-- Utilitaires
-- -----------------------------------------------------------------------------

create or replace function nom_utilisateur(p_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nom, 'Inconnu') from utilisateurs where id = p_id
$$;

create or replace function pousser_alerte(
  p_ent uuid, p_mission uuid, p_user uuid, p_type type_alerte, p_titre text, p_detail text
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into alertes (entreprise_id, mission_id, utilisateur_id, type, titre, detail, cle)
  values (p_ent, p_mission, p_user, p_type, p_titre, p_detail,
          coalesce(p_mission::text, '-') || ':' || coalesce(p_user::text, '-') || ':' || p_type::text)
  on conflict (cle) do nothing;
end $$;

-- Fin de service attendue : le temps de service est une durée DUE sur le
-- chantier, pas un horaire fixe. Arrivé plus tard, l'ouvrier finit plus tard,
-- et les pauses la décalent d'autant.
create or replace view v_fin_prevue as
select
  j.mission_id,
  j.utilisateur_id,
  j.arrivee + make_interval(mins => j.duree_service_min + j.pause_min::int) as fin_prevue
from v_journees j
where j.arrivee is not null;

-- -----------------------------------------------------------------------------
-- Tâches planifiées (pg_cron)
-- -----------------------------------------------------------------------------

-- Coordonnées GPS : 2 mois. Durée de travail : 5 ans, elle reste intacte.
create or replace function purger_localisation()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update pointages
     set position = null, precision_m = null
   where horodatage < now() - interval '2 months' and position is not null;
  get diagnostics n = row_count;
  return n;
end $$;

-- Retards, absences, dépassements et oublis. À passer toutes les 5 minutes.
create or replace function verifier_alertes()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  -- Pas confirmé 30 min après l'heure de rendez-vous
  for r in
    select m.entreprise_id, m.id as mission_id, d.utilisateur_id, m.heure_rdv, m.libelle, m.ville
      from missions m
      join mission_destinataires d on d.mission_id = m.id
     where m.jour = current_date and m.annulee_le is null
       and d.etat in ('envoye', 'vue')
       and now()::time > m.heure_rdv + interval '30 minutes'
  loop
    perform pousser_alerte(r.entreprise_id, r.mission_id, r.utilisateur_id, 'absence',
      nom_utilisateur(r.utilisateur_id) || ' n''a pas confirme sa presence',
      'Attendu a ' || to_char(r.heure_rdv, 'HH24:MI') || ' — ' || r.libelle ||
      coalesce(', ' || r.ville, ''));
  end loop;

  -- Temps de service dépassé, toujours sur le chantier
  for r in
    select j.entreprise_id, j.mission_id, j.utilisateur_id, j.duree_service_min, f.fin_prevue
      from v_journees j
      join v_fin_prevue f on f.mission_id = j.mission_id and f.utilisateur_id = j.utilisateur_id
     where j.jour = current_date and j.en_cours and now() > f.fin_prevue
  loop
    perform pousser_alerte(r.entreprise_id, r.mission_id, r.utilisateur_id, 'service_depasse',
      'Temps de service depasse — ' || nom_utilisateur(r.utilisateur_id),
      (r.duree_service_min / 60) || ' h prevues, fin attendue a ' || to_char(r.fin_prevue, 'HH24:MI'));
  end loop;

  -- Journée restée ouverte 30 min après la fin attendue
  for r in
    select j.entreprise_id, j.mission_id, j.utilisateur_id, f.fin_prevue
      from v_journees j
      join v_fin_prevue f on f.mission_id = j.mission_id and f.utilisateur_id = j.utilisateur_id
     where j.jour = current_date and j.en_cours and now() > f.fin_prevue + interval '30 minutes'
  loop
    perform pousser_alerte(r.entreprise_id, r.mission_id, r.utilisateur_id, 'oubli_pointage',
      'Journee restee ouverte — ' || nom_utilisateur(r.utilisateur_id),
      'Aucun depart pointe 30 min apres la fin de service. A arbitrer.');
  end loop;
end $$;

-- À exécuter une fois, si pg_cron est activé sur le projet :
--   select cron.schedule('purge-localisation', '0 3 * * *', $$select purger_localisation()$$);
--   select cron.schedule('verifier-alertes',   '*/5 * * * *', $$select verifier_alertes()$$);
