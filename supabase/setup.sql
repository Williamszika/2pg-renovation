-- =============================================================================
-- 2PG Pointage — installation en une seule fois
--
-- FICHIER GENERE. Ne le modifiez pas a la main : il est produit par
-- ./build-setup.sh a partir de migrations/*.sql, qui restent la source de
-- verite.
--
-- Comment s'en servir : Supabase > SQL Editor > New query > tout coller > Run.
-- Puis executez verification.sql pour controler l'installation.
-- =============================================================================


-- ####################  migrations/0001_schema.sql  ####################

-- =============================================================================
-- 2PG Pointage — schéma
--
-- Principe : le téléphone déclare, le serveur décide.
-- Le client envoie une position brute ; le serveur calcule la distance, tranche
-- si elle est dans la zone, et horodate. Rien de tout cela n'est calculé dans
-- l'application : un ouvrier qui la décompile ne peut rien contourner.
--
-- Minimisation : les coordonnées brutes sont purgées à 2 mois (doctrine CNIL
-- sur les données de localisation), alors que la durée de travail est conservée
-- 5 ans (obligations de paie). Deux durées sur la même ligne.
-- =============================================================================

create extension if not exists postgis;
create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Entreprises et utilisateurs
-- -----------------------------------------------------------------------------

create table entreprises (
  id                uuid primary key default gen_random_uuid(),
  nom               text not null,
  siret             text,
  rayon_defaut_m    int  not null default 50  check (rayon_defaut_m between 20 and 1000),
  duree_defaut_min  int  not null default 480 check (duree_defaut_min between 30 and 720),
  cree_le           timestamptz not null default now()
);

create type role_utilisateur as enum ('patron', 'chef_equipe', 'ouvrier');

create table utilisateurs (
  id             uuid primary key references auth.users(id) on delete cascade,
  entreprise_id  uuid not null references entreprises(id) on delete cascade,
  nom            text not null,
  role           role_utilisateur not null default 'ouvrier',
  telephone      text,
  actif          boolean not null default true,

  -- Un compte est lié à un appareil : empêche de pointer pour un collègue.
  -- Le premier appareil qui se connecte s'enregistre ; tout changement
  -- ultérieur doit être validé par le patron (appareil_valide_le remis à null).
  appareil_id         text,
  appareil_nom        text,
  appareil_valide_le  timestamptz,

  -- Jeton Expo pour les notifications push.
  push_token     text,
  cree_le        timestamptz not null default now()
);

create index on utilisateurs (entreprise_id, actif);

-- -----------------------------------------------------------------------------
-- Chantiers — le référentiel durable, qui porte le devis
-- -----------------------------------------------------------------------------

create type statut_chantier as enum ('prevu', 'en_cours', 'termine', 'annule');

create table chantiers (
  id              uuid primary key default gen_random_uuid(),
  entreprise_id   uuid not null references entreprises(id) on delete cascade,
  libelle         text not null,
  client_nom      text,
  adresse         text not null,
  code_postal     text,
  ville           text,
  position        geography(point, 4326),
  heures_devisees numeric(6,2),
  statut          statut_chantier not null default 'prevu',
  cree_le         timestamptz not null default now()
);

create index on chantiers (entreprise_id, statut);
create index on chantiers using gist (position);

-- -----------------------------------------------------------------------------
-- Missions — un envoi d'adresse à une ou plusieurs personnes, pour un jour
-- -----------------------------------------------------------------------------

create table missions (
  id                uuid primary key default gen_random_uuid(),
  entreprise_id     uuid not null references entreprises(id) on delete cascade,
  chantier_id       uuid references chantiers(id) on delete set null,

  libelle           text not null,
  adresse           text not null,
  code_postal       text,
  ville             text,
  position          geography(point, 4326) not null,

  -- Rayon PAR MISSION : une maison isolée tolère 30 m, un immeuble du centre a
  -- besoin de 100 m à cause de la réflexion du signal sur les façades. Un rayon
  -- unique produit des fausses alertes, et les fausses alertes tuent la
  -- confiance dans l'outil en deux semaines.
  rayon_m           int not null default 50 check (rayon_m between 20 and 1000),

  jour              date not null default current_date,
  heure_rdv         time not null default '08:00',

  -- Durée due sur le chantier, pas un horaire fixe : arrivé plus tard,
  -- l'ouvrier finit plus tard, et les pauses la décalent d'autant.
  duree_service_min int not null default 480 check (duree_service_min between 30 and 720),

  envoyee_par       uuid not null references utilisateurs(id) on delete restrict,
  envoyee_le        timestamptz not null default now(),
  annulee_le        timestamptz
);

create index on missions (entreprise_id, jour desc);
create index on missions using gist (position);

create type etat_destinataire as enum ('envoye', 'vue', 'confirme', 'probleme', 'refuse');
create type source_confirmation as enum ('gps', 'bureau');

create table mission_destinataires (
  id              uuid primary key default gen_random_uuid(),
  mission_id      uuid not null references missions(id) on delete cascade,
  utilisateur_id  uuid not null references utilisateurs(id) on delete cascade,

  etat            etat_destinataire not null default 'envoye',
  vue_le          timestamptz,

  confirme_le     timestamptz,
  confirme_dist_m int,
  confirme_source source_confirmation,
  confirme_par    uuid references utilisateurs(id) on delete set null, -- si validation bureau

  motif           text,       -- renseigné quand etat = 'probleme'
  unique (mission_id, utilisateur_id)
);

create index on mission_destinataires (utilisateur_id, etat);

-- -----------------------------------------------------------------------------
-- Pointages — la trace brute, jamais modifiable
-- -----------------------------------------------------------------------------

create type type_pointage as enum ('arrivee', 'pause_debut', 'pause_fin', 'depart');

create table pointages (
  id              uuid primary key default gen_random_uuid(),
  entreprise_id   uuid not null references entreprises(id) on delete cascade,
  mission_id      uuid not null references missions(id) on delete restrict,
  utilisateur_id  uuid not null references utilisateurs(id) on delete restrict,
  type            type_pointage not null,

  -- HORODATAGE SERVEUR. L'heure du téléphone est modifiable par son porteur :
  -- elle n'est conservée qu'à titre indicatif, avec l'écart mesuré, pour
  -- arbitrer les pointages remontés après une coupure réseau.
  horodatage       timestamptz not null default now(),
  hors_ligne       boolean not null default false,
  horodatage_local timestamptz,
  ecart_horloge_s  int,

  -- Coordonnées brutes : PURGÉES À 2 MOIS (voir purger_localisation()).
  position       geography(point, 4326),
  precision_m    real,

  -- Résultat de la vérification, calculé côté serveur, CONSERVÉ 5 ANS.
  -- En régime courant le patron ne voit que cela : « à 23 m du chantier ».
  distance_m     int,
  dans_zone      boolean,

  -- Anti-fraude
  mock_detecte   boolean not null default false,
  appareil_root  boolean not null default false,

  -- Obligatoire hors zone : on n'empêche jamais un pointage, sinon un ouvrier
  -- de bonne foi dans un sous-sol sans GPS ne peut plus déclarer ses heures.
  motif          text,
  cree_le        timestamptz not null default now(),

  constraint motif_requis_hors_zone
    check (dans_zone is not false or motif is not null)
);

create index on pointages (utilisateur_id, horodatage desc);
create index on pointages (mission_id, horodatage);
create index on pointages (entreprise_id, horodatage desc);

-- -----------------------------------------------------------------------------
-- Alertes
-- -----------------------------------------------------------------------------

create type type_alerte as enum (
  'retard', 'absence', 'hors_zone', 'gps_insuffisant',
  'service_depasse', 'depart_anticipe', 'oubli_pointage', 'gps_suspect'
);

create table alertes (
  id              uuid primary key default gen_random_uuid(),
  entreprise_id   uuid not null references entreprises(id) on delete cascade,
  mission_id      uuid references missions(id) on delete cascade,
  utilisateur_id  uuid references utilisateurs(id) on delete set null,
  type            type_alerte not null,
  titre           text not null,
  detail          text,
  lue             boolean not null default false,
  cree_le         timestamptz not null default now(),
  -- Une même alerte ne se répète pas : la clé porte la mission, la personne
  -- et le type.
  cle             text not null,
  unique (cle)
);

create index on alertes (entreprise_id, lue, cree_le desc);

-- -----------------------------------------------------------------------------
-- Journées consolidées — dérivées des pointages, pour la paie et la marge
-- -----------------------------------------------------------------------------

create or replace view v_journees as
with bornes as (
  select
    p.mission_id,
    p.utilisateur_id,
    p.entreprise_id,
    min(p.horodatage) filter (where p.type = 'arrivee') as arrivee,
    max(p.horodatage) filter (where p.type = 'depart')  as depart
  from pointages p
  group by 1, 2, 3
),
pauses as (
  -- Somme des intervalles pause_debut → pause_fin, appariés dans l'ordre.
  select
    d.mission_id, d.utilisateur_id,
    coalesce(sum(extract(epoch from (f.horodatage - d.horodatage)) / 60), 0)::numeric as pause_min
  from (
    select mission_id, utilisateur_id, horodatage,
           row_number() over (partition by mission_id, utilisateur_id order by horodatage) as n
    from pointages where type = 'pause_debut'
  ) d
  left join (
    select mission_id, utilisateur_id, horodatage,
           row_number() over (partition by mission_id, utilisateur_id order by horodatage) as n
    from pointages where type = 'pause_fin'
  ) f on f.mission_id = d.mission_id and f.utilisateur_id = d.utilisateur_id and f.n = d.n
  group by 1, 2
)
select
  b.entreprise_id,
  b.mission_id,
  b.utilisateur_id,
  m.chantier_id,
  m.jour,
  m.duree_service_min,
  b.arrivee,
  b.depart,
  coalesce(pa.pause_min, 0) as pause_min,
  case when b.arrivee is not null then
    greatest(0, extract(epoch from (coalesce(b.depart, now()) - b.arrivee)) / 60
                - coalesce(pa.pause_min, 0))
  end::numeric as duree_min,
  b.depart is null as en_cours
from bornes b
join missions m on m.id = b.mission_id
left join pauses pa on pa.mission_id = b.mission_id and pa.utilisateur_id = b.utilisateur_id;

-- Devisé vs réalisé : la vue qui fait passer l'outil de « surveillance » à
-- « pilotage ».
create or replace view v_marge_chantier as
select
  c.id,
  c.entreprise_id,
  c.libelle,
  c.client_nom,
  c.statut,
  c.heures_devisees,
  round(coalesce(sum(j.duree_min), 0) / 60.0, 2) as heures_realisees,
  case when c.heures_devisees > 0 then
    round(((coalesce(sum(j.duree_min), 0) / 60.0) - c.heures_devisees)
          / c.heures_devisees * 100, 1)
  end as ecart_pct
from chantiers c
left join v_journees j on j.chantier_id = c.id
group by c.id;

-- ####################  migrations/0002_rls.sql  ####################

-- =============================================================================
-- Sécurité au niveau ligne
--
-- Un ouvrier ne voit QUE ce qui le concerne. Le patron voit son entreprise, et
-- rien au-delà. Ces règles vivent dans la base : elles s'appliquent quel que
-- soit le client — application mobile, tableau de bord, ou requête forgée à la
-- main avec la clé publique.
-- =============================================================================

alter table entreprises           enable row level security;
alter table utilisateurs          enable row level security;
alter table chantiers             enable row level security;
alter table missions              enable row level security;
alter table mission_destinataires enable row level security;
alter table pointages             enable row level security;
alter table alertes               enable row level security;

-- security definer : ces fonctions lisent utilisateurs sans repasser par RLS,
-- ce qui éviterait une récursion infinie sur ses propres politiques.
create or replace function mon_entreprise_id()
returns uuid language sql stable security definer set search_path = public as $$
  select entreprise_id from utilisateurs where id = auth.uid()
$$;

create or replace function est_encadrant()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('patron', 'chef_equipe') from utilisateurs where id = auth.uid()), false)
$$;

-- Ces deux fonctions cassent une récursion : la politique de `missions` doit
-- savoir si l'utilisateur est destinataire, et celle de `mission_destinataires`
-- doit connaître l'entreprise de la mission. Chacune interrogeant la table de
-- l'autre, Postgres boucle et refuse la requête. En security definer, la
-- vérification se fait hors RLS et la boucle disparaît.
create or replace function suis_destinataire(p_mission_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from mission_destinataires
     where mission_id = p_mission_id and utilisateur_id = auth.uid()
  )
$$;

create or replace function mission_de_mon_entreprise(p_mission_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from missions
     where id = p_mission_id and entreprise_id = mon_entreprise_id()
  )
$$;

-- --- entreprises -------------------------------------------------------------

create policy entreprise_lecture on entreprises
  for select using (id = mon_entreprise_id());
create policy entreprise_ecriture on entreprises
  for update using (id = mon_entreprise_id() and est_encadrant());

-- --- utilisateurs ------------------------------------------------------------

-- Tout le monde voit ses collègues (nom + rôle) : l'ouvrier a besoin de savoir
-- qui d'autre est sur son chantier, le patron de composer ses envois.
create policy utilisateurs_lecture on utilisateurs
  for select using (entreprise_id = mon_entreprise_id());

-- Chacun met à jour sa propre ligne (jeton push, enregistrement d'appareil).
create policy utilisateurs_soi on utilisateurs
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy utilisateurs_admin on utilisateurs
  for all using (entreprise_id = mon_entreprise_id() and est_encadrant());

-- --- chantiers ---------------------------------------------------------------

create policy chantiers_lecture on chantiers
  for select using (entreprise_id = mon_entreprise_id());
create policy chantiers_ecriture on chantiers
  for all using (entreprise_id = mon_entreprise_id() and est_encadrant())
  with check (entreprise_id = mon_entreprise_id() and est_encadrant());

-- --- missions ----------------------------------------------------------------

-- Un ouvrier ne voit que les missions qui lui ont été envoyées. Il ne sait pas
-- où travaillent ses collègues s'il n'y est pas affecté.
create policy missions_lecture on missions
  for select using (
    entreprise_id = mon_entreprise_id()
    and (est_encadrant() or suis_destinataire(id))
  );

create policy missions_ecriture on missions
  for all using (entreprise_id = mon_entreprise_id() and est_encadrant())
  with check (entreprise_id = mon_entreprise_id() and est_encadrant());

-- --- destinataires -----------------------------------------------------------

create policy dest_lecture on mission_destinataires
  for select using (
    utilisateur_id = auth.uid()
    or (est_encadrant() and mission_de_mon_entreprise(mission_id))
  );

create policy dest_encadrant on mission_destinataires
  for all using (est_encadrant() and mission_de_mon_entreprise(mission_id))
  with check (est_encadrant() and mission_de_mon_entreprise(mission_id));

-- L'ouvrier ne peut modifier que l'accusé de lecture. La confirmation de
-- présence passe obligatoirement par la RPC confirmer_arrivee(), qui recalcule
-- la distance côté serveur.
create policy dest_accuse_lecture on mission_destinataires
  for update using (utilisateur_id = auth.uid() and etat = 'envoye')
  with check (utilisateur_id = auth.uid() and etat = 'vue');

-- --- pointages ---------------------------------------------------------------

create policy pointages_lecture on pointages
  for select using (
    entreprise_id = mon_entreprise_id()
    and (utilisateur_id = auth.uid() or est_encadrant())
  );

-- Volontairement : AUCUNE politique INSERT, UPDATE ni DELETE.
-- Les pointages ne s'écrivent que par les RPC ci-après, en security definer.
-- Le Code du travail exige un système « fiable et infalsifiable » (art. D3171-x) :
-- une correction se fait par un pointage rectificatif tracé, jamais par une
-- modification en place.

-- --- alertes -----------------------------------------------------------------

create policy alertes_encadrement on alertes
  for all using (entreprise_id = mon_entreprise_id() and est_encadrant())
  with check (entreprise_id = mon_entreprise_id() and est_encadrant());

-- ####################  migrations/0003_rpc.sql  ####################

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

-- ####################  migrations/0004_bootstrap.sql  ####################

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

-- ####################  migrations/0005_lecture.sql  ####################

-- =============================================================================
-- Vues et fonctions de lecture
--
-- Une colonne geography sort de l'API REST en WKB hexadécimal, illisible côté
-- client. On expose donc lat/lon en nombres, et les écrans lisent ces vues
-- plutôt que les tables.
-- =============================================================================

create or replace view v_missions as
select
  m.id, m.entreprise_id, m.chantier_id,
  m.libelle, m.adresse, m.code_postal, m.ville,
  st_y(m.position::geometry) as lat,
  st_x(m.position::geometry) as lon,
  m.rayon_m, m.jour, m.heure_rdv, m.duree_service_min,
  m.envoyee_par, m.envoyee_le, m.annulee_le
from missions m;

-- Les vues n'héritent pas des politiques RLS de leurs tables : sans
-- security_invoker, elles s'exécuteraient avec les droits du propriétaire et
-- laisseraient fuiter les missions des autres entreprises.
alter view v_missions             set (security_invoker = true);
alter view v_journees             set (security_invoker = true);
alter view v_fin_prevue           set (security_invoker = true);
alter view v_marge_chantier       set (security_invoker = true);

-- -----------------------------------------------------------------------------
-- Ce que l'ouvrier voit : son adresse du jour, rien d'autre
-- -----------------------------------------------------------------------------

create or replace function ma_mission_du_jour()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when m.id is null then null else jsonb_build_object(
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
           order by p.horodatage desc limit 1
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

-- Accusé de lecture, appelé à l'ouverture de l'écran.
create or replace function marquer_vue(p_mission_id uuid)
returns void language sql security definer set search_path = public as $$
  update mission_destinataires
     set etat = 'vue', vue_le = now()
   where mission_id = p_mission_id and utilisateur_id = auth.uid() and etat = 'envoye'
$$;

create or replace function enregistrer_push_token(p_token text)
returns void language sql security definer set search_path = public as $$
  update utilisateurs set push_token = p_token where id = auth.uid()
$$;

-- -----------------------------------------------------------------------------
-- Ce que le patron voit : le suivi d'une mission, en une requête
-- -----------------------------------------------------------------------------

create or replace function suivi_mission(p_mission_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'mission', (select to_jsonb(v) from v_missions v where v.id = m.id),
    'destinataires', coalesce((
      select jsonb_agg(jsonb_build_object(
        'destinataire_id', d.id,
        'utilisateur_id',  u.id,
        'nom',             u.nom,
        'role',            u.role,
        'etat',            d.etat,
        'vue_le',          d.vue_le,
        'confirme_le',     d.confirme_le,
        'confirme_dist_m', d.confirme_dist_m,
        'confirme_source', d.confirme_source,
        'motif',           d.motif,
        'arrivee',         j.arrivee,
        'depart',          j.depart,
        'pause_min',       j.pause_min,
        'duree_min',       j.duree_min,
        'en_cours',        j.en_cours,
        'fin_prevue',      f.fin_prevue
      ) order by u.nom)
      from mission_destinataires d
      join utilisateurs u on u.id = d.utilisateur_id
      left join v_journees j on j.mission_id = d.mission_id and j.utilisateur_id = d.utilisateur_id
      left join v_fin_prevue f on f.mission_id = d.mission_id and f.utilisateur_id = d.utilisateur_id
      where d.mission_id = m.id
    ), '[]'::jsonb)
  )
  from missions m
  where m.id = p_mission_id
    and m.entreprise_id = mon_entreprise_id()
    and est_encadrant()
$$;

-- Les missions du jour, pour la page d'accueil du tableau de bord.
create or replace function missions_du_jour(p_jour date default current_date)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(suivi_mission(m.id) order by m.heure_rdv), '[]'::jsonb)
  from missions m
  where m.entreprise_id = mon_entreprise_id()
    and est_encadrant()
    and m.jour = p_jour
    and m.annulee_le is null
$$;

-- Export mensuel pour le comptable. Arrivée et départ sont vérifiés séparément :
-- une seule colonne « dans la zone » pour la journée masquerait un départ
-- pointé depuis la rue.
create or replace function export_mois(p_debut date, p_fin date)
returns table (
  salarie text, jour date, chantier text, adresse text,
  arrivee time, arrivee_source text, arrivee_dist_m int,
  depart time, depart_dist_m int, pause_min int, duree_h numeric
) language sql stable security definer set search_path = public as $$
  select
    u.nom, m.jour, m.libelle,
    m.adresse || coalesce(' ' || m.code_postal, '') || coalesce(' ' || m.ville, ''),
    (j.arrivee at time zone 'Europe/Paris')::time,
    d.confirme_source::text,
    d.confirme_dist_m,
    (j.depart at time zone 'Europe/Paris')::time,
    (select p.distance_m from pointages p
      where p.mission_id = m.id and p.utilisateur_id = u.id and p.type = 'depart'
      order by p.horodatage desc limit 1),
    round(j.pause_min)::int,
    round(j.duree_min / 60.0, 2)
  from v_journees j
  join missions m     on m.id = j.mission_id
  join utilisateurs u on u.id = j.utilisateur_id
  join mission_destinataires d on d.mission_id = m.id and d.utilisateur_id = u.id
  where m.entreprise_id = mon_entreprise_id()
    and est_encadrant()
    and m.jour between p_debut and p_fin
  order by u.nom, m.jour
$$;

-- ####################  migrations/0006_outils.sql  ####################

-- =============================================================================
-- Outils d'exploitation
-- =============================================================================

/**
 * Une tâche planifiée contenant ce motif existe-t-elle ?
 *
 * Passe par du SQL dynamique à dessein : une référence directe à cron.job
 * échoue dès l'analyse de la requête quand pg_cron n'est pas installé, et ce,
 * même protégée par un test d'existence — PostgreSQL doit résoudre la table
 * avant d'évaluer quoi que ce soit. Cette fonction permet donc à
 * verification.sql de rester une seule requête, exécutable partout.
 */
