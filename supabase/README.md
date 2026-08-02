# Base de données

**Pour installer, suivez [`INSTALLATION.md`](INSTALLATION.md)** — collez `setup.sql` d'un
bloc, puis `verification.sql`.

Ce qui suit décrit le contenu. Les migrations sont la source de vérité ; `setup.sql` en est la
concaténation, régénérée par `./build-setup.sh`. Ne modifiez jamais `setup.sql` à la main.

| Fichier | Contenu |
|---|---|
| `0001_schema.sql` | Tables, types, index, vues de consolidation (`v_journees`, `v_marge_chantier`) |
| `0002_rls.sql` | Sécurité au niveau ligne. Un ouvrier ne voit que ce qui le concerne |
| `0003_rpc.sql` | Fonctions métier : confirmation, pointage, validation bureau, alertes, purge |
| `0004_bootstrap.sql` | Création de la première entreprise et rattachement des ouvriers |
| `0005_lecture.sql` | Vues et fonctions de lecture pour les deux applications |
| `0006_outils.sql` | `cron_planifie()`, utilisée par `verification.sql` |
| `0007_ordre_pointages.sql` | Ordonne les pointages par ordre d'insertion, pas par horodatage |

## Pourquoi des fonctions plutôt que des écritures directes

Toute écriture de pointage passe par une fonction `security definer`. Le client n'envoie
qu'une position brute : c'est le serveur qui calcule la distance avec PostGIS, tranche si elle
est dans la zone, et horodate. L'application n'a aucun moyen de mentir sur l'une de ces trois
choses, et la table `pointages` n'a **aucune** politique INSERT, UPDATE ou DELETE.

## Un piège à connaître

Les politiques de `missions` et de `mission_destinataires` doivent s'interroger mutuellement :
lire une mission demande de savoir si l'on en est destinataire, et lire un destinataire demande
de connaître l'entreprise de la mission. Écrites naïvement, elles produisent une
« infinite recursion detected in policy ». D'où `suis_destinataire()` et
`mission_de_mon_entreprise()`, en `security definer` : la vérification se fait hors RLS et la
boucle disparaît.

Ce défaut est **invisible** si vous testez en superutilisateur, qui contourne RLS. Testez avec
le rôle `authenticated`, comme le font les vraies requêtes.

## Tâches planifiées

```sql
select cron.schedule('purge-localisation', '0 3 * * *',  $$select purger_localisation()$$);
select cron.schedule('verifier-alertes',   '*/5 * * * *', $$select verifier_alertes()$$);
```

La purge efface les coordonnées GPS de plus de 2 mois (doctrine CNIL) sans toucher aux durées
de travail, conservées 5 ans pour la paie.

## Pourquoi les pointages s'ordonnent par `seq` et pas par horodatage

`now()` renvoie l'heure de **début de transaction**. Deux pointages enregistrés dans la même
transaction — ou simplement dans la même milliseconde — portent le même horodatage, et
`order by horodatage desc limit 1` devient indéterminé. Toute la validation de séquence part
avec : « pas deux pauses de suite » laisse passer une double pause, « pas de reprise sans
pause » refuse une reprise légitime, et l'appariement pause/reprise peut croiser les
intervalles. Un double appui sur le bouton Pause suffit à déclencher le cas.

D'où la colonne `seq` (`bigserial`) sur `pointages` : on ordonne par ordre d'insertion, qui
est exactement ce que la vérification de séquence cherche à contrôler.

## Fichiers de test

| Fichier | Ce qu'il vérifie |
|---|---|
| `verification.sql` | L'installation : extensions, tables, RLS, fonctions, tâches planifiées |
| `test-metier.sql` | Le comportement, contre la vraie base : distances, refus, séquences, durées, alertes, export. Nettoie tout derrière lui |
| `test-projet.mjs` | La même chose depuis l'extérieur, avec un vrai compte — seul moyen de tester aussi l'isolation entre entreprises |

`test-metier.sql` s'exécute dans l'éditeur SQL, donc en propriétaire : il ne teste **pas**
l'isolation, puisque le propriétaire contourne RLS par conception.
