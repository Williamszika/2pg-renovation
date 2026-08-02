-- =============================================================================
-- Indicateur « développeur »
--
-- Permet à un encadrant de basculer entre le tableau de bord et l'écran ouvrier
-- avec un seul compte, et d'afficher un panneau de diagnostic. Sans lui, tester
-- le parcours de l'ouvrier demande un deuxième compte et un deuxième téléphone.
--
-- Un booléen plutôt qu'une valeur d'énumération supplémentaire : « ALTER TYPE …
-- ADD VALUE » ne peut pas être suivi d'un usage de cette valeur dans la même
-- transaction, et l'éditeur SQL de Supabase exécute tout un collage d'un bloc.
-- Le réglage échouerait donc à mi-parcours. Ce n'est de toute façon pas un rôle
-- métier : ça ne change aucun droit, seulement ce que l'application affiche.
-- =============================================================================

alter table utilisateurs
  add column if not exists developpeur boolean not null default false;

comment on column utilisateurs.developpeur is
  'Affiche la bascule vue patron / vue ouvrier et le panneau de diagnostic. '
  'N''accorde aucun droit supplémentaire sur les données : les règles de '
  'sécurité restent celles du rôle.';

-- -----------------------------------------------------------------------------
-- Pour se désigner soi-même — à exécuter avec son propre e-mail
-- -----------------------------------------------------------------------------
-- update utilisateurs u
--    set developpeur = true
--   from auth.users a
--  where a.id = u.id and a.email = 'vous@exemple.fr'
-- returning u.nom, u.role, u.developpeur;
