# Application installable — ouvrier et patron

Une seule application web, installable sur iOS et Android depuis le navigateur. Le rôle du
compte décide de ce qui s'affiche : l'ouvrier voit son adresse du jour, l'encadrement voit le
suivi. Une icône, une installation.

## Construire

```bash
cd ../web && npm install     # une seule fois, pour la bibliothèque Supabase
cd ../statique && ./build.sh
```

Produit `dist/site/` :

| Fichier | Rôle |
|---|---|
| `index.html` | L'application entière, bibliothèque Supabase intégrée (~270 Ko) |
| `manifest.webmanifest` | Nom, icônes, affichage plein écran — ce qui la rend installable |
| `sw.js` | Service worker : démarrage instantané et fonctionnement hors ligne |
| `icone-*.png` | Icônes, générées sans dépendance par `src/icones.py` |

`src/` est la source. Ne modifiez jamais `dist/` à la main.

## Mettre en ligne

Le dossier `dist/site/` se dépose tel quel :

| Hébergeur | Comment | Compte |
|---|---|---|
| **Netlify Drop** | Glisser le dossier sur [app.netlify.com/drop](https://app.netlify.com/drop) | facultatif pour essayer |
| **Cloudflare Pages** | Create a project → Direct Upload | gratuit |
| **Vercel** | Import GitHub, Root Directory `apps/statique/dist/site` | gratuit |

> ## ⚠️ Pas dans le Storage de Supabase
>
> Supabase **force le type `text/plain` sur tous les fichiers HTML** qu'il sert, pour empêcher
> l'hébergement de pages trompeuses sur son domaine. Le navigateur affiche alors le code source
> au lieu d'exécuter la page. Ce n'est pas un réglage : c'est codé en dur, et ça ne se
> contourne pas sans plan Pro avec domaine personnalisé.
>
> Mesuré sur le projet réel : `HTTP 200`, 257 249 octets, `content-type: text/plain`.
> Voir [supabase/storage#186](https://github.com/supabase/storage/issues/186).
>
> L'hébergement doit aussi être en **HTTPS** : sans lui, ni service worker, ni installation,
> ni géolocalisation. Tous les hébergeurs ci-dessus le fournissent d'office.

## Installer sur un téléphone

**Android** — ouvrir l'adresse dans Chrome, puis la bannière « Installer l'application », ou
menu ⋮ → *Ajouter à l'écran d'accueil*.

**iPhone** — ouvrir l'adresse **dans Safari** (Chrome iOS ne sait pas installer), bouton
Partager, puis *Sur l'écran d'accueil*.

## Mode développeur

Un compte marqué `developpeur = true` voit une barre supplémentaire dans l'en-tête :

| Vue | Ce qu'elle donne |
|---|---|
| **Vue patron** | Le tableau de bord habituel |
| **Vue ouvrier** | L'écran de l'ouvrier, avec son propre compte — plus besoin d'un deuxième téléphone pour tester le parcours |
| **Diagnostic** | Compte, projet, latence des appels, état du service worker, application installée ou non, volumes du jour. Bouton Copier pour transmettre le tout |

L'indicateur **n'accorde aucun droit supplémentaire** : les règles de sécurité restent celles
du rôle, et le serveur refuse exactement ce qu'il refusait. C'est de l'affichage.

Pour se désigner :

```sql
update utilisateurs u
   set developpeur = true
  from auth.users a
 where a.id = u.id and a.email = 'vous@exemple.fr'
returning u.nom, u.role, u.developpeur;
```

Le panneau de diagnostic s'ouvre justement quand quelque chose ne marche pas : il affiche donc
tout ce qui est connu localement **immédiatement**, et complète les deux lignes réseau quand
elles répondent — ou déclare forfait après 8 secondes. Il ne reste jamais bloqué à attendre.

## Cartes et itinéraires

Trois usages distincts, trois choix différents :

| Usage | Service | Pourquoi |
|---|---|---|
| Chercher l'adresse à la frappe | **Base Adresse Nationale** | Gratuit, sans clé, base officielle française — meilleur que Google sur les adresses françaises |
| Aperçu avant envoi | **OpenStreetMap** (iframe) | Gratuit, sans clé. Une carte Google exigerait une clé et un compte de facturation |
| Ouvrir / itinéraire | **Google Maps** | C'est ce que tout le monde connaît, et l'URL universelle ouvre l'application installée sur iPhone comme sur Android |

L'aperçu n'est pas décoratif : un géocodage peut poser le point au mauvais endroit, et
l'ouvrier ne pourrait alors jamais confirmer sa présence. Le patron le voit avant d'envoyer.

Les destinations sont passées en **coordonnées**, jamais en texte : elles viennent de la BAN et
désignent exactement le point validé sur l'aperçu, là où une adresse en toutes lettres pourrait
être réinterprétée par le service de navigation.

## Ce que cette version ne fait pas

**Pas de signal d'approche en arrière-plan.** iOS n'autorise pas la surveillance de zone pour
une application web. Le message « Vous approchez du chantier » s'affiche donc uniquement quand
l'ouvrier a l'application ouverte. L'application native Expo (`apps/mobile/`) le fait, elle.

**Pas de détection de GPS falsifié.** Le navigateur ne fournit pas l'information que le système
donne à une application native. Le reste de l'anti-fraude tient : distance calculée côté
serveur, horodatage serveur, pointages immuables, un compte par appareil.

Si ces deux points deviennent gênants, le code natif est écrit et prêt dans `apps/mobile/`.

## Sécurité

L'URL et la clé publique sont écrites en clair dans la page : c'est leur raison d'être, elles
ne donnent accès qu'à ce que les règles de la base autorisent. Un visiteur non authentifié lit
zéro ligne sur toutes les tables — vérifié depuis l'extérieur. La clé secrète n'est pas dans
ce fichier et ne doit jamais y être.

Le service worker ne met en cache **que la coquille** — page, manifeste, icônes. Jamais les
réponses de Supabase : servir un pointage périmé depuis un cache ferait croire à un ouvrier
que sa journée est enregistrée alors qu'elle ne l'est pas.
