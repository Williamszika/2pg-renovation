# Proposition — Application de suivi de présence sur chantier

**Client :** 2PG Rénovation (Saint-Orens-de-Gameville, 31)
**Besoin :** savoir à quelle heure les ouvriers arrivent sur l'adresse du chantier, combien de temps ils y restent, et à quelle heure ils repartent.
**Date :** août 2026

---

## 1. Ce que j'ai trouvé sur l'entreprise

### Le compte TikTok — @pitte

| | |
|---|---|
| Nom affiché | PATMOS NEW FAMILLY |
| Handle | [@pitte](https://www.tiktok.com/@pitte) |
| Bio | **« 2PG DONNE DES COULEURS À VOS IDÉES »** |
| Abonnés | 7 814 |
| Abonnements | 7 189 |
| Vidéos publiques | 18 |
| J'aime cumulés | 2 711 |
| Compte | public, non vérifié, messages directs ouverts |
| Lien en bio | **aucun** |

TikTok bloque la lecture automatisée de la liste des vidéos (API signée), je n'ai donc pas pu
lire les légendes une par une. En revanche la bio a suffi à identifier l'entreprise réelle.

### L'entreprise derrière le compte

**2PG Rénovation** — peintre-plaquiste en Haute-Garonne.

- Adresse : 34 rue de Ribaute, 31650 Saint-Orens-de-Gameville
- Téléphone : 06 71 57 72 94 — Mail : 2pg.renovation@gmail.com
- Site : [2pg-renovation-31.fr](https://2pg-renovation-31.fr/)
- Plus de 10 ans d'activité
- Métiers : peinture intérieure/extérieure, rénovation de cuisines et salles de bains,
  parquets (massif, flottant, stratifié), placo et faux plafonds, carrelage mur et sol,
  petite maçonnerie et reprise de fissures, enduits décoratifs, remise en état après dégât des eaux
- Zone d'intervention : Toulouse et périphérie — Aucamville, Saint-Jean, Castanet-Tolosan,
  Beauzelle, Blagnac

### Ce que ça implique pour l'application

C'est un profil d'artisan, pas un groupe de BTP. Cinq conséquences directes sur la conception :

1. **Petite équipe.** L'outil doit s'installer en une soirée et s'utiliser sans formation.
   Une usine à gaz ne sera jamais adoptée.
2. **Chantiers chez des particuliers**, en appartement ou maison. Les adresses sont précises,
   mais le GPS est mauvais en intérieur, en sous-sol et en cage d'escalier. Il faut une
   tolérance de rayon, jamais une exigence de précision au mètre.
3. **Chantiers courts et multiples** — de la demi-journée à quelques semaines. Un ouvrier peut
   faire deux adresses dans la même journée. Le modèle « un pointage par jour » ne suffit pas.
4. **Zone urbaine dense** autour de Toulouse : couverture 4G correcte, mais des trous en
   parking et en sous-sol. **Le mode hors ligne est obligatoire**, pas optionnel.
5. **Entreprise française** → le RGPD et la doctrine CNIL s'appliquent. C'est le point qui
   détermine toute l'architecture, et c'est l'objet de la section suivante.

---

## 2. Le vrai besoin, et le piège à éviter

La demande telle qu'elle est formulée — « savoir s'ils vont bien à l'adresse et combien de
temps ils y restent » — appelle spontanément une réponse : **tracer les téléphones en
continu**. C'est la mauvaise réponse, pour trois raisons.

**C'est illégal en France.** Détaillé au point 3.

**C'est inutilisable en cas de litige.** Une preuve obtenue par un dispositif illicite est
écartée par le conseil de prud'hommes. Un patron qui licencie pour abandon de poste sur la
base d'un traçage non conforme perd son procès et paie des dommages-intérêts.

**Ça détruit l'équipe.** Un ouvrier qui découvre qu'il est pisté en permanence, y compris
pendant sa pause et sur le trajet du retour, démissionne ou se braque. Dans un métier où
recruter un bon plaquiste prend des mois, c'est le risque le plus coûteux des trois.

**La bonne réponse : une badgeuse mobile géo-vérifiée.**
L'ouvrier appuie lui-même sur un bouton en arrivant et en partant. À cet instant précis — et
uniquement à cet instant — l'application prend **une seule** position GPS, la compare à
l'adresse du chantier, et enregistre le résultat. Entre deux pointages, l'application ne
sait rien et n'enregistre rien.

Le patron obtient exactement les trois informations qu'il demande — heure d'arrivée, durée,
heure de départ — avec en prime la preuve que l'ouvrier était bien à l'adresse. Sans traçage.

---

## 3. La contrainte n°1 : la loi française

C'est la partie que la plupart des devs oublient, et c'est celle qui coûte le plus cher
quand on l'oublie. Trois textes comptent.

### 3.1 La géolocalisation pour contrôler les horaires est très encadrée

La CNIL est explicite : un dispositif de géolocalisation ne peut servir à suivre le temps de
travail **que si ce suivi ne peut pas être assuré par un autre moyen**, même moins efficace.
Autrement dit : dès qu'une badgeuse ou un pointage déclaratif est possible — et ici il l'est —
le traçage GPS continu devient disproportionné, donc illicite.

S'y ajoutent : l'interdiction de collecter la position en dehors du temps de travail
(trajet domicile-travail, pauses), l'obligation de permettre au salarié de désactiver la
collecte, et une conservation limitée à **2 mois** pour les données de localisation.

### 3.2 En revanche, décompter le temps de travail est une *obligation* de l'employeur

Les articles L3171-1 à L3171-4 et D3171-1 à D3171-16 du Code du travail imposent à
l'employeur de décompter quotidiennement la durée de travail de chaque salarié, par tout
moyen d'enregistrement, et de récapituler les heures chaque semaine. Si le décompte est
automatisé, le système doit être **fiable et infalsifiable**.

**C'est le renversement d'argument le plus important de cette proposition.** L'application
ne se présente pas comme un outil de surveillance qu'il faudrait justifier : c'est un outil
de **mise en conformité** d'une obligation légale que 2PG a déjà, et que les feuilles
d'heures papier remplissent mal. La base légale du traitement devient l'obligation légale,
la plus solide qui soit. La géolocalisation ponctuelle n'est qu'un attribut de fiabilité du
pointage — pas une finalité en soi.

Ça change aussi le discours aux ouvriers, et c'est vrai : « fini les feuilles d'heures
remplies de mémoire le vendredi soir, tes heures sup sont comptées automatiquement ».

### 3.3 Attention aux photos — la CNIL a déjà sanctionné

La CNIL a mis en demeure plusieurs employeurs pour des **badgeuses photo** : la prise
systématique d'une photo du salarié à chaque pointage, deux à quatre fois par jour, a été
jugée excessive et contraire au principe de minimisation.

**Conséquence directe :** pas de selfie obligatoire à chaque pointage, alors que c'est la
première idée qui vient pour lutter contre la triche. On garde uniquement une photo **du
chantier** (jamais du visage), et seulement dans deux cas : facultative pour documenter
l'avancement, obligatoire pour justifier un pointage hors zone.

### 3.4 La checklist de conformité, concrètement

| À faire | Détail | Charge |
|---|---|---|
| Note d'information aux salariés | Remise contre signature avant la mise en service. Modèle fourni dans `docs/note-information-salaries.md` | 1 h |
| Registre des traitements | Une fiche « gestion du temps de travail ». Obligatoire même à 3 salariés | 1 h |
| Analyse d'impact (AIPD) | Recommandée pour un dispositif de suivi des employés. Version allégée suffisante à cette taille | 3 h |
| Consultation du CSE | Uniquement si l'effectif atteint 11 salariés. À vérifier | — |
| Droit d'accès | Satisfait nativement : chaque ouvrier voit son propre historique dans l'app | inclus |
| Purge automatique | Coordonnées GPS effacées à 2 mois, heures conservées 5 ans (paie) | inclus |

> Ces éléments sont une synthèse documentaire, pas un conseil juridique. Avant la mise en
> service, faites relire la note d'information par le comptable ou le juriste de 2PG —
> comptez une heure, c'est l'heure la mieux investie du projet.

---

## 4. La solution proposée

### 4.1 Le principe en une phrase

**Un pointage déclaratif, horodaté par le serveur, vérifié par une position GPS unique
prise au moment du clic — et rien entre les deux.**

### 4.2 Le déroulé d'une journée

```
07h50  L'ouvrier ouvre l'app. Écran unique : « Chantier du jour — Mme Durand,
       12 rue des Lilas, Blagnac ». Bouton « Itinéraire » qui ouvre Waze.

08h05  Il arrive. Le bouton ARRIVÉE est vert : il est à 23 m du point du chantier.
       Il appuie. → position prise une fois, distance calculée (23 m), position dans
       la zone, heure serveur enregistrée. Le chrono démarre.

12h15  Il appuie sur PAUSE. Le chrono se met en pause. Aucune position n'est prise.

13h00  Il appuie sur REPRISE.

17h10  Il appuie sur DÉPART. Deuxième et dernière position de la journée.
       → 8h05–17h10, moins 45 min de pause = 8 h 20 travaillées.
```

Deux positions GPS dans la journée. C'est tout ce qui est collecté.

**Si l'ouvrier est hors zone** (mauvaise adresse, ou il pointe depuis chez lui), le bouton
passe en orange : il peut quand même pointer, mais un motif écrit devient obligatoire, et
une alerte part chez le patron. On ne bloque jamais le pointage — sinon un ouvrier de bonne
foi dans un sous-sol sans GPS ne peut plus déclarer ses heures, et l'outil est abandonné en
une semaine.

### 4.3 Ce que voit l'ouvrier — 4 écrans, pas un de plus

1. **Aujourd'hui** — son chantier, l'adresse, l'itinéraire, le gros bouton de pointage, le chrono.
2. **Mes heures** — sa semaine et son mois, total et détail par jour. *(C'est aussi le droit d'accès RGPD, satisfait sans démarche.)*
3. **Mes chantiers** — le planning des jours à venir.
4. **Profil** — déconnexion, mentions d'information sur le traitement de ses données.

Pas de fil d'actualité, pas de messagerie, pas de notifications inutiles. Un ouvrier qui a
les mains dans l'enduit doit pouvoir pointer en deux secondes avec le pouce.

### 4.4 Ce que voit le patron

**Écran « Aujourd'hui » — la réponse directe à sa question**

Une ligne par ouvrier : nom, chantier affecté, heure d'arrivée prévue, heure d'arrivée
réelle, écart, temps écoulé en direct, statut.

```
Karim    Blagnac / Mme Durand      prévu 08:00   arrivé 08:05   +5 min    en cours 6h12   ✅
Sofiane  Castanet / M. Bertrand    prévu 08:00   arrivé 09:47   +1h47              4h30   ⚠️
Momo     Aucamville / SCI Pech     prévu 08:00   —              absent                    🔴
```

**Carte** — les chantiers du jour, avec pour chacun qui est présent. Pas la position des
ouvriers : le fait qu'ils aient pointé sur le chantier.

**Fiche chantier** — et c'est là que se trouve la vraie valeur de l'outil :

```
Chantier : Mme Durand — Blagnac
Devisé      : 40 h
Réalisé     : 63 h   (+58 %)
Coût MO     : 1 890 €  vs  1 200 € prévus
Marge       : ⚠️  -690 €
```

Le patron a demandé « est-ce qu'ils y vont et combien de temps ». La question qui rapporte
de l'argent, c'est **« ce chantier, je l'ai devisé 40 h, on en a passé 63 »**. C'est ce qui
lui permet de mieux chiffrer le devis suivant. Un outil qui ne fait que du contrôle sera
détesté et abandonné ; un outil qui améliore les devis sera utilisé tous les jours.

**Alertes push** — non arrivé 30 min après l'heure prévue, départ anticipé de plus d'une
heure, pointage hors zone, GPS falsifié détecté.

**Export** — CSV et PDF mensuel par salarié, pour le comptable et la paie. À lui seul,
cet export justifie souvent l'outil : il supprime la ressaisie de fin de mois.

### 4.5 Résister à la triche

C'est la question que le patron posera en premier. Cinq garde-fous, du plus au moins important :

| Risque | Parade |
|---|---|
| **Fausse position GPS** (appli de mock location, très répandue sur Android) | Détection du drapeau *mock provider* fourni par le système, et du root / jailbreak. Pointage marqué comme suspect et remonté au patron |
| **Pointer depuis chez soi** | La position est comparée au chantier côté **serveur**, pas dans le téléphone. Hors zone = motif obligatoire + alerte |
| **Changer l'heure du téléphone** | L'horodatage fait foi côté serveur. L'heure du téléphone n'est jamais utilisée, même en mode hors ligne : on stocke l'écart d'horloge et on le corrige à la synchro |
| **Pointer pour un collègue** | Un compte par ouvrier, lié à un seul appareil. Tout changement d'appareil demande une validation du patron |
| **Oublier de pointer le départ** | Rappel push à l'heure de fin prévue. Si la journée reste ouverte, clôture automatique à l'heure prévue et signalement au patron pour arbitrage |

Aucun de ces garde-fous n'est infaillible pris isolément. Ensemble, ils rendent la triche
plus fatigante que le travail — ce qui est le seul objectif atteignable.

### 4.6 Ce que je recommande de NE PAS faire

- **Pas de géofencing automatique en arrière-plan.** Techniquement séduisant (le pointage se
  ferait tout seul), mais c'est de la géolocalisation continue déguisée : juridiquement
  fragile, ça vide la batterie, ça complique la validation sur l'App Store, et ça casse dès
  qu'Android met l'app en veille. À écarter au moins pour la V1.
- **Pas de selfie au pointage.** Voir 3.3.
- **Pas de suivi des trajets ni des kilomètres.** Autre finalité, autre régime juridique.
  Si le besoin apparaît un jour, ça se traite séparément.
- **Pas de blocage du pointage hors zone.** Voir 4.2.

---

## 5. Architecture technique

### 5.1 La pile recommandée

| Brique | Choix | Pourquoi |
|---|---|---|
| Application mobile | **React Native + Expo** | Une seule base de code pour iOS et Android. `expo-location` en premier plan suffit — pas besoin de tâches d'arrière-plan, ce qui simplifie tout |
| Base + API + auth | **Supabase** (PostgreSQL) | Postgres avec PostGIS pour le calcul de distance, authentification incluse, sécurité au niveau ligne (RLS) pour garantir qu'un ouvrier ne voit que ses données, hébergement en région UE |
| Tableau de bord patron | **Web (Next.js)** + accès mobile | Le patron consulte souvent sur ordinateur le soir. Une app web évite un deuxième déploiement store |
| Géocodage des adresses | **API Adresse (BAN) — api-adresse.data.gouv.fr** | Service public français, gratuit, sans clé, excellent sur les adresses françaises. Zéro coût, zéro dépendance à Google |
| Fond de carte | MapLibre + tuiles OpenStreetMap | Gratuit, pas de facturation à la vue |
| Notifications | Expo Push | Gratuit, intégré |
| Hors ligne | File d'attente locale (SQLite) + synchro | Les pointages sont mis en file et repartent à la reconnexion |

Le choix structurant est **RLS + calcul de distance côté serveur** : la règle de sécurité et
la règle métier vivent dans la base, pas dans le téléphone. Un ouvrier qui décompile l'app
ne peut rien contourner.

### 5.2 Le modèle de données

Sept tables. Le schéma SQL complet et commenté est dans **`docs/schema.sql`**, prêt à
exécuter sur Supabase.

| Table | Rôle |
|---|---|
| `entreprises` | Multi-société dès le départ — coûte 2 heures maintenant, permet de revendre l'outil plus tard |
| `utilisateurs` | Rôle patron / chef d'équipe / ouvrier, appareil autorisé |
| `chantiers` | Client, adresse, position, **rayon de tolérance**, heures devisées |
| `affectations` | Qui, sur quel chantier, quel jour, sur quelle plage horaire prévue |
| `pointages` | Le cœur : type, horodatage serveur, distance au chantier, dans la zone o/n, mock détecté o/n, motif |
| `sessions_travail` | Arrivée + départ + pauses consolidés en une durée exploitable |
| `alertes` | Retard, absence, départ anticipé, hors zone, GPS suspect |

Deux détails de conception qui comptent :

**La minimisation par défaut.** Le téléphone envoie la position brute, le serveur calcule la
distance, puis les coordonnées sont purgées automatiquement à 2 mois — alors que la durée de
travail, elle, est conservée 5 ans pour la paie. Ce sont deux durées différentes sur la même
ligne, et c'est exactement ce que demande la CNIL. En régime courant, le patron ne voit
jamais de coordonnées : il voit « à 23 m du chantier ».

**Le rayon par chantier, pas global.** Une maison isolée à Castanet tolère 60 m ; un immeuble
en centre-ville de Toulouse a besoin de 150 m à cause de la réflexion du signal sur les
façades. Un rayon unique génère soit des faux positifs, soit des fausses alertes — et les
fausses alertes tuent la confiance dans l'outil en deux semaines.

---

## 6. Déroulé et budget

### 6.1 Les quatre lots

| Lot | Contenu | Charge |
|---|---|---|
| **0 — Cadrage et conformité** | Note d'information aux salariés, registre, AIPD allégée, validation du modèle de données avec le patron | 2 j |
| **1 — MVP utilisable** | Authentification, gestion des chantiers avec géocodage, pointage arrivée/départ géo-vérifié, pauses, écran « aujourd'hui » du patron, export CSV | 12–15 j |
| **2 — Fiabilisation terrain** | Mode hors ligne, détection anti-triche, alertes push, photos de chantier, rappels de pointage | 8–10 j |
| **3 — Valeur métier** | Devisé vs réalisé et marge par chantier, PDF mensuel de paie, multi-équipes, chef d'équipe | 6–8 j |

**Total : 28 à 35 jours-homme.** Le lot 1 seul est déjà livrable et répond à la question
posée — je recommande de le mettre en production sur **un seul chantier réel pendant deux
semaines** avant d'écrire une ligne du lot 2. Ce pilote fera remonter trois ou quatre
surprises terrain qu'aucune spécification ne peut anticiper.

### 6.2 Coûts récurrents

| Poste | Coût |
|---|---|
| Supabase | 0 € au démarrage, ~23 €/mois en offre Pro (sauvegardes + région UE garantie) |
| Compilation Expo EAS | 0 € (offre gratuite suffisante à ce rythme) |
| Compte développeur Apple | 99 $/an — obligatoire pour publier sur iOS |
| Compte développeur Google Play | 25 $ une seule fois |
| Géocodage et cartes | 0 € (API Adresse + OpenStreetMap) |
| Notifications push | 0 € |

**Environ 10 à 35 €/mois**, quel que soit le nombre d'ouvriers. C'est le principal avantage
économique du sur-mesure : le coût ne suit pas les effectifs.

---

## 7. L'alternative honnête : un logiciel existant

Il faut la poser franchement, parce qu'elle est parfois le bon choix.

Des SaaS de pointage géolocalisé existent déjà, certains spécialisés BTP français. Comptez
de l'ordre de 4 à 10 € par salarié et par mois selon l'éditeur — à vérifier au moment du
choix. Pour cinq ouvriers, on est autour de 25 à 50 €/mois, disponible demain matin, sans
aucun développement.

**Prenez un SaaS si** le seul besoin est le pointage, qu'il faut que ça tourne la semaine
prochaine, et que personne dans l'entourage ne peut maintenir une application.

**Développez sur-mesure si** au moins l'un de ces trois points est vrai :

1. **Le devisé vs réalisé compte.** C'est spécifique aux devis de 2PG et à sa façon de
   chiffrer. Aucun SaaS générique ne le fera correctement.
2. **Le coût doit rester fixe.** À 5 ouvriers l'écart est faible ; à 15, le SaaS coûte
   90–150 €/mois quand le sur-mesure reste à 35 €.
3. **L'application peut devenir un produit.** Voir ci-dessous.

---

## 8. Deux remarques sur le TikTok, en dehors du sujet

Elles sortent du cadre de la demande, mais elles sautent aux yeux et elles valent de l'argent.

**Il n'y a aucun lien en bio.** 7 814 abonnés, un site web qui existe, et rien pour faire le
pont entre les deux. Quelqu'un qui voit une vidéo de rénovation de salle de bains et veut un
devis doit chercher le numéro à la main. Ajouter le lien vers `2pg-renovation-31.fr` prend
trente secondes et c'est probablement le meilleur retour sur temps investi de tout ce
document.

**L'audience est un canal de distribution.** 7 814 abonnés sur un compte de rénovation, ce
sont en grande partie des artisans et des petites entreprises du bâtiment — c'est-à-dire
exactement la cible de cette application. Si l'outil fonctionne bien chez 2PG, le
multi-société prévu dans le modèle de données (section 5.2) permet de le proposer à d'autres
artisans, avec une audience déjà constituée pour le faire connaître. Le coût de
développement devient un investissement produit au lieu d'une charge. À garder en tête au
moment d'arbitrer entre SaaS et sur-mesure.

---

## 9. Les six questions à trancher pour démarrer

1. **Combien d'ouvriers ?** Sous 11 salariés, pas de CSE à consulter — ça allège nettement
   le lot 0.
2. **iPhone ou Android ?** Si l'équipe est 100 % Android, on économise le compte Apple à
   99 $/an et une semaine de validation store.
3. **Téléphone pro ou personnel ?** Sur téléphone personnel, il faut un accord écrit du
   salarié et prévoir une indemnisation. C'est faisable, mais ça se prépare.
4. **Les heures servent-elles à la paie ?** Si oui, le format d'export doit être calé avec
   le comptable **avant** de coder — pas après.
5. **Devisé vs réalisé : oui ou non ?** C'est ce qui fait passer l'outil de « surveillance »
   à « pilotage ». Si oui, il faut pouvoir saisir les heures devisées à la création du chantier.
6. **Un ouvrier peut-il faire deux chantiers dans la journée ?** Presque certainement oui
   vu le métier — ça doit être dans le MVP, pas ajouté après coup.

---

## 10. Ma recommandation

**Lancer le lot 0 et le lot 1, et rien d'autre pour l'instant.**

En quatre semaines environ, 2PG dispose d'une application qui répond exactement à la question
posée — heure d'arrivée, temps passé, heure de départ, avec la preuve de présence à l'adresse —
qui est conforme dès le premier jour, et qui remplace les feuilles d'heures papier par un
export propre pour le comptable.

Deux semaines de pilote sur un chantier réel, puis on décide des lots 2 et 3 avec des faits
plutôt qu'avec des hypothèses.

Le point à ne pas rater n'est pas technique : c'est **la conversation avec les ouvriers avant
la mise en service**. Présentée comme du flicage, l'application sera contournée dès la
première semaine. Présentée comme la fin des feuilles d'heures et la garantie que les heures
sup sont payées — ce qui est exactement ce qu'elle fait — elle sera adoptée. La note
d'information fournie dans `docs/note-information-salaries.md` est écrite dans ce sens.

---

### Annexes

- `docs/schema.sql` — modèle de données complet, prêt à exécuter sur Supabase
- `docs/note-information-salaries.md` — note d'information à remettre aux salariés

### Sources

- Profil TikTok [@pitte](https://www.tiktok.com/@pitte) — données publiques du profil, consultées le 2 août 2026
- [2pg-renovation-31.fr](https://2pg-renovation-31.fr/) — site de l'entreprise
- CNIL — [La géolocalisation des véhicules des salariés](https://www.cnil.fr/fr/la-geolocalisation-des-vehicules-des-salaries)
- CNIL — [L'accès aux locaux et le contrôle des horaires sur le lieu de travail](https://www.cnil.fr/fr/lacces-aux-locaux-et-le-controle-des-horaires-sur-le-lieu-de-travail)
- CNIL — [Badgeuses photo : mise en demeure de plusieurs employeurs pour collecte excessive de données](https://www.cnil.fr/fr/badgeuses-photo-mise-en-demeure-de-plusieurs-employeurs-pour-collecte-excessive-de-donnees)
- CNIL — [Le contrôle de l'activité des personnes employées](https://www.cnil.fr/fr/controle-de-lactivite-des-personnes-employees)
- Légifrance — [Code du travail, art. L3171-1 à L3171-4](https://www.legifrance.gouv.fr/codes/section_lc/LEGITEXT000006072050/LEGISCTA000006178019/)
- Légifrance — [Code du travail, art. D3171-1 à D3171-16](https://www.legifrance.gouv.fr/codes/section_lc/LEGITEXT000006072050/LEGISCTA000018487066/)
