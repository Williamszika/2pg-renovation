#!/usr/bin/env bash
# Regenere setup.sql a partir des migrations. Les migrations restent la source
# de verite : ne modifiez jamais setup.sql a la main.
set -euo pipefail
cd "$(dirname "$0")"
{
  cat <<'ENTETE'
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

ENTETE
  for f in migrations/*.sql; do
    echo ""
    echo "-- ####################  $f  ####################"
    echo ""
    cat "$f"
  done
} > setup.sql
echo "setup.sql regenere ($(wc -l < setup.sql) lignes)"
