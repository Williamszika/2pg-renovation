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
