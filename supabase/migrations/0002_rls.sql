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
