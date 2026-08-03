# Documents

| Fichier | À quoi ça sert |
|---|---|
| `note-information-salaries.md` | À remettre à chaque salarié **contre signature, avant** la mise en service. Sans cette remise préalable, le dispositif est irrégulier et les données produites sont inexploitables en cas de litige. |
| `captures/` | Les deux interfaces, rendues depuis l'application construite. Utile pour montrer à quoi ressemble chaque rôle sans avoir à créer un compte. |

## Les deux interfaces

Une seule adresse, un seul écran de connexion. Le rôle du compte décide de
l'écran, dans `demarrer()` :

| Rôle | Écran | Capture |
|---|---|---|
| `ouvrier` | l'adresse du jour, et rien d'autre | `captures/ecran-ouvrier.png` |
| `patron`, `chef_equipe` | suivi, envoi d'adresse, équipe | `captures/ecran-patron.png` |

La séparation ne tient pas à l'affichage : les règles de sécurité de la base
ne servent à un ouvrier que sa propre mission du jour. Une application
modifiée ne lui donnerait rien de plus.

Le modèle de données, initialement esquissé ici, vit désormais dans `supabase/migrations/`.
