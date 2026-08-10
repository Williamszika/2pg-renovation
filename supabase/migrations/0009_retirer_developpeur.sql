-- =============================================================================
-- Retrait de l'indicateur « développeur »
--
-- Il servait à basculer entre le tableau de bord et l'écran ouvrier avec un
-- seul compte. Cette bascule a été retirée de l'application : le rôle du
-- compte décide de l'écran, et personne ne peut voir celui d'un autre.
--
-- La colonne ne sert donc plus à rien. Elle n'accordait aucun droit — les
-- règles de sécurité n'y ont jamais fait référence, seulement l'affichage —
-- si bien que la supprimer ne change rien à ce que chacun peut lire ou écrire.
--
-- Facultatif : laisser la colonne en place ne casse rien non plus.
-- =============================================================================

alter table utilisateurs drop column if exists developpeur;
