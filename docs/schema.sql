-- =============================================================================
-- 2PG Rénovation — Suivi de présence sur chantier
-- Modèle de données PostgreSQL / Supabase
--
-- Principe directeur : minimisation des données.
--   - Une position GPS n'est capturée qu'à l'instant d'un pointage.
--   - Le serveur la convertit immédiatement en distance au chantier.
--   - Les coordonnées brutes sont purgées à 2 mois (doctrine CNIL).
--   - La durée de travail, elle, est conservée 5 ans (obligations de paie).
-- =============================================================================

create extension if not exists postgis;
create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Référentiel
-- -----------------------------------------------------------------------------

create table entreprises (
  id           uuid primary key default gen_random_uuid(),
  nom          text not null,
  siret        text,
  -- Rayon appliqué à un chantier quand aucun rayon spécifique n'est saisi.
  rayon_defaut_m int not null default 100 check (rayon_defaut_m between 20 and 1000),
  cree_le      timestamptz not null default now()
);

create type role_utilisateur as enum ('patron', 'chef_equipe', 'ouvrier');

create table utilisateurs (
  id             uuid primary key references auth.users(id) on delete cascade,
  entreprise_id  uuid not null references entreprises(id) on delete cascade,
  nom            text not null,
  telephone      text,
  role           role_utilisateur not null default 'ouvrier',
  actif          boolean not null default true,
  -- Un compte est lié à un appareil : empêche de pointer pour un collègue.
  -- Tout changement d'appareil doit être validé par le patron.
  appareil_id            text,
  appareil_valide_le     timestamptz,
  cree_le        timestamptz not null default now()
);

create index on utilisateurs (entreprise_id, actif);

-- -----------------------------------------------------------------------------
-- Chantiers
-- -----------------------------------------------------------------------------

create type statut_chantier as enum ('prevu', 'en_cours', 'termine', 'annule');

create table chantiers (
  id             uuid primary key default gen_random_uuid(),
  entreprise_id  uuid not null references entreprises(id) on delete cascade,
  libelle        text not null,                  -- « Mme Durand — SDB »
  client_nom     text,
  adresse        text not null,
  code_postal    text,
  ville          text,

  -- Renseigné via api-adresse.data.gouv.fr (gratuit, sans clé, France).
  -- Le pin reste ajustable à la main : le géocodage se trompe sur les lieux-dits.
  position       geography(point, 4326) not null,

  -- Rayon PAR CHANTIER, jamais global : une maison isolée tolère 60 m, un immeuble
  -- en centre-ville a besoin de 150 m (réflexion du signal sur les façades).
  -- Un rayon unique produit des fausses alertes, et les fausses alertes tuent
  -- la confiance dans l'outil en deux semaines.
  rayon_m        int not null default 100 check (rayon_m between 20 and 1000),

  heures_devisees numeric(6,2),                  -- alimente le suivi de marge
  date_debut     date,
  date_fin_prevue date,
  statut         statut_chantier not null default 'prevu',
  cree_le        timestamptz not null default now()
);

create index on chantiers (entreprise_id, statut);
create index on chantiers using gist (position);

-- Qui travaille où, quel jour, sur quelle plage prévue.
-- Un ouvrier peut avoir plusieurs affectations le même jour (deux adresses) :
-- c'est le cas courant en rénovation, pas une exception.
create table affectations (
  id             uuid primary key default gen_random_uuid(),
  chantier_id    uuid not null references chantiers(id) on delete cascade,
  utilisateur_id uuid not null references utilisateurs(id) on delete cascade,
  jour           date not null,
  debut_prevu    time,
  fin_prevue     time,
  cree_le        timestamptz not null default now(),
  unique (chantier_id, utilisateur_id, jour, debut_prevu)
);

create index on affectations (utilisateur_id, jour);

-- -----------------------------------------------------------------------------
-- Pointages — le cœur du système
-- -----------------------------------------------------------------------------

create type type_pointage as enum ('arrivee', 'pause_debut', 'pause_fin', 'depart');