create or replace function cron_planifie(p_motif text)
returns boolean language plpgsql stable as $$
declare n int;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return false;
  end if;
  execute 'select count(*) from cron.job where command like $1'
    into n using '%' || p_motif || '%';
  return n > 0;
exception when others then
  -- pg_cron installé mais schéma inaccessible : on considère non planifié
  -- plutôt que de faire échouer tout le contrôle.
  return false;
end $$;

-- ####################  migrations/0007_ordre_pointages.sql  ####################

-- =============================================================================
-- Ordre des pointages : un compteur d'insertion plutôt que l'horodatage
--
-- `now()` renvoie l'heure de DÉBUT DE TRANSACTION : deux pointages enregistrés
-- dans la même transaction — ou simplement dans la même milliseconde — portent
-- le même horodatage. `order by horodatage desc limit 1` devient alors
-- indéterminé, et toute la validation de séquence part avec :
--
--   - « pas deux pauses de suite » laisse passer une double pause ;
--   - « pas de reprise sans pause » refuse une reprise légitime ;
--   - l'appariement pause_debut / pause_fin peut croiser les intervalles.
--
-- Un double appui sur le bouton Pause suffit à déclencher le cas. On ordonne
-- donc par ordre d'insertion, qui est exactement ce qu'on veut vérifier.
-- =============================================================================

