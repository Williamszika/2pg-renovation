# Application Android autonome

`2pgpointage.apk` — 3,7 Mo. **Ne dépend d'aucun hébergeur web.**

## Pourquoi elle existe

Supabase refuse de servir une page web : toute réponse affichable ressort en
`text/plain`, avec une politique de sécurité qui interdit son exécution.
Mesures dans `supabase/HEBERGEMENT.md`. Héberger l'application chez Supabase
est donc impossible — et la seule façon de n'utiliser que Supabase est de ne
plus héberger de page du tout.

Ici, les fichiers de l'application voyagent **à l'intérieur de l'APK**
(`assets/public/`). L'application les charge depuis la mémoire du téléphone et
ne parle plus qu'à l'API Supabase, en direct. Aucun Netlify, aucun bucket, rien
à déployer.

## Ce que contient l'APK

Les mêmes fichiers que l'application web, tableau de bord patron et écran
ouvrier compris — c'est toujours le rôle du compte qui décide de l'écran.

    assets/public/index.html            l'application entiere, 287 Ko
    assets/public/manifest.webmanifest
    assets/public/icone*.png

Le service worker n'est pas embarqué : les fichiers sont déjà locaux, un cache
par-dessus ne ferait que risquer de figer une version.

## Permissions

    INTERNET                 parler a Supabase
    ACCESS_FINE_LOCATION     confirmer l'arrivee et pointer le depart
    ACCESS_COARSE_LOCATION   repli si le GPS precis est refuse

Pas d'accès en arrière-plan : l'application ne demande rien quand elle est
fermée. Le pont Capacitor traduit la demande de position de la page en demande
système (`BridgeWebChromeClient.onGeolocationPermissionsShowPrompt`), donc
l'ouvrier voit la fenêtre Android habituelle.

## Vérifié

| Point | Résultat |
|---|---|
| Signature | même clé que les versions précédentes |
| Fichiers embarqués | `index.html` intact, 294 150 octets, version `2026-08-07.1351` |
| Supabase depuis le WebView | `access-control-allow-origin: *` pour `https://localhost` |
| API Adresse depuis le WebView | `access-control-allow-origin: *` |

Non vérifié : l'exécution sur un vrai téléphone. Cette machine n'a pas
d'émulateur Android.

## Ce que ce choix coûte

**Android uniquement.** Sans page web hébergée, il n'y a plus rien à ouvrir
depuis un iPhone, un iPad ou un ordinateur — ni pour l'ouvrier, ni pour le
patron. Compiler l'équivalent iOS demande un Mac avec Xcode, et le distribuer
demande un compte développeur Apple à 99 €/an.

## Reconstruire

    cd apps/natif
    npm install
    cp ../statique/dist/site/{index.html,manifest.webmanifest,icone*.png,appletouchicon.png} www/
    npx cap sync android
    cd android
    export ANDROID_HOME=/opt/android-sdk KEYSTORE_MDP=<mot de passe>
    ./gradlew assembleRelease

L'APK sort dans `android/app/build/outputs/apk/release/`. La clé `2pg.keystore`
n'est pas versionnée.

## Mettre l'application à jour

Il faut reconstruire et redistribuer l'APK — c'est le revers de l'autonomie.
Avec une page hébergée, un remplacement de fichier suffisait et tous les
téléphones suivaient. Ici, chaque mise à jour est un fichier à renvoyer aux
ouvriers, qui l'installent par-dessus l'ancien.
