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
