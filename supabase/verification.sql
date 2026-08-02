-- =============================================================================
-- Contrôle de l'installation
--
-- À exécuter dans Supabase > SQL Editor, APRÈS setup.sql.
--
-- Les 7 premiers contrôles sont BLOQUANTS : un seul échec et l'application ne
-- fonctionne pas. Les 3 derniers sont des réglages Supabase à faire à la main ;
-- sans eux l'application marche, mais sans alertes automatiques ni mise à jour
-- en direct du tableau de bord.
-- =============================================================================

with controles as (

  -- 1. PostGIS : sans lui, aucune distance ne peut être calculée.
  select 1 as n, true as bloquant, 'PostGIS installe' as controle,
         exists (select 1 from pg_extension where extname = 'postgis') as ok,
         'Database > Extensions > activer postgis' as si_echec

  -- 2. Les huit tables du schéma.
  union all
  select 2, true, 'Les 7 tables sont creees',
         (select count(*) from pg_tables where schemaname = 'public'
           and tablename in ('entreprises','utilisateurs','chantiers','missions',
                             'mission_destinataires','pointages','alertes')) = 7,
         'Rejouez setup.sql en entier'

  -- 3. RLS active partout. Sans elle, n'importe quel compte lit tout.
  union all
  select 3, true, 'Securite au niveau ligne active partout',
         not exists (
           select 1 from pg_tables t
            where t.schemaname = 'public'
              and t.tablename in ('entreprises','utilisateurs','chantiers','missions',
                                  'mission_destinataires','pointages','alertes')
              and not exists (select 1 from pg_class c
                               join pg_namespace ns on ns.oid = c.relnamespace
                              where ns.nspname = 'public' and c.relname = t.tablename
                                and c.relrowsecurity)
         ),
         'Rejouez 0002_rls.sql'

  -- 4. Les pointages doivent être infalsifiables : aucune politique d'ecriture
  --    directe, tout passe par les fonctions serveur.
  union all
  select 4, true, 'Les pointages sont immuables (aucune politique UPDATE/DELETE)',
         not exists (select 1 from pg_policies
                      where schemaname = 'public' and tablename = 'pointages'
                        and cmd in ('UPDATE','DELETE','INSERT')),
         'Une politique d''ecriture a ete ajoutee par erreur sur pointages'

  -- 5. Les fonctions anti-recursion. Sans elles, toute lecture de mission
  --    echoue avec « infinite recursion detected in policy ».
  union all
  select 5, true, 'Fonctions anti-recursion presentes',
         (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
           where ns.nspname = 'public'
             and p.proname in ('suis_destinataire','mission_de_mon_entreprise')) = 2,
         'Rejouez 0002_rls.sql'

  -- 6. Les fonctions appelées par les applications.
  union all
  select 6, true, 'Fonctions metier presentes',
         (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
           where ns.nspname = 'public'
             and p.proname in ('creer_mission','confirmer_arrivee','pointer',
                               'valider_presence','signaler_probleme',
                               'ma_mission_du_jour','suivi_mission','missions_du_jour',
                               'export_mois','purger_localisation','verifier_alertes',
                               'bootstrap_entreprise','rattacher_utilisateur')) = 13,
         'Rejouez 0003_rpc.sql, 0004_bootstrap.sql et 0005_lecture.sql'

  -- 7. security_invoker sur les vues : sans lui, elles s'executent avec les
  --    droits du proprietaire et laissent fuiter les donnees des autres
  --    entreprises.
  union all
  select 7, true, 'Les vues respectent la securite (security_invoker)',
         not exists (
           select 1 from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
            where ns.nspname = 'public' and c.relkind = 'v'
              and c.relname in ('v_missions','v_journees','v_fin_prevue','v_marge_chantier')
              and coalesce(array_to_string(c.reloptions, ','), '') not like '%security_invoker=%'
         ),
         'Rejouez 0005_lecture.sql'

  -- 8. Purge automatique des coordonnees a 2 mois (doctrine CNIL).
  union all
  select 8, false, 'Purge des coordonnees planifiee (2 mois)',
         cron_planifie('purger_localisation'),
         'Facultatif mais recommande : activez pg_cron puis voir README'

  -- 9. Alertes automatiques.
  union all
  select 9, false, 'Verification des alertes planifiee',
         cron_planifie('verifier_alertes'),
         'Facultatif : sans pg_cron, pas d''alerte de retard ni de depassement'

  -- 10. Temps reel : sans cela le tableau de bord ne bouge qu'a la minute.
  union all
  select 10, false, 'Temps reel active sur les 3 tables',
         (select count(*) from pg_publication_tables
           where pubname = 'supabase_realtime' and schemaname = 'public'
             and tablename in ('pointages','mission_destinataires','alertes')) = 3,
         'Database > Replication > activer pointages, mission_destinataires, alertes'
)
select
  n as "#",
  case when ok then 'OK'
       when bloquant then 'ECHEC'
       else 'A REGLER' end as etat,
  controle,
  case when ok then '' else si_echec end as a_faire
from controles
order by n;
