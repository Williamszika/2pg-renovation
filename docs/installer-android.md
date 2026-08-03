# Installer l'application sur un téléphone Android

À transmettre avec le fichier `2pg-pointage.apk`.

L'application est signée par 2PG, pas distribuée par le Play Store. Android
prévient donc qu'elle vient d'une « source inconnue » — c'est normal pour une
application d'entreprise, et c'est ce message qu'il faut accepter.

## 1. Recevoir le fichier

Par WhatsApp, par e-mail ou par câble. Le fichier s'appelle
`2pg-pointage.apk`.

## 2. L'ouvrir

Appuyer sur le fichier dans les téléchargements. Android affiche :

> Pour votre sécurité, votre téléphone n'est pas autorisé à installer des
> applications inconnues provenant de cette source.

Appuyer sur **Paramètres**, activer **Autoriser depuis cette source**, puis
revenir en arrière. L'installation reprend.

Si un écran **Play Protect** apparaît (« application non reconnue »), appuyer
sur **Installer quand même**. Google ne connaît pas cette application parce
qu'elle n'est pas publiée sur le Play Store, pas parce qu'elle est dangereuse.

## 3. Se connecter

Avec l'adresse e-mail et le mot de passe donnés par le bureau.

## 4. Autoriser la position — les deux niveaux

Deux demandes séparées, et la deuxième compte autant que la première.

| Demande | Réponse | À quoi ça sert |
|---|---|---|
| Position pendant l'utilisation | **Autoriser** | confirmer l'arrivée et le départ |
| Position en permanence | **Autoriser tout le temps** | être prévenu à l'approche du chantier, téléphone rangé |

Android ne propose pas « tout le temps » directement : il envoie dans les
réglages de l'application. Chemin exact :

**Paramètres → Applications → 2PG Pointage → Autorisations → Position →
Toujours autoriser**

Sans ce réglage, l'application fonctionne quand même, mais l'ouvrier ne reçoit
plus la notification d'approche : il doit penser à ouvrir l'application en
arrivant sur le chantier.

## Ce que l'application relève, et quand

La position est envoyée **au moment de l'arrivée et au moment du départ**,
rien entre les deux. La surveillance d'approche ne transmet pas de trajet :
le système d'exploitation réveille l'application au franchissement de la
limite et lui dit seulement « il vient d'entrer dans la zone ».

Les coordonnées GPS sont effacées au bout de deux mois. Les heures, elles,
sont conservées cinq ans — c'est l'obligation légale de décompte du temps de
travail.

## Mettre à jour plus tard

Installer le nouveau fichier par-dessus l'ancien : les données et la session
sont conservées. Cela ne fonctionne que si le nouveau fichier est signé avec
**la même clé** — d'où l'importance de conserver `2pg-release.keystore` et son
mot de passe. Perdus, il faudrait désinstaller l'application sur chaque
téléphone avant de pouvoir réinstaller.
