-- =============================================================================
-- Test du comportement métier, à exécuter dans le SQL Editor de Supabase
--
-- Rejoue une journée complète contre la vraie base, en se faisant passer pour
-- le premier compte patron. Chaque contrôle capture son résultat au lieu de
-- s'arrêter à la première erreur — un test qui s'arrête ne dit rien de ce qui
-- suit.
--
-- Ne teste PAS l'isolation entre entreprises : l'éditeur SQL s'exécute en
-- propriétaire, qui contourne les règles de sécurité par conception. Cette
-- partie se vérifie depuis l'extérieur, avec un vrai compte.
--
-- Tout est nettoyé à la fin : aucune trace ne reste en base.
-- =============================================================================

drop table if exists _resultat_test;
create table _resultat_test (n serial, controle text, etat text, detail text);

do $$
declare
  v_user     uuid;
  v_mission  uuid;
  v_dest     uuid;
  v_r        jsonb;
  v_dist     int;
  v_duree    numeric;
  v_pause    numeric;
  v_n        int;
  v_msg      text;

  -- Chantier de test : 12 rue des Lilas, Blagnac.
  c_lat  constant double precision := 43.6357;
  c_lon  constant double precision := 1.3897;
  -- 0,0002° de latitude ≈ 22 m ; 0,008° ≈ 890 m ; 0,018° ≈ 2 km.
  p_lat  constant double precision := 43.6359;   -- ~22 m
  l_lat  constant double precision := 43.6437;   -- ~890 m
  t_lat  constant double precision := 43.6537;   -- ~2 km

  procedure_ok boolean;
