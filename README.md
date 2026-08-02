# 2PG Pointage — suivi de présence sur chantier

Le patron envoie une adresse aux ouvriers de son choix. Chacun la reçoit sur son téléphone,
est prévenu quand il approche, et confirme sa présence une fois sur place. Le temps passé se
compte automatiquement et remonte au bureau.

Application développée pour **2PG Rénovation**, peintre-plaquiste à Saint-Orens-de-Gameville (31).

## Le principe

**Le téléphone déclare, le serveur décide.** L'application envoie une position brute ; c'est
PostgreSQL qui calcule la distance, tranche si elle est dans la zone, et horodate. Un ouvrier
qui décompile l'application ne peut rien contourner — la règle n'y est pas.

**Pas de traçage.** Une position est relevée à la confirmation d'arrivée, une autre au départ.
Entre les deux, rien n'est collecté : ni trajets, ni pauses, ni soirées. La CNIL n'autorise la
géolocalisation pour suivre le temps de travail que lorsqu'aucun autre moyen n'existe — un
pointage déclaratif en est un. À l'inverse, décompter chaque jour la durée de travail est une
**obligation** de l'employeur (art. L3171-1 et suivants du Code du travail) : c'est la base
légale du traitement.

**Deux durées de conservation.** Les coordonnées GPS sont purgées à 2 mois, les heures
travaillées conservées 5 ans pour la paie. Sur la même ligne.

## Structure

| Dossier | Contenu |
|---|---|
| `supabase/migrations/` | Schéma, RLS, fonctions métier. Cinq fichiers à exécuter dans l'ordre |
| `apps/mobile/` | Application ouvrier — Expo / React Native, iOS et Android |
| `apps/web/` | Tableau de bord patron — Next.js |
| `prototype/index.html` | Maquette cliquable d'origine, sans serveur. Utile pour montrer le produit |
| `PROPOSITION.md` | La proposition initiale : analyse, cadre légal, chiffrage |
| `docs/note-information-salaries.md` | Note à remettre aux salariés **avant** la mise en service |

## Installation

### 1. Base de données

Créez un projet sur [supabase.com](https://supabase.com) — **choisissez une région
européenne** (Frankfurt ou Paris), c'est ce qui garde les données dans l'UE.

Dans le SQL Editor, exécutez les cinq migrations **dans l'ordre** :

```
supabase/migrations/0001_schema.sql
supabase/migrations/0002_rls.sql
supabase/migrations/0003_rpc.sql
supabase/migrations/0004_bootstrap.sql
supabase/migrations/0005_lecture.sql
```

Puis, si `pg_cron` est activé sur le projet (Database → Extensions) :

```sql
select cron.schedule('purge-localisation', '0 3 * * *',  $$select purger_localisation()$$);
select cron.schedule('verifier-alertes',   '*/5 * * * *', $$select verifier_alertes()$$);
```

Sans `pg_cron`, les alertes de retard et de dépassement ne se déclenchent pas toutes seules ;
tout le reste fonctionne.

Enfin, activez le temps réel sur les tables `pointages`, `mission_destinataires` et `alertes`
(Database → Replication), sinon le tableau de bord ne se met à jour qu'à chaque minute.

### 2. Tableau de bord

```bash
cd apps/web
cp .env.example .env.local     # puis remplissez les trois valeurs
npm install
npm run dev                    # http://localhost:3000
```

Les clés se trouvent dans Supabase → Project Settings → API. Attention à la troisième :
`SUPABASE_SERVICE_ROLE_KEY` contourne **toutes** les règles de sécurité. Elle ne sert qu'à
créer les comptes des ouvriers, uniquement côté serveur, et ne doit jamais être préfixée
`NEXT_PUBLIC_`.

**Premier lancement :** créez votre compte dans Supabase → Authentication → Users → Add user
(cochez « Auto Confirm User »). Connectez-vous au tableau de bord : il vous proposera de créer
votre entreprise, et ce premier compte en devient le patron. Ensuite, section **Équipe** →
*Ajouter un ouvrier* pour créer les comptes des autres.

### 3. Application mobile

```bash
cd apps/mobile
cp .env.example .env           # les deux mêmes premières valeurs
npm install
npx expo start
```

Pour tester tout de suite, scannez le QR code avec **Expo Go**. Deux réserves : les
notifications push n'y fonctionnent pas sur iOS, et la surveillance de zone en arrière-plan
demande un build de développement (`npx expo run:android`).

Pour distribuer :

```bash
npx eas build --platform android --profile preview      # APK, installable directement
npx eas build --platform android --profile production   # AAB, pour Google Play
npx eas build --platform ios --profile production       # IPA, pour l'App Store
```

Le AAB est **Android uniquement** ; iOS demande un IPA distinct, un compte Apple Developer à
99 $/an, et une recompilation annuelle imposée par Apple. Si toute l'équipe est sur Android,
l'APK en installation directe ou le canal « test interne » de Google Play évite tout cela.

## Le parcours

**Patron** — il tape l'adresse, les propositions arrivent à la frappe depuis la Base Adresse
Nationale. Il choisit l'heure de rendez-vous, le **temps de service** (la durée due sur le
chantier), le seuil de confirmation, coche les ouvriers, envoie.

