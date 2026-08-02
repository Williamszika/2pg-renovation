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