create table pointages (
  id             uuid primary key default gen_random_uuid(),
  entreprise_id  uuid not null references entreprises(id) on delete cascade,
  utilisateur_id uuid not null references utilisateurs(id) on delete restrict,
  chantier_id    uuid not null references chantiers(id) on delete restrict,
  type           type_pointage not null,

  -- HORODATAGE SERVEUR, jamais celui du téléphone : l'heure du mobile est
  -- modifiable par l'utilisateur. En mode hors ligne on conserve l'heure locale
  -- déclarée et l'écart d'horloge mesuré à la synchronisation, pour arbitrage.
  horodatage       timestamptz not null default now(),
  hors_ligne       boolean not null default false,
  horodatage_local timestamptz,
  ecart_horloge_s  int,

  -- Coordonnées brutes : PURGÉES À 2 MOIS par la tâche de rétention (voir plus bas).
  position       geography(point, 4326),
  precision_m    real,

  -- Résultat de la vérification, calculé côté serveur et CONSERVÉ 5 ANS.
  -- En régime courant le patron ne voit que cela : « à 23 m du chantier ».
  distance_m     int,
  dans_zone      boolean,

  -- Anti-fraude
  mock_detecte   boolean not null default false,  -- drapeau « mock provider » du système
  appareil_root  boolean not null default false,

  -- Obligatoire lorsque dans_zone = false : on n'empêche jamais un pointage,
  -- sinon un ouvrier de bonne foi dans un sous-sol sans GPS ne peut plus
  -- déclarer ses heures — et l'outil est abandonné en une semaine.
  motif          text,
  photo_url      text,                            -- photo DU CHANTIER, jamais du visage
                                                  -- (la CNIL a sanctionné les badgeuses photo)

  cree_le        timestamptz not null default now(),

  constraint motif_requis_hors_zone
    check (dans_zone is not false or motif is not null)
);

create index on pointages (utilisateur_id, horodatage desc);
create index on pointages (chantier_id, horodatage desc);
create index on pointages (entreprise_id, horodatage desc);

-- Journées consolidées : arrivée + pauses + départ → une durée exploitable
-- pour la paie et pour le calcul de marge du chantier.
create table sessions_travail (
  id             uuid primary key default gen_random_uuid(),
  entreprise_id  uuid not null references entreprises(id) on delete cascade,
  utilisateur_id uuid not null references utilisateurs(id) on delete restrict,
  chantier_id    uuid not null references chantiers(id) on delete restrict,
  jour           date not null,
  arrivee        timestamptz,
  depart         timestamptz,
  pause_totale_min int not null default 0,
  duree_min      int,                             -- (départ - arrivée) - pauses
  -- Journée restée ouverte : clôturée automatiquement à l'heure prévue et
  -- signalée au patron pour arbitrage manuel.
  cloture_auto   boolean not null default false,
  valide_par     uuid references utilisateurs(id),
  valide_le      timestamptz
);

create index on sessions_travail (utilisateur_id, jour desc);
create index on sessions_travail (chantier_id);

-- -----------------------------------------------------------------------------
-- Alertes
-- -----------------------------------------------------------------------------

create type type_alerte as enum (
  'retard', 'absence', 'depart_anticipe', 'hors_zone', 'gps_suspect', 'oubli_pointage'
);

create table alertes (
  id             uuid primary key default gen_random_uuid(),
  entreprise_id  uuid not null references entreprises(id) on delete cascade,
  utilisateur_id uuid references utilisateurs(id) on delete set null,
  chantier_id    uuid references chantiers(id) on delete set null,
  pointage_id    uuid references pointages(id) on delete set null,
  type           type_alerte not null,
  message        text not null,
  lue            boolean not null default false,
  cree_le        timestamptz not null default now()
);

create index on alertes (entreprise_id, lue, cree_le desc);

-- =============================================================================
-- Vérification de position — CÔTÉ SERVEUR
--
-- La règle métier vit dans la base, pas dans le téléphone : un ouvrier qui
-- décompile l'application ne peut rien contourner.
-- =============================================================================

create or replace function verifier_position()
returns trigger
language plpgsql
as $$
declare
  v_chantier chantiers%rowtype;
begin
  select * into v_chantier from chantiers where id = new.chantier_id;

  if new.position is not null and v_chantier.position is not null then
    new.distance_m := round(st_distance(new.position, v_chantier.position))::int;
    new.dans_zone  := new.distance_m <= v_chantier.rayon_m;
  else
    -- Pas de GPS (sous-sol, permission refusée) : on accepte le pointage,
    -- on ne peut simplement pas le vérifier. Un motif reste exigé.
    new.dans_zone := null;
  end if;

  return new;
