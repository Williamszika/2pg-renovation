# 2PG Rénovation — Suivi de présence sur chantier

Proposition d'application mobile pour **2PG Rénovation** (Saint-Orens-de-Gameville, 31) :
savoir à quelle heure les ouvriers arrivent sur l'adresse du chantier, combien de temps ils
y restent, et à quelle heure ils repartent.

## En bref

L'approche retenue n'est **pas** le traçage GPS continu — illégal en France pour contrôler
les horaires, inutilisable en cas de litige prud'homal, et destructeur pour l'équipe.

C'est une **badgeuse mobile géo-vérifiée** : l'ouvrier pointe lui-même son arrivée et son
départ, et à cet instant précis — uniquement à cet instant — l'application relève une
position unique, comparée à l'adresse du chantier côté serveur. Entre deux pointages, rien
n'est collecté.

Le patron obtient les trois informations qu'il demande, avec la preuve de présence sur
place. Et l'entreprise se met au passage en conformité avec son obligation de décompte du
temps de travail (art. L3171-1 et suivants du Code du travail).

## Documents

| Fichier | Contenu |
|---|---|
| [`PROPOSITION.md`](PROPOSITION.md) | La proposition complète : analyse, cadre légal, fonctionnalités, architecture, chiffrage, planning |
| [`docs/schema.sql`](docs/schema.sql) | Modèle de données PostgreSQL/Supabase, prêt à exécuter |
| [`docs/note-information-salaries.md`](docs/note-information-salaries.md) | Note d'information à remettre aux salariés avant mise en service |

## Statut

**Proposition — pas encore développée.** Six décisions restent à trancher avec le client
avant de démarrer (voir la section 9 de la proposition).
