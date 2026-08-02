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
