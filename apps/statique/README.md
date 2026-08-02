# Tableau de bord — page autonome

Un seul fichier HTML, sans serveur ni build. À déposer chez n'importe quel hébergeur de
fichiers statiques.

> ## ⚠️ Pas dans le Storage de Supabase
>
> Supabase **force le type `text/plain` sur tous les fichiers HTML** qu'il sert, pour empêcher
> qu'on héberge des pages trompeuses sur son domaine. Le fichier se télécharge et se lit
> correctement, mais le navigateur affiche le code source au lieu d'exécuter la page. Ce n'est
> pas un réglage : c'est codé en dur dans leur service, et ça ne se contourne pas sans un plan
> Pro avec domaine personnalisé.
>
> Vérifié sur le projet réel : `HTTP 200`, 257 249 octets, `content-type: text/plain`.
>
> Voir [supabase/storage#186](https://github.com/supabase/storage/issues/186) et
> [discussion #39110](https://github.com/orgs/supabase/discussions/39110).

## Construire

```bash
cd apps/web && npm install     # une seule fois, pour récupérer la bibliothèque
cd ../statique && ./build.sh
```

Produit `dist/tableau-de-bord.html` (~250 Ko). La bibliothèque Supabase y est **intégrée**
plutôt que chargée depuis un CDN : la page ne dépend de rien d'autre que de votre projet.

`src/tableau-de-bord.html` est la source. Ne modifiez jamais `dist/` à la main.

## Mettre en ligne

Renommez le fichier `index.html`, placez-le seul dans un dossier, puis :

| Hébergeur | Comment | Compte requis |
|---|---|---|
| **Netlify Drop** | Glisser le dossier sur [app.netlify.com/drop](https://app.netlify.com/drop) | non pour essayer |
| **Cloudflare Pages** | Create a project → Direct Upload | oui, gratuit |
| **Vercel** | Import depuis GitHub, Root Directory `apps/statique/dist` | oui, gratuit |
| **GitHub Pages** | Uniquement si le dépôt est public, ou avec un compte Pro | oui |

Tous sont gratuits à cette échelle et servent bien le HTML en `text/html`.

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
