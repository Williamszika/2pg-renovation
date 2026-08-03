# APK Android

`2pg-pointage.apk` — l'application installable sur téléphone Android.

## Ce que c'est

Une enveloppe Android autour de l'application web déjà déployée. Elle ouvre
`https://hilarious-biscotti-6d0ccf.netlify.app/` en plein écran, sans barre
d'adresse ni onglets — l'utilisateur ne voit pas qu'il y a un navigateur en
dessous.

Conséquence utile : **le contenu se met à jour tout seul**. Un nouveau dépôt
sur Netlify est visible immédiatement, sans réinstaller l'APK sur chaque
téléphone. L'APK ne change que si l'icône, le nom ou l'adresse changent.

Elle contient les deux interfaces, patron et ouvrier — c'est la même
application web, et c'est le rôle du compte qui décide de l'écran.

## Ce qu'elle ne fait pas

Pas de surveillance de position en arrière-plan. La confirmation d'arrivée se
fait quand l'application est ouverte. Un ouvrier qui arrive sans ouvrir
l'application n'est pas compté tant qu'il ne l'ouvre pas.

C'est la seule chose que l'application native (`apps/mobile`) apporterait de
plus : Android la réveillerait au franchissement du périmètre. Sa compilation
est bloquée, voir plus bas.

## Reconstruire

    export ANDROID_HOME=/opt/android-sdk
    ./gradlew assembleRelease
    zipalign -p -f 4 app/build/outputs/apk/release/app-release-unsigned.apk /tmp/a.apk
    apksigner sign --ks 2pg.keystore --ks-key-alias 2pg --out 2pg-pointage.apk /tmp/a.apk

La clé `2pg.keystore` n'est pas dans le dépôt — voir « Signature » ci-dessous.

## Signature

    SHA-256  C6:F1:EF:E9:23:7F:49:81:D6:11:A7:F9:AE:E3:01:71:2B:C9:01:45:04:F7:DB:2F:9B:10:6E:B0:AA:EA:0C:47

Cette empreinte est reprise dans `apps/statique/src/.well-known/assetlinks.json`,
déployé avec le site. C'est ce qui autorise l'application à s'ouvrir en plein
écran plutôt qu'en onglet Chrome. **Si la clé change, l'empreinte doit changer
des deux côtés en même temps**, sinon la barre d'adresse réapparaît.

La clé elle-même et son mot de passe ne sont pas versionnés. Sans eux, aucune
mise à jour ne peut s'installer par-dessus : il faudrait désinstaller
l'application sur chaque téléphone.

## Pourquoi pas l'application native

`apps/mobile` est une application Expo complète, avec surveillance de zone en
arrière-plan. Sa compilation locale échoue à l'étape prefab :

    [CXX1210] expo-modules-core/android/CMakeLists.txt release|arm64-v8a
      : No compatible library found

Vérifié et écarté : NDK 26 installé et utilisé, CMake 3.22.1, `minSdk` 24,
`ndk.stl` forcé à `c++_shared`, `newArchEnabled` testé dans les deux états,
`react-native` réaligné de 0.76.7 sur 0.76.9. Les métadonnées prefab de
`react-android` (`api 24, ndk 26, c++_shared`) correspondent exactement aux
paramètres passés à CMake, et l'outil prefab en ligne de commande accepte ces
mêmes paramètres. AGP 8.6 les rejette quand même.

Le chemin normal pour cette application est **EAS Build**, le service de
compilation d'Expo, que le projet est déjà configuré pour utiliser
(`eas.json`, profil `preview` → APK). Il demande un compte Expo :

    npx eas login
    npx eas build --platform android --profile preview