**Ouvrier** — un seul écran. L'adresse en grand, tapable pour lancer l'itinéraire. À 300 m,
le téléphone le prévient qu'il approche. Sous le seuil, le bouton **Je suis arrivé** s'active.
Puis le chrono, un bouton pause, et **J'ai terminé**.

**Retour au patron** — l'heure exacte, la distance au moment de la confirmation, l'avancement
du temps de service en direct, et des alertes automatiques : retard, absence, GPS insuffisant,
dépassement de service, départ anticipé, journée restée ouverte.

## Les décisions qui comptent

**Le seuil est réglable à chaque envoi, 50 m par défaut.** 20 m reste possible mais est
déconseillé dans l'interface : le GPS d'un téléphone dérive à ± 30–50 m contre une façade ou
en cage d'escalier, et l'ouvrier serait régulièrement sur place sans pouvoir confirmer.

**Confirmer exige deux conditions :** être dans le rayon **et** un GPS assez précis pour
l'affirmer. Un GPS annoncé à ± 60 m ne prouve pas une présence à 50 m. On refuse plutôt que
d'enregistrer une présence fausse — l'ouvrier signale alors au bureau, qui valide à la main.
La source (`gps` ou `validation bureau`) est tracée jusque dans l'export CSV.

**Le départ tolère un rayon plus large** (100 m minimum) : on pointe souvent depuis le
trottoir. Au-delà, ça passe quand même, avec un motif obligatoire et une alerte. On ne bloque
jamais un pointage — sinon un ouvrier de bonne foi dans un sous-sol ne peut plus déclarer ses
heures, et l'outil est abandonné en une semaine.

**Le temps de service est une durée due, pas un horaire fixe.** Arrivé plus tard, l'ouvrier
finit plus tard ; les pauses décalent la fin d'autant.

**Les pointages sont immuables.** Aucune politique UPDATE ni DELETE : une correction se fait
par un pointage rectificatif tracé. Le Code du travail exige un système « fiable et
infalsifiable » (art. D3171-x).

**Un compte, un téléphone.** Le premier appareil s'enregistre ; tout changement demande une
validation du patron. Sans cela, deux ouvriers peuvent pointer l'un pour l'autre.

**Le mode hors ligne est obligatoire.** Les sous-sols et les parkings n'ont pas de réseau. Les
pointages sont mis en file locale et rejoués dans l'ordre à la reconnexion, avec l'écart
d'horloge mesuré — l'heure du téléphone ne fait jamais foi.

## Avant la mise en service

1. **Remettre la note d'information aux salariés, contre signature.** Modèle dans
   `docs/note-information-salaries.md`. Sans cette remise préalable, le dispositif est
   irrégulier et les données qu'il produit sont inexploitables en cas de litige.
2. **Inscrire le traitement au registre**, même à trois salariés.
3. **Analyse d'impact (AIPD)** — recommandée pour un suivi des employés, version allégée
   suffisante à cette taille.
4. **CSE** — information/consultation obligatoire seulement à partir de 11 salariés.
5. **Téléphone personnel** — accord écrit du salarié et indemnisation. Le plus simple reste de
   fournir un téléphone professionnel.

> Ces éléments sont une synthèse documentaire, pas un conseil juridique. Faites relire la note
> par le comptable ou le juriste de l'entreprise avant diffusion.

Un point resté ouvert : l'ouvrier n'a pas d'écran « Mes heures ». Ce n'est pas illégal, mais
son droit d'accès RGPD reste dû — un export PDF mensuel remis avec la paie règle la question.

## Coûts

| Poste | Coût |
|---|---|
| Supabase | 0 € au démarrage, ~23 €/mois en offre Pro (sauvegardes + région UE garantie) |
| Hébergement du tableau de bord (Vercel) | 0 € à cette échelle |
| Compilation Expo EAS | 0 € |
| Compte développeur Apple | 99 $/an — seulement si iOS |
| Compte développeur Google Play | 25 $ une seule fois |
| Géocodage (Base Adresse Nationale) | 0 €, sans clé |
| Notifications push | 0 € |

**10 à 35 €/mois**, quel que soit le nombre d'ouvriers. C'est l'avantage économique du
sur-mesure : le coût ne suit pas les effectifs.

## Vérifications effectuées

Les cinq migrations ont été exécutées sur PostgreSQL 16 + PostGIS, avec les rôles Supabase
reproduits (`authenticated`), et le parcours complet rejoué en SQL :

- confirmation refusée à 811 m, refusée à 25 m avec un GPS à ± 60 m, acceptée à 24 m avec ± 8 m ;
- séquences incohérentes rejetées (reprise sans pause, journée déjà close) ;
- départ hors zone refusé sans motif, accepté avec ;
- durées : 08:05 → 17:10 moins 45 min de pause = 8 h 20, fin prévue 15:50, écart +1 h 20 ;
- isolation entre entreprises : une entreprise tierce voit 0 mission, 0 pointage, 0 chantier,
  0 alerte, et ne peut pas confirmer une présence sur une mission qui n'est pas la sienne ;
- un ouvrier ne peut ni insérer, ni modifier, ni supprimer un pointage ; il ne peut ni créer
  une mission, ni valider sa propre présence.

Les deux applications passent `tsc --noEmit`, et le tableau de bord se construit
(`next build`) sans erreur.
