# Mode d'emploi

À transmettre avec le fichier `2pgpointage.apk`.

L'application est signée par 2PG et distribuée directement, pas par le Play
Store. Android prévient donc qu'elle vient d'une « source inconnue » — c'est
normal pour une application d'entreprise, et c'est ce message qu'il faut
accepter.

Tout est dans le fichier : elle n'ouvre aucun site, elle parle directement à la
base de l'entreprise.

---

## 1. Installer — une fois par téléphone

1. Recevoir `2pgpointage.apk` par WhatsApp, par e-mail ou par câble
2. Appuyer sur le fichier dans les téléchargements
3. Android affiche « votre téléphone n'est pas autorisé à installer des
   applications inconnues provenant de cette source » → **Paramètres** →
   activer **Autoriser depuis cette source** → revenir en arrière
4. Si **Play Protect** s'affiche (« application non reconnue ») → **Installer
   quand même**. Google ne la connaît pas parce qu'elle n'est pas publiée sur
   le Play Store, pas parce qu'elle est dangereuse.

L'icône **2PG Pointage** apparaît sur l'écran d'accueil.

## 2. Se connecter

Adresse e-mail et mot de passe donnés par le bureau. L'application reste
connectée : c'est à faire une seule fois.

Le rôle du compte décide de ce qui s'affiche. Un ouvrier voit son adresse du
jour, un patron voit le tableau de bord. Même fichier, deux applications.

## 3. Autoriser la position

À la première confirmation d'arrivée, Android demande l'accès à la position.
Répondre **Pendant l'utilisation de l'application**.

Sans cette autorisation, l'ouvrier ne peut pas confirmer son arrivée — c'est la
position qui fait la preuve.

Si l'autorisation a été refusée par erreur :
**Paramètres → Applications → 2PG Pointage → Autorisations → Position**.

---

## Ce que fait l'ouvrier

Rien, ou presque.

Il ouvre l'application, il voit l'adresse du jour et l'heure de rendez-vous.
Le bouton **Itinéraire** ouvre Google Maps.

Pendant le trajet, la distance descend en direct : « Encore 130 m ». **Dès
qu'il entre dans le périmètre, sa présence part toute seule** — il n'a aucun
bouton à toucher. Un bouton « Je suis arrivé » reste en secours si le GPS
tarde.

Ensuite : **Pause**, **Reprise**, et **Départ** en fin de journée. Si le départ
est pointé loin du chantier, l'application demande une explication en une
phrase.

L'ouvrier ne voit ni les autres, ni son historique, ni aucun chiffre. Juste sa
journée.

## Ce que fait le patron

**Envoyer une adresse** — il tape la rue, choisit dans la liste proposée, met
un nom de client, une heure de rendez-vous, une durée de service, et coche les
ouvriers concernés. Le seuil de confirmation par défaut est 50 m ; 20 m en
zone dégagée, 100 m en ville dense.

**Suivre la journée** — le tableau se remplit tout seul :

| Ce qui s'affiche | Ce que ça veut dire |
|---|---|
| 🟢 Sur le chantier | arrivé, l'heure exacte est indiquée |
| 🟢 + 🟠 Arrivé en retard | arrivé, avec le retard chiffré |
| 🟠 En retard · 15 min | pas encore arrivé, moins de 30 min après l'heure |
| 🔴 Absent | pas arrivé, plus de 30 min après l'heure |
| ⚪ Journée close | parti |

Il n'y a rien à valider. Le seul bouton qui apparaît, **Débloquer**, sert au
cas où le GPS d'un ouvrier ne descend pas — un sous-sol, un immeuble.

**Ajouter un ouvrier** — panneau Équipe, en bas : nom, e-mail, mot de passe
provisoire. Il transmet ensuite ces deux identifiants à l'intéressé.

**Exporter le mois** — un fichier CSV qui s'ouvre dans Excel, pour la paie.

---

## Avant la première utilisation réelle

Deux choses à faire une fois pour toutes.

**Désactiver la confirmation par e-mail** dans Supabase, sinon un ouvrier créé
ne pourra pas se connecter :
**Authentication → Sign In / Providers → Email → décocher « Confirm email »**.

**Remettre à chaque salarié la note d'information** (`docs/note-information-salaries.md`),
contre signature, **avant** la mise en service. Sans cette remise préalable, le
dispositif est irrégulier et les relevés sont inexploitables en cas de litige.

## Mettre à jour plus tard

Installer le nouveau fichier par-dessus l'ancien : la session et les données
sont conservées. Cela ne fonctionne que si le nouveau fichier est signé avec
**la même clé** — d'où l'importance de conserver `2pg.keystore` et son mot de
passe.
