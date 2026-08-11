import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pg2_pointage/main.dart' show languesGerees, delegationsLangue;
import 'package:pg2_pointage/patron/envoi.dart';
import 'package:pg2_pointage/theme.dart';

/// Le panneau d'envoi, monté dans les mêmes conditions de langue que sur le
/// téléphone. Rien ici ne touche au réseau : la recherche d'adresse n'est
/// déclenchée que par la frappe, et on ne tape pas.
Widget _ecran() => MaterialApp(
      locale: languesGerees.first,
      supportedLocales: languesGerees,
      localizationsDelegates: delegationsLangue,
      theme: themeDepuis(Teintes.clair, Brightness.light),
      builder: (_, page) => Palette(t: Teintes.clair, child: page!),
      home: Scaffold(
        body: ListView(children: [
          PanneauEnvoi(equipe: const [], apresEnvoi: () async {}),
        ]),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  // Ces trois choix sont les seuls endroits de l'application où l'on ouvre
  // quelque chose par-dessus la page. Chacun s'était révélé capable de
  // laisser le patron enfermé : le calendrier en échouant, la liste des
  // durées en couvrant l'écran sans porte de sortie.

  testWidgets('le calendrier s\'ouvre et se referme', (tester) async {
    await tester.pumpWidget(_ecran());

    await tester.tap(find.text("aujourd'hui"));
    await tester.pumpAndSettle();

    // Sans les délégations de langue, la construction échoue ici et il ne
    // reste que le voile gris.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget, reason: 'et en français');

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('le choix de l\'heure s\'ouvre et se referme', (tester) async {
    await tester.pumpWidget(_ecran());

    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  group('temps de service', () {
    testWidgets('la feuille s\'ouvre et Fermer la referme', (tester) async {
      await tester.pumpWidget(_ecran());

      await tester.tap(find.text('8 h 00'));
      await tester.pumpAndSettle();

      expect(find.text('Temps de service'), findsWidgets);
      expect(find.text('Fermer'), findsOneWidget,
          reason: 'la porte de sortie doit être visible');

      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Fermer'), findsNothing);
    });

    testWidgets('choisir une durée la reporte dans le champ', (tester) async {
      await tester.pumpWidget(_ecran());

      await tester.tap(find.text('8 h 00'));
      await tester.pumpAndSettle();

      // La liste s'ouvre sur la valeur en cours, donc 7 h 00 est à l'écran.
      await tester.tap(find.text('7 h 00').last);
      await tester.pumpAndSettle();

      expect(find.text('Fermer'), findsNothing, reason: 'la feuille se ferme');
      expect(find.text('7 h 00'), findsOneWidget);
      expect(find.text('8 h 00'), findsNothing);
    });
  });

  testWidgets('sans ouvrier coché, on ne peut pas envoyer', (tester) async {
    await tester.pumpWidget(_ecran());
    expect(find.text('Choisissez une adresse'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
