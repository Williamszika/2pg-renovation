# Compiler pour iPhone

Le projet iOS est configuré et prêt. **Ce qui reste demande un Mac** — ce
document dit exactement quoi y faire.

## Ce qui est déjà fait

| | |
|---|---|
| Projet iOS créé | `apps/flutter/ios/` |
| Identifiant | `fr.pg2renovation.pointage` — le même que sur Android |
| Nom affiché | 2PG Pointage |
| iOS minimum | 13.0 |
| Textes de permission de position | rédigés en français, précis |
| Ouverture de Google Maps déclarée | `LSApplicationQueriesSchemes` |
| Déclaration de chiffrement | `ITSAppUsesNonExemptEncryption = false` |
| Code Dart | identique à Android, 19 contrôles passent |

Les deux derniers points évitent des refus au dépôt : Apple rejette une
application dont les demandes de permission sont vagues, et réclame une
déclaration de chiffrement à chaque envoi sans celle-ci.

## Ce qu'il reste, et ce que ça coûte

**Un Mac avec Xcode.** Il n'existe aucun moyen légal de compiler une
application iOS ailleurs. C'est une contrainte d'Apple, pas de Flutter.

**Un compte développeur Apple, 99 € par an.** Sans lui, une application ne
s'installe que sur un téléphone branché au Mac, et **expire au bout de sept
jours**. Inutilisable pour des ouvriers.

Flutter supprime la double écriture du code. Il ne supprime ni le Mac ni les
99 €.

## Sur le Mac, dans l'ordre

    # 1. Flutter, une fois pour toutes
    brew install --cask flutter
    flutter doctor          # suivre ce qu'il demande

    # 2. Xcode depuis l'App Store, puis
    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
    sudo xcodebuild -runFirstLaunch

    # 3. Le projet
    git clone https://github.com/Williamszika/2pg-renovation.git
    cd 2pg-renovation/apps/flutter
    flutter pub get
    cd ios && pod install && cd ..

    # 4. Essai immédiat sur un iPhone branché en USB
    flutter run --release

L'étape 4 fonctionne avec un simple identifiant Apple gratuit, et suffit pour
**vérifier que tout marche**. L'application expirera au bout de sept jours.

### La première ouverture est refusée — c'est normal

L'application s'installe, puis iOS affiche **« Développeur non fiable »** et
refuse de l'ouvrir. Un certificat personnel doit être déclaré de confiance sur
le téléphone lui-même ; le Mac ne peut pas le faire à sa place.

Sur l'iPhone :

**Réglages** → **Général** → **VPN et gestion de l'appareil** → sous
*App développeur*, la ligne **Apple Development: …** → **Faire confiance**

En allemand : *Einstellungen → Allgemein → VPN & Geräteverwaltung →
Apple Development: … → Vertrauen*.

Cette ligne n'apparaît **qu'après** une première tentative d'ouverture. Tant
qu'on n'a pas touché l'icône au moins une fois, la page est vide et on cherche
en vain.

Une fois la confiance accordée, elle vaut pour toutes les applications signées
par ce certificat, y compris les versions suivantes.

### Deux échecs fréquents à l'étape 4

**`"Macintosh HD" is out of space` / `Command CodeSign failed`.** La
compilation iOS écrit plusieurs gigaoctets. À libérer, dans cet ordre :

    rm -rf ~/Library/Developer/Xcode/DerivedData
    rm -rf ~/Library/Developer/Xcode/"iOS DeviceSupport"
    flutter clean

Puis les runtimes de simulateur inutilisés — Xcode → Settings → Components —
environ 8 Go chacun. Vider la corbeille ensuite : tant qu'elle n'est pas vide,
l'espace n'est pas rendu.

**Aucun certificat de signature.** Xcode → Settings → Accounts → ajouter
l'identifiant Apple, puis dans Runner → Signing & Capabilities cocher
*Automatically manage signing* et choisir l'équipe personnelle. Le mot de passe
du trousseau sera demandé une fois.

## Distribuer aux ouvriers

Une fois le compte développeur pris :

    flutter build ipa

Puis Xcode → Product → Archive → Distribute App → **TestFlight**.

TestFlight est le bon canal ici : jusqu'à 100 testeurs internes, installation
par invitation, pas de validation App Store à chaque version. Les ouvriers
installent l'application TestFlight, acceptent l'invitation, et reçoivent les
mises à jour automatiquement.

L'App Store publique n'a aucun intérêt pour une application d'entreprise, et
demanderait une validation à chaque envoi.

## En attendant — ce qui marche aujourd'hui, gratuitement

L'application web s'installe sur iPhone et donne le plein écran, sans compte
Apple ni Mac :

**Safari** (pas Chrome) → https://williamszika.github.io/2pg-renovation/
→ bouton Partager → **Sur l'écran d'accueil**

Icône sur l'écran d'accueil, plein écran, mêmes fonctions. La seule chose qui
manque par rapport au natif est la surveillance de zone en arrière-plan — que
la version Flutter n'a pas encore non plus.

Tant que le compte Apple n'est pas pris, c'est le bon chemin pour les iPhone,
et il ne coûte rien.
