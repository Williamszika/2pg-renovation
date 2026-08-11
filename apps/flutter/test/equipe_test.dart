import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg2_pointage/main.dart' show languesGerees, delegationsLangue;
import 'package:pg2_pointage/motdepasse.dart';
import 'package:pg2_pointage/patron/equipe.dart';
import 'package:pg2_pointage/theme.dart';

Widget _ecran(List<Map<String, dynamic>> equipe) => MaterialApp(
      locale: languesGerees.first,
      supportedLocales: languesGerees,
      localizationsDelegates: delegationsLangue,
      theme: themeDepuis(Teintes.clair, Brightness.light),
      builder: (_, page) => Palette(t: Teintes.clair, child: page!),
      home: Scaffold(
        body: ListView(children: [
          PanneauEquipe(
            equipe: equipe,
            moiId: 'patron-1',
            apresAction: () async {},
          ),
        ]),
      ),
    );

const _patron = {
  'id': 'patron-1',
  'nom': '2pg Renovation',
  'role': 'patron',
  'actif': true,
};

void main() {
  group('tirerMotDePasse', () {
    test('trois syllabes, un tiret, trois chiffres', () {
      for (var i = 0; i < 200; i++) {
        expect(tirerMotDePasse(), matches(r'^[a-z]{6}-[2-9]{3}$'));
      }
    });

    // Ce mot de passe se dicte de vive voix sur un chantier bruyant. Les
    // trois caractères qui s'échangent à l'œil sont écartés — le zéro, le un
    // et le L — ainsi que le h et le y, muets ou ambigus à l'oral.
    test('aucun caractère qui prête à confusion', () {
      for (var i = 0; i < 200; i++) {
        expect(tirerMotDePasse(), isNot(contains(RegExp(r'[l01hy]'))));
      }
    });

    test('deux tirages ne se ressemblent pas', () {
      final vus = {for (var i = 0; i < 400; i++) tirerMotDePasse()};
      expect(vus.length, greaterThan(390), reason: 'un générateur, pas un compteur');
    });
  });

  group('messageIdentifiants', () {
    final m = messageIdentifiants(
      nom: 'Karim Benali',
      email: 'karim@exemple.fr',
      motDePasse: 'bakumo-473',
      adresseApp: 'https://exemple.fr/',
    );

    test('tutoie par le prénom seul', () {
      expect(m, contains('Bonjour Karim,'));
      expect(m, isNot(contains('Bonjour Karim Benali')));
    });

    test('porte les trois choses nécessaires pour entrer', () {
      expect(m, contains('https://exemple.fr/'));
      expect(m, contains('karim@exemple.fr'));
      expect(m, contains('bakumo-473'));
    });

    test('dit comment installer sur les deux téléphones', () {
      expect(m, contains('iPhone'));
      expect(m, contains('Android'));
    });
  });

  group('le formulaire de création', () {
    testWidgets('reste fermé tant qu\'on ne le demande pas', (tester) async {
      await tester.pumpWidget(_ecran(const [_patron]));
      expect(find.text('Ajouter un ouvrier'), findsOneWidget);
      expect(find.text('Créer le compte'), findsNothing);
    });

    testWidgets('s\'ouvre, se referme', (tester) async {
      await tester.pumpWidget(_ecran(const [_patron]));

      await tester.tap(find.text('Ajouter un ouvrier'));
      await tester.pumpAndSettle();
      expect(find.text('Créer le compte'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);

      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Créer le compte'), findsNothing);
    });

    testWidgets('arrive avec un mot de passe déjà tiré', (tester) async {
      await tester.pumpWidget(_ecran(const [_patron]));
      await tester.tap(find.text('Ajouter un ouvrier'));
      await tester.pumpAndSettle();

      final champ = find.widgetWithText(TextField, 'Mot de passe');
      final avant = tester.widget<TextField>(champ).controller!.text;
      expect(avant, matches(r'^[a-z]{6}-[2-9]{3}$'));

      await tester.tap(find.byIcon(Icons.casino_outlined));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(champ).controller!.text, isNot(avant));
    });

    // Le réseau n'est jamais atteint : la saisie est refusée avant.
    testWidgets('refuse un nom vide sans rien envoyer', (tester) async {
      await tester.pumpWidget(_ecran(const [_patron]));
      await tester.tap(find.text('Ajouter un ouvrier'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Créer le compte'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Il faut un nom'), findsOneWidget);
    });

    testWidgets('refuse une adresse e-mail qui n\'en est pas une',
        (tester) async {
      await tester.pumpWidget(_ecran(const [_patron]));
      await tester.tap(find.text('Ajouter un ouvrier'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Nom de l\'ouvrier'), 'Karim Benali');
      await tester.enterText(
          find.widgetWithText(TextField, 'Adresse e-mail'), 'karim-arobase');
      await tester.tap(find.text('Créer le compte'));
      await tester.pumpAndSettle();

      expect(find.textContaining("n'est pas valide"), findsOneWidget);
    });
  });

  group('la liste', () {
    testWidgets('le patron ne peut pas se bloquer lui-même', (tester) async {
      await tester.pumpWidget(_ecran(const [_patron]));
      expect(find.text('2pg Renovation'), findsOneWidget);
      expect(find.text('Bloquer'), findsNothing);
    });

    testWidgets('un ouvrier bloqué se débloque ou se supprime',
        (tester) async {
      await tester.pumpWidget(_ecran(const [
        _patron,
        {'id': 'o-1', 'nom': 'Karim Benali', 'role': 'ouvrier', 'actif': false},
      ]));

      expect(find.text('Bloqué'), findsOneWidget);
      expect(find.text('Débloquer'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
      expect(find.text('Bloquer'), findsNothing);
    });
  });
}
