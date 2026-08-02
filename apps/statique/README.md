# Tableau de bord — page autonome

Un seul fichier HTML, à déposer dans le Storage de Supabase. Aucun serveur, aucun
hébergeur tiers, rien à installer.

## Construire

```bash
cd apps/web && npm install     # une seule fois, pour récupérer la bibliothèque
cd ../statique && ./build.sh
```

Produit `dist/tableau-de-bord.html` (~250 Ko). La bibliothèque Supabase y est **intégrée**
plutôt que chargée depuis un CDN : la page ne dépend de rien d'autre que de votre projet.

`src/tableau-de-bord.html` est la source. Ne modifiez jamais `dist/` à la main.

## Déposer sur Supabase

1. **Storage** → **New bucket** → nom `app`, cocher **Public bucket** → Save
2. Ouvrir le bucket → **Upload file** → `dist/tableau-de-bord.html`
3. L'adresse est alors :
   `https://<projet>.supabase.co/storage/v1/object/public/app/tableau-de-bord.html`

Pour mettre à jour : reconstruire, puis réuploader le fichier en écrasant l'ancien.

## Ce que cette version fait, et ne fait pas

Identique au tableau de bord Next.js pour l'essentiel : recherche d'adresse en direct via la
Base Adresse Nationale, envoi multi-destinataires, temps de service, seuil de confirmation,
suivi en temps réel, validation manuelle, alertes, marge par chantier, export CSV.

**La création d'un compte ouvrier fonctionne différemment.** La version Next.js utilise la clé
secrète côté serveur ; ici il n'y a pas de serveur, et cette clé n'a rien à faire dans une page
publique. La page passe donc par l'inscription classique, ce qui suppose que les inscriptions
soient ouvertes sur le projet. Si elles sont fermées — le réglage le plus sûr — la page affiche
la requête SQL exacte à coller dans l'éditeur Supabase, avec un bouton Copier.

## Sécurité

L'URL et la clé publique sont écrites en clair dans la page : c'est leur raison d'être, elles
ne donnent accès qu'à ce que les règles de sécurité de la base autorisent. Un visiteur non
authentifié lit zéro ligne sur toutes les tables — vérifié depuis l'extérieur.

La clé secrète n'est pas dans ce fichier et ne doit jamais y être.
