# Héberger l'application sur Supabase, et seulement Supabase

Résultat : l'application s'ouvre à l'adresse

```
https://xugujaxoqzsypltvzyny.supabase.co/functions/v1/app/
```

Base de données, comptes, fichiers et application au même endroit. Aucun autre
hébergeur.

## Pourquoi une fonction, et pas simplement un fichier dans Storage

Storage renvoie **tout fichier HTML en `text/plain`**, quel que soit le type
déclaré à l'envoi. C'est une protection délibérée contre l'hébergement de pages
d'hameçonnage, et elle ne se désactive pas. Un `index.html` déposé dans un
bucket s'affiche donc en code source au lieu de s'exécuter.

Vérifiable en une commande :

```
curl -sI "https://xugujaxoqzsypltvzyny.supabase.co/storage/v1/object/public/app/tableaudebord.html" | grep content-type
→ content-type: text/plain
```

La fonction `app` lit les fichiers dans le bucket et les renvoie avec le type
qui convient. Les fichiers restent dans Storage : **pour mettre l'application à
jour, on remplace `index.html` dans le bucket — la fonction ne bouge plus.**

## 1. Déposer les fichiers

**Storage → bucket `app`** (celui qui existe déjà, il doit être **public**).

Déposer les 8 fichiers du dossier `dist/site/`, à la racine du bucket :

```
index.html
sw.js
manifest.webmanifest
icone-192.png
icone-512.png
icone-maskable-512.png
apple-touch-icon.png
2pg-pointage.apk
```

`_headers` ne sert qu'à Netlify — inutile ici, la fonction fait ce travail.

## 2. Déployer la fonction

**Edge Functions → Deploy a new function → Via Editor.**

- Nom : **`app`** — exactement, la fonction s'en sert pour découper l'URL
- Coller le contenu de `supabase/functions/app/index.ts`
- **Décocher « Verify JWT »**

Ce dernier point est indispensable : un navigateur qui ouvre une page n'envoie
pas d'en-tête `Authorization`. Avec la vérification active, la page répond 401
et rien ne s'affiche.

Si la case n'apparaît pas à la création : déployer d'abord, puis
**Edge Functions → app → Settings → Verify JWT → désactiver**.

Puis **Deploy function**, et attendre une trentaine de secondes.

## 3. Vérifier

Ouvrir `https://xugujaxoqzsypltvzyny.supabase.co/functions/v1/app/`

L'écran de connexion doit apparaître, avec la date de fabrication sous le
bouton. Si vous voyez du code source, le type MIME n'est pas appliqué — la
fonction n'est pas celle qui répond. Si vous voyez `{"code":401}`, la
vérification du JWT est restée active.

## Installer sur les téléphones

**Android** — ouvrir l'adresse dans Chrome, menu ⋮ → **Installer l'application**.

**iPhone** — ouvrir dans **Safari** (pas Chrome), Partager → **Sur l'écran
d'accueil**.

Dans les deux cas l'application s'ouvre en plein écran, sans barre d'adresse,
avec son icône sur l'écran d'accueil. C'est le mode d'installation à privilégier
ici — voir ci-dessous.

## Ce que cet hébergement coûte : l'APK perd son plein écran

L'APK s'ouvre en plein écran à une condition : qu'un fichier
`/.well-known/assetlinks.json` soit servi **à la racine du domaine**, portant
l'empreinte de la clé de signature. Sur `xugujaxoqzsypltvzyny.supabase.co`, la
racine appartient à Supabase — les fonctions ne peuvent répondre que sous
`/functions/v1/`. Ce fichier ne peut donc pas y être placé.

Conséquence : un APK pointant vers Supabase **affiche une barre d'adresse
Chrome en haut**. Il fonctionne, mais il ne ressemble plus à une application.

L'installation depuis le navigateur, elle, donne le plein écran sans aucun
fichier de vérification. Sur Supabase seul, **c'est le bon chemin** ; l'APK ne
garde d'intérêt que si vous tenez à envoyer un fichier plutôt qu'un lien.

## Mettre l'application à jour, ensuite

Remplacer `index.html` dans le bucket. C'est tout — la fonction n'a pas à être
redéployée. La page est servie sans cache, la nouvelle version part dès
l'ouverture suivante. La date sous le bouton de connexion permet de vérifier
d'un coup d'œil que le remplacement a pris.
