# Installation sur Supabase — pas à pas

Compter 20 minutes. Aucune commande à taper pour les trois premières étapes :
tout se fait dans l'interface.

---

## 1. Créer le projet

1. [supabase.com](https://supabase.com) → **Start your project** → connexion avec GitHub ou e-mail.
2. **New project**.
3. Remplir :
   - **Name** : `2pg-pointage`
   - **Database Password** : générez-en un et **notez-le** — il ne se réaffiche jamais.
   - **Region** : **Frankfurt (eu-central-1)** ou **Paris (eu-west-3)**.
     Ce choix décide où vivent les données. Une région américaine sortirait les
     données personnelles des salariés de l'Union européenne, ce qui complique
     nettement la conformité.
   - **Plan** : Free suffit pour démarrer.
4. **Create new project**, puis attendre 2 minutes que la base soit provisionnée.

---

## 2. Installer le schéma

1. Menu de gauche → **SQL Editor** → **New query**.
2. Ouvrir `supabase/setup.sql` dans ce dépôt, **tout copier**, coller dans l'éditeur.
3. **Run** (ou Ctrl+Entrée).

Attendu : `Success. No rows returned`. C'est normal — le script crée des objets,
il ne renvoie pas de données.

> `setup.sql` est prévu pour un projet **vierge**. Relancé sur une base déjà
> installée, il s'arrêtera sur `relation already exists`. Sans gravité : ça veut
> dire que c'était déjà fait.

---

## 3. Les trois réglages qui ne sont pas dans le SQL

**a) Extensions** — Menu **Database** → **Extensions**, chercher et activer :

| Extension | Pourquoi |
|---|---|
| `postgis` | Calcul des distances. **Sans elle, rien ne fonctionne.** Elle est normalement activée par `setup.sql` ; vérifiez-le |
| `pg_cron` | Purge automatique des coordonnées et alertes de retard. Facultatif mais recommandé |

**b) Tâches planifiées** — si `pg_cron` est activé, retourner dans **SQL Editor** et exécuter :

```sql
select cron.schedule('purge-localisation', '0 3 * * *',  $$select purger_localisation()$$);
select cron.schedule('verifier-alertes',   '*/5 * * * *', $$select verifier_alertes()$$);
```

La première efface chaque nuit les coordonnées GPS de plus de 2 mois, sans
toucher aux heures travaillées. La seconde produit les alertes de retard,
d'absence et de dépassement du temps de service.

**c) Temps réel** — Menu **Database** → **Replication** → cliquer sur
`supabase_realtime` → activer les trois tables :

- `pointages`
- `mission_destinataires`
- `alertes`

Sans cela le tableau de bord fonctionne, mais ne se met à jour qu'une fois par
minute au lieu d'être instantané.

---

## 4. Vérifier

**SQL Editor** → **New query** → coller tout `supabase/verification.sql` → **Run**.

Vous devez obtenir 10 lignes. Les **7 premières doivent afficher `OK`** — elles
sont bloquantes. Les 3 dernières correspondent aux réglages de l'étape 3 ; si
elles affichent `A REGLER`, la colonne `a_faire` dit quoi faire.

---

## 5. Récupérer les clés

Menu **Project Settings** (roue dentée) → **API Keys**. Trois valeurs à noter :

| Valeur | Où elle va | Sensibilité |
|---|---|---|
| **Project URL** | `apps/web/.env.local` et `apps/mobile/.env` | publique |
| **publishable** (`sb_publishable_…`) ou **anon** (`eyJ…`) | idem | publique par nature — elle ne donne accès qu'à ce que les règles de sécurité autorisent |
| **secret** (`sb_secret_…`) ou **service_role** (`eyJ…`) | `apps/web/.env.local` **uniquement** | **secrète** — elle contourne toutes les règles de sécurité |

Supabase délivre désormais le format `sb_publishable_…` / `sb_secret_…`. Les
projets plus anciens ont des clés en `eyJ…`. Les deux fonctionnent : prenez
celles que votre projet affiche.

> La clé `service_role` ne sert qu'à créer les comptes des ouvriers, côté
> serveur. Elle ne doit jamais être préfixée `NEXT_PUBLIC_`, jamais être mise
> dans l'application mobile, jamais être commitée. Si elle fuite, quelqu'un peut
> lire et modifier toute la base. Elle se révoque dans **Project Settings → API
> → Generate new JWT secret**.

---

## 6. Créer votre compte

Menu **Authentication** → **Users** → **Add user** → **Create new user** :

- **Email** : votre adresse
- **Password** : votre mot de passe
- **Auto Confirm User** : **coché** — sinon il faut valider un e-mail avant de
  pouvoir se connecter.

---

## 7. Lancer le tableau de bord

```bash
cd apps/web
cp .env.example .env.local
# remplir les trois valeurs de l'étape 5
npm install
npm run dev
```

Ouvrir <http://localhost:3000>, se connecter. Au premier lancement, un écran
propose de **créer l'entreprise** : ce compte en devient le patron.

Puis section **Équipe** → *Ajouter un ouvrier* pour créer les autres comptes.
Chacun reçoit une adresse e-mail et un mot de passe provisoire, à lui remettre.

---

## 8. Lancer l'application mobile

```bash
cd apps/mobile
cp .env.example .env
# les deux mêmes premières valeurs (URL + anon), PAS la service_role
npm install
npx expo start
```

Scanner le QR code avec **Expo Go**. Deux réserves : les notifications push n'y
fonctionnent pas sur iOS, et le signal d'approche en arrière-plan demande un
build de développement (`npx expo run:android`).

---

## 9. Tester l'installation de bout en bout

Une fois le patron créé, depuis la racine du dépôt :

```bash
SUPABASE_URL="https://xxxx.supabase.co" \
SUPABASE_ANON_KEY="eyJhbGciOi..." \
PATRON_EMAIL="vous@exemple.fr" \
PATRON_MDP="votre-mot-de-passe" \
node supabase/test-projet.mjs
```

Le script s'envoie une adresse à lui-même et vérifie les six comportements qui
comptent : refus à 900 m, refus avec un GPS imprécis, acceptation à 22 m,
démarrage du chrono, remontée côté patron, et rejet d'une séquence incohérente.

Il laisse une mission nommée `TEST INSTALLATION`. Pour la supprimer, dans le
SQL Editor :

```sql
delete from pointages where mission_id in (select id from missions where libelle like 'TEST INSTALLATION%');
delete from missions  where libelle like 'TEST INSTALLATION%';
```

---

## Si ça coince

| Symptôme | Cause |
|---|---|
| `type "geography" does not exist` | PostGIS non activé — étape 3a |
| `infinite recursion detected in policy` | `0002_rls.sql` incomplet — rejouez `setup.sql` sur un projet vierge |
| `permission denied for table ...` | Normal : les règles de sécurité font leur travail. Vérifiez avec quel compte vous êtes connecté |
| Le tableau de bord affiche « Compte non rattaché » | Le compte auth existe mais pas la ligne entreprise — laissez l'écran de création d'entreprise aller au bout |
| `ce compte est deja rattache a une entreprise` | Vous avez déjà fait le bootstrap ; reconnectez-vous simplement |
| Aucune alerte de retard | `pg_cron` non activé ou tâches non planifiées — étape 3b |
| Le tableau de bord ne bouge pas en direct | Temps réel non activé — étape 3c |