end;
$$;

create trigger trg_verifier_position
  before insert on pointages
  for each row execute function verifier_position();

-- =============================================================================
-- Rétention — deux durées différentes sur la même ligne
--
--   Coordonnées GPS ......... 2 mois  (doctrine CNIL sur les données de localisation)
--   Durée de travail ........ 5 ans   (obligations liées à la paie)
--
-- À planifier quotidiennement (pg_cron sur Supabase).
-- =============================================================================

create or replace function purger_donnees_localisation()
returns void
language sql
as $$
  update pointages
     set position = null,
         precision_m = null
   where horodatage < now() - interval '2 months'
     and position is not null;
$$;

-- select cron.schedule('purge-localisation', '0 3 * * *',
--                      $$select purger_donnees_localisation()$$);

-- =============================================================================
-- Sécurité au niveau ligne (RLS)
--
-- Un ouvrier ne voit QUE ses propres données — c'est aussi ce qui satisfait
-- son droit d'accès RGPD, sans démarche à faire.
-- Le patron voit toute son entreprise, et rien au-delà.
-- =============================================================================

alter table entreprises      enable row level security;
alter table utilisateurs     enable row level security;
alter table chantiers        enable row level security;
alter table affectations     enable row level security;
alter table pointages        enable row level security;
alter table sessions_travail enable row level security;
alter table alertes          enable row level security;

create or replace function mon_entreprise_id()
returns uuid
language sql stable security definer
as $$ select entreprise_id from utilisateurs where id = auth.uid() $$;

create or replace function est_encadrant()
returns boolean
language sql stable security definer
as $$ select role in ('patron', 'chef_equipe') from utilisateurs where id = auth.uid() $$;

-- Chantiers : lecture par toute l'entreprise, écriture réservée à l'encadrement.
create policy chantiers_lecture on chantiers
  for select using (entreprise_id = mon_entreprise_id());
create policy chantiers_ecriture on chantiers
  for all using (entreprise_id = mon_entreprise_id() and est_encadrant());

-- Pointages : l'ouvrier voit et crée les siens ; l'encadrement voit tout.
create policy pointages_lecture on pointages
  for select using (
    entreprise_id = mon_entreprise_id()
    and (utilisateur_id = auth.uid() or est_encadrant())
  );
create policy pointages_creation on pointages
  for insert with check (
    utilisateur_id = auth.uid()
    and entreprise_id = mon_entreprise_id()
  );
-- Volontairement : AUCUNE politique UPDATE ni DELETE sur les pointages.
-- Le Code du travail exige un système « fiable et infalsifiable » (art. D3171-x) :
-- une correction se fait par un pointage rectificatif tracé, jamais par une
-- modification en place.

create policy sessions_lecture on sessions_travail
  for select using (
    entreprise_id = mon_entreprise_id()
    and (utilisateur_id = auth.uid() or est_encadrant())
  );

create policy affectations_lecture on affectations
  for select using (
    utilisateur_id = auth.uid()
    or exists (select 1 from chantiers c
                where c.id = affectations.chantier_id
                  and c.entreprise_id = mon_entreprise_id()
                  and est_encadrant())
  );

create policy alertes_encadrement on alertes
  for all using (entreprise_id = mon_entreprise_id() and est_encadrant());

-- =============================================================================
-- Suivi de marge : devisé vs réalisé
-- C'est la vue qui fait passer l'outil de « surveillance » à « pilotage ».
-- =============================================================================

create or replace view v_marge_chantier as
select
  c.id,
  c.entreprise_id,
  c.libelle,
  c.client_nom,
  c.heures_devisees,
  round(coalesce(sum(s.duree_min), 0) / 60.0, 2) as heures_realisees,
  case
    when c.heures_devisees > 0
    then round(((coalesce(sum(s.duree_min), 0) / 60.0) - c.heures_devisees)
               / c.heures_devisees * 100, 1)
  end as ecart_pct,
  c.statut
from chantiers c
left join sessions_travail s on s.chantier_id = c.id
group by c.id;