begin
  select id into v_user from utilisateurs where role in ('patron','chef_equipe')
   order by cree_le limit 1;
  if v_user is null then
    insert into _resultat_test (controle, etat, detail)
    values ('Un compte encadrant existe', 'ECHEC', 'aucun patron en base — rattachez d''abord vos comptes');
    return;
  end if;

  -- On se fait passer pour ce compte : auth.uid() lira cette valeur.
  perform set_config('request.jwt.claim.sub', v_user::text, true);

  insert into _resultat_test (controle, etat, detail)
  values ('Compte utilise pour le test', 'OK',
          (select nom from utilisateurs where id = v_user));

  -- 1 -----------------------------------------------------------------------
  begin
    v_mission := creer_mission('TEST METIER', '12 rue des Lilas', '31700', 'Blagnac',
                               c_lat, c_lon, 50, current_date, '08:00', 420, null,
                               array[v_user]);
    insert into _resultat_test (controle, etat, detail)
    values ('Envoi de l''adresse', case when v_mission is null then 'ECHEC' else 'OK' end, '');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into _resultat_test (controle, etat, detail) values ('Envoi de l''adresse', 'ECHEC', v_msg);
    return;
  end;

  -- 2 -----------------------------------------------------------------------
  select (ma_mission_du_jour() -> 'mission' ->> 'id')::uuid into v_dest;
  insert into _resultat_test (controle, etat, detail)
  values ('L''ouvrier voit son adresse',
          case when v_dest = v_mission then 'OK' else 'ECHEC' end,
          coalesce(v_dest::text, 'rien recu'));

  -- 3 -----------------------------------------------------------------------
  v_r := confirmer_arrivee(v_mission, l_lat, c_lon, 8.0);
  insert into _resultat_test (controle, etat, detail)
  values ('Confirmation refusee a ~890 m',
          case when v_r->>'ok' = 'false' and v_r->>'motif' = 'trop_loin' then 'OK' else 'ECHEC' end,
          v_r::text);

  -- 4 -----------------------------------------------------------------------
  v_r := confirmer_arrivee(v_mission, p_lat, c_lon, 80.0);
  insert into _resultat_test (controle, etat, detail)
  values ('Confirmation refusee si le GPS annonce +-80 m',
          case when v_r->>'ok' = 'false' and v_r->>'motif' = 'gps_insuffisant' then 'OK' else 'ECHEC' end,
          v_r::text);

  -- 5 -----------------------------------------------------------------------
  v_r := confirmer_arrivee(v_mission, p_lat, c_lon, 8.0);
  v_dist := (v_r->>'distance_m')::int;
  insert into _resultat_test (controle, etat, detail)
  values ('Confirmation acceptee a ~22 m',
          case when v_r->>'ok' = 'true' and v_dist <= 50 then 'OK' else 'ECHEC' end,
          coalesce(v_dist::text || ' m calcules par PostGIS', v_r::text));

  -- 6 -----------------------------------------------------------------------
  begin
    perform pointer(v_mission, 'pause_debut');
    insert into _resultat_test (controle, etat, detail) values ('Pause acceptee', 'OK', '');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into _resultat_test (controle, etat, detail) values ('Pause acceptee', 'ECHEC', v_msg);
  end;

  -- 7 -----------------------------------------------------------------------
  procedure_ok := false;
  begin
    perform pointer(v_mission, 'pause_debut');
  exception when others then
    procedure_ok := true;
    get stacked diagnostics v_msg = message_text;
  end;
  insert into _resultat_test (controle, etat, detail)
  values ('Deuxieme pause consecutive rejetee',
          case when procedure_ok then 'OK' else 'ECHEC' end,
          coalesce(v_msg, 'aucune erreur levee'));

  -- 8 -----------------------------------------------------------------------
  begin
    perform pointer(v_mission, 'pause_fin');
    insert into _resultat_test (controle, etat, detail) values ('Reprise acceptee', 'OK', '');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into _resultat_test (controle, etat, detail) values ('Reprise acceptee', 'ECHEC', v_msg);
  end;

  -- 9 -----------------------------------------------------------------------
  v_r := pointer(v_mission, 'depart', t_lat, c_lon, 8.0);
  insert into _resultat_test (controle, etat, detail)
  values ('Depart a ~2 km refuse sans motif',
          case when v_r->>'ok' = 'false' and v_r->>'motif' = 'motif_requis' then 'OK' else 'ECHEC' end,
          v_r::text);

  -- 10 ----------------------------------------------------------------------
  v_r := pointer(v_mission, 'depart', t_lat, c_lon, 8.0, 'Camionnette deja chargee');
  insert into _resultat_test (controle, etat, detail)
  values ('Depart a ~2 km accepte avec motif',
          case when v_r->>'ok' = 'true' then 'OK' else 'ECHEC' end, v_r::text);

  -- 11 ----------------------------------------------------------------------
  select duree_min, pause_min into v_duree, v_pause
    from v_journees where mission_id = v_mission and utilisateur_id = v_user;
  insert into _resultat_test (controle, etat, detail)
  values ('Journee consolidee (arrivee, pause, depart)',
          case when v_duree is not null then 'OK' else 'ECHEC' end,
          coalesce(round(v_duree)::text || ' min travaillees, ' ||
                   round(v_pause)::text || ' min de pause', 'aucune journee'));

  -- 12 ----------------------------------------------------------------------
  select jsonb_array_length(suivi_mission(v_mission) -> 'destinataires') into v_n;
  insert into _resultat_test (controle, etat, detail)
  values ('Le suivi remonte au patron',
          case when v_n >= 1 then 'OK' else 'ECHEC' end,
          coalesce(v_n::text || ' destinataire(s)', 'rien'));

  -- 13 ----------------------------------------------------------------------
  select count(*) into v_n from export_mois(current_date, current_date);
  insert into _resultat_test (controle, etat, detail)
  values ('Export du mois', case when v_n >= 1 then 'OK' else 'ECHEC' end,
          v_n::text || ' ligne(s)');

  -- 14 ----------------------------------------------------------------------
  select count(*) into v_n from alertes where mission_id = v_mission;
  insert into _resultat_test (controle, etat, detail)
  values ('Alertes generees',
          case when v_n >= 1 then 'OK' else 'ECHEC' end,
          v_n::text || ' alerte(s) : ' ||
          coalesce((select string_agg(type::text, ', ') from alertes where mission_id = v_mission), ''));

  -- 15 ----------------------------------------------------------------------
  select count(*) into v_n from pointages where mission_id = v_mission;
  insert into _resultat_test (controle, etat, detail)
  values ('Pointages enregistres', case when v_n = 4 then 'OK' else 'ECHEC' end,
          v_n::text || ' pointages (attendu 4 : arrivee, pause, reprise, depart)');

  -- Nettoyage ---------------------------------------------------------------
  delete from alertes   where mission_id = v_mission;
  delete from pointages where mission_id = v_mission;
  delete from mission_destinataires where mission_id = v_mission;
  delete from missions  where id = v_mission;
  insert into _resultat_test (controle, etat, detail)
  values ('Donnees de test supprimees', 'OK', 'aucune trace ne reste en base');
end $$;

select n as "#", etat, controle, detail from _resultat_test order by n;
