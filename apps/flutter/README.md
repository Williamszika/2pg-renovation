# Application Flutter

`2pgpointage-flutter.apk` — 52 Mo, signée avec la même clé que les versions
précédentes, donc installable **par-dessus** l'application Capacitor.

Une vraie application native, écrite en Dart. Elle ne contient plus de page
web : les écrans sont dessinés par Flutter et parlent directement à l'API
Supabase.

## Ce qu'elle contient

Les deux interfaces, comme les autres versions. C'est le rôle du compte qui
décide, et rien ne permet d'en changer.

**Ouvrier** — son adresse du jour, la carte, la distance qui descend en direct,
la confirmation automatique dès l'entrée dans le périmètre, pause, départ,
signalement quand le GPS ne suit pas.

**Patron** — compteurs du jour, envoi d'adresse avec recherche à la Base
Adresse Nationale et carte du lieu choisi, jour programmable, seuil de
confirmation, suivi de chaque ouvrier avec retard chiffré, historique par
période, équipe avec blocage et suppression.

La carte du patron n'est pas décorative : une adresse correcte peut désigner
le mauvais endroit, et il vaut mieux s'en apercevoir avant d'y envoyer trois
personnes.

## La carte, et pourquoi elle refusait de s'afficher

Google ne sert sa carte intégrée qu'à l'intérieur d'un `<iframe>` : chargée
comme page principale, elle répond *The Google Maps Embed API must be used in
an iframe*. L'application web y échappait sans le savoir, étant elle-même
faite d'iframes. Le WebView, lui, chargeait l'adresse directement.

`pageCarte()` fabrique donc la page d'accueil de l'iframe, et le document
reçoit `https://maps.google.com/` pour base — l'adresse redirige en portant
`x-frame-options: SAMEORIGIN`, que cette base satisfait ; la réponse finale
n'impose plus rien.

La carte ne prend pas les gestes. Dans un formulaire qui défile, une carte qui
capte le glissement du doigt enferme celui qui la touche. Une tape ouvre la
vraie application Maps, où l'on peut vraiment regarder autour.

## La langue, et pourquoi c'est un piège

Le calendrier et le choix de l'heure sont fournis par Flutter, pas écrits ici.
Ils ne parlent français que si `MaterialApp` porte les délégations de
`flutter_localizations`. Sans elles, demander le français à
`showDatePicker` ne renvoie pas d'erreur visible : le dialogue échoue en cours
de construction, et en version publiée Flutter peint un rectangle gris à la
place. Écran voilé, rien dedans, aucun moyen de sortir.

`test/envoi_test.dart` ouvre réellement les trois sélecteurs et vérifie qu'ils
se referment. Retirer les délégations fait échouer le test avec le message
exact : *A MaterialLocalizations delegate that supports the fr_FR locale was
not found*.

## Ce qu'elle n'apporte pas encore

**Pas de surveillance en arrière-plan.** La confirmation part quand
l'application est ouverte. C'était la raison principale de passer au natif, et
c'est la suite logique : Flutter sait le faire, cela demande un paquet de
géorepérage et une déclaration de permission supplémentaire.

**iOS reste à part.** Le code est prêt — Flutter compile pour les deux — mais
produire un `.ipa` demande un Mac avec Xcode, et le distribuer un compte
développeur Apple à 99 €/an. Flutter supprime la double écriture du code, pas
les règles d'Apple.

## Construire

    export PATH=/opt/flutter/bin:$PATH
    export ANDROID_HOME=/opt/android-sdk
    flutter pub get
    flutter test              # 30 contrôles : formats, retards, sélecteurs, carte
    flutter build apk --release

L'APK sort dans `build/app/outputs/flutter-apk/`.

`--split-per-abi` produit des fichiers trois fois plus petits — 18 Mo pour
arm64, 16 Mo pour les anciens téléphones 32 bits — mais oblige à savoir quel
processeur équipe chaque téléphone. La version universelle évite la question.

`android/key.properties` et `android/2pg.keystore` ne sont pas versionnés : la
clé permettrait de publier une mise à jour se faisant passer pour la nôtre.

## Organisation

    lib/
      main.dart            portail : session, rôle, langue, aiguillage
      donnees.dart         client Supabase, modèles, appels RPC
      format.dart          heures, durées, distances, dates — testé
      carte.dart           la carte intégrée, sans clé Google
      theme.dart           la palette de l'application web, à l'identique
      ecran_connexion.dart
      ecran_ouvrier.dart   l'écran de l'ouvrier, et lui seul
      patron/
        tableau.dart       assemblage, compteurs, cadre commun
        envoi.dart         envoyer une adresse
        suivi.dart         l'état de chacun, déduit des faits
        historique.dart    totaux et jour par jour
        equipe.dart        bloquer, débloquer, supprimer

Aucune règle métier ici : les distances sont recalculées par PostGIS, les
horodatages posés par le serveur, et un compte bloqué est refusé par la base.
L'application affiche, elle ne tranche pas.
