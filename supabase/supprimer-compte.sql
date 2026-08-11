-- =============================================================================
-- Supprimer définitivement un compte, et tout ce qui s'y rattache
-- =============================================================================
--
-- Le tableau de bord Supabase refuse la suppression avec un message vide :
--
--     Failed to delete selected users: {}
--
-- Ce n'est pas un défaut de Supabase, c'est la base qui refuse et le tableau
-- de bord qui n'affiche pas pourquoi. Trois contraintes s'y opposent :
--
--     missions.envoyee_par     → utilisateurs(id)  on delete restrict
--     pointages.utilisateur_id → utilisateurs(id)  on delete restrict
--     pointages.mission_id     → missions(id)      on delete restrict
--
-- Supprimer le compte d'authentification efface en cascade sa fiche dans
-- `utilisateurs` ; le `restrict` s'y oppose dès que ce compte a envoyé une
-- adresse ou pointé une seule fois, et rejette toute l'opération.
--
-- Ces deux `restrict` ne sont pas un accident. Ils sont ce qui empêche
-- d'effacer des heures travaillées — l'article L3171-4 du code du travail
-- impose de pouvoir les produire pendant cinq ans, et un employeur qui ne le
-- peut pas perd le litige. Les lever demande une décision, pas un clic.
--
-- CE SCRIPT EST DONC RÉSERVÉ AUX COMPTES D'ESSAI. Sur le compte d'un salarié
-- qui a réellement travaillé, il détruit une preuve. Dans ce cas, la bonne
-- opération est le blocage — `definir_actif(id, false)` — qui interdit tout
-- accès sans rien effacer.
--
-- Il efface aussi les pointages faits par D'AUTRES sur les adresses envoyées
-- par ce compte : ils bloquent la suppression des missions. Le tableau final
-- en donne le compte exact.
--
-- Coller dans SQL Editor, remplacer l'adresse, puis Run.
-- =============================================================================

create temporary table if not exists bilan (quoi text, combien int);
truncate bilan;

do $$
declare
  v_courriel constant text := lower('bracknetswilliam@gmail.com');
  v_id uuid;
  n int;
begin
  select id into v_id from auth.users where email = v_courriel;

  if v_id is null then
    insert into bilan values ('aucun compte à cette adresse', 0);
    return;
  end if;

  -- D'abord les pointages : ils tiennent à la fois au compte et aux missions
  -- qu'il a envoyées. Tant qu'ils sont là, rien d'autre ne peut partir.
  delete from pointages
   where utilisateur_id = v_id
      or mission_id in (select id from missions where envoyee_par = v_id);
  get diagnostics n = row_count;
  insert into bilan values ('pointages effacés', n);

  delete from alertes where utilisateur_id = v_id;
  get diagnostics n = row_count;
  insert into bilan values ('alertes effacées', n);

  delete from mission_destinataires where utilisateur_id = v_id;
  get diagnostics n = row_count;
  insert into bilan values ('adresses reçues effacées', n);

  delete from missions where envoyee_par = v_id;
  get diagnostics n = row_count;
  insert into bilan values ('adresses envoyées effacées', n);

  delete from utilisateurs where id = v_id;
  get diagnostics n = row_count;
  insert into bilan values ('fiche dans l''entreprise effacée', n);

  -- Le compte de connexion lui-même. Supabase efface en cascade ses sessions,
  -- ses identités et ses jetons.
  delete from auth.users where id = v_id;
  get diagnostics n = row_count;
  insert into bilan values ('compte de connexion effacé', n);
end $$;

select * from bilan
union all
select 'RESTE-T-IL QUELQUE CHOSE ?',
       (select count(*)::int from auth.users
         where email = lower('bracknetswilliam@gmail.com'));