alter table pointages add column if not exists seq bigserial;

create index if not exists pointages_seq_idx on pointages (mission_id, utilisateur_id, seq);

-- -----------------------------------------------------------------------------
-- pointer() : la séquence se lit par seq, plus par horodatage
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

  -- Ordre d'insertion, pas ordre chronologique : voir l'en-tête du fichier.
  select type into v_dernier from pointages
   where mission_id = p_mission_id and utilisateur_id = auth.uid()
   order by seq desc limit 1;

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
-- v_journees : l'appariement des pauses suit lui aussi l'ordre d'insertion
-- -----------------------------------------------------------------------------

create or replace view v_journees as
with bornes as (
  select
    p.mission_id,
    p.utilisateur_id,
    p.entreprise_id,
    min(p.horodatage) filter (where p.type = 'arrivee') as arrivee,
    max(p.horodatage) filter (where p.type = 'depart')  as depart
  from pointages p
  group by 1, 2, 3
),
pauses as (
  select
    d.mission_id, d.utilisateur_id,
    coalesce(sum(extract(epoch from (f.horodatage - d.horodatage)) / 60), 0)::numeric as pause_min
  from (
    select mission_id, utilisateur_id, horodatage,
           row_number() over (partition by mission_id, utilisateur_id order by seq) as n
    from pointages where type = 'pause_debut'
  ) d
  left join (
    select mission_id, utilisateur_id, horodatage,
           row_number() over (partition by mission_id, utilisateur_id order by seq) as n
    from pointages where type = 'pause_fin'
  ) f on f.mission_id = d.mission_id and f.utilisateur_id = d.utilisateur_id and f.n = d.n
  group by 1, 2
)
select
  b.entreprise_id,
  b.mission_id,
  b.utilisateur_id,
  m.chantier_id,
  m.jour,
  m.duree_service_min,
  b.arrivee,
  b.depart,
  coalesce(pa.pause_min, 0) as pause_min,
  case when b.arrivee is not null then
    greatest(0, extract(epoch from (coalesce(b.depart, now()) - b.arrivee)) / 60
                - coalesce(pa.pause_min, 0))
  end::numeric as duree_min,
  b.depart is null as en_cours
from bornes b
join missions m on m.id = b.mission_id
left join pauses pa on pa.mission_id = b.mission_id and pa.utilisateur_id = b.utilisateur_id;

alter view v_journees set (security_invoker = true);

-- -----------------------------------------------------------------------------
-- ma_mission_du_jour() : « suis-je en pause ? » suit le même ordre
-- -----------------------------------------------------------------------------

create or replace function ma_mission_du_jour()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when m.id is null then null else jsonb_build_object(
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
