# Base de données

Cinq migrations, à exécuter **dans l'ordre** depuis le SQL Editor de Supabase.

| Fichier | Contenu |
|---|---|
| `0001_schema.sql` | Tables, types, index, vues de consolidation (`v_journees`, `v_marge_chantier`) |
| `0002_rls.sql` | Sécurité au niveau ligne. Un ouvrier ne voit que ce qui le concerne |
| `0003_rpc.sql` | Fonctions métier : confirmation, pointage, validation bureau, alertes, purge |
| `0004_bootstrap.sql` | Création de la première entreprise et rattachement des ouvriers |
| `0005_lecture.sql` | Vues et fonctions de lecture pour les deux applications |

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
