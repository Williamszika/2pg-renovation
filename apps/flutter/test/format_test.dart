import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pg2_pointage/format.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('minutesDuJour', () {
    // Une heure seule et un horodatage sont tous deux des chaînes : on
    // reconnaît la première à sa forme, pas à son type. C'est précisément
    // l'erreur qui avait empêché le retard de s'afficher côté web.
    test('lit une heure seule', () {
      expect(minutesDuJour('08:00'), 480);
      expect(minutesDuJour('8:05'), 485);
      expect(minutesDuJour('09:44:00'), 584);
    });

    test('lit un horodatage', () {
      final d = DateTime(2026, 8, 10, 10, 21);
      expect(minutesDuJour(d), 621);
      expect(minutesDuJour(d.toIso8601String()), 621);
    });
  });

  group('retard', () {
    int retard(String arrivee, String rdv) =>
        minutesDuJour(arrivee) - minutesDuJour(rdv);

    test('arrivée en avance ou à l\'heure', () {
      expect(retard('07:58', '08:00'), -2);
      expect(retard('08:00', '08:00'), 0);
    });

    test('arrivée en retard', () {
      expect(retard('08:37', '08:00'), 37);
      expect(duree(retard('08:37', '08:00')), '37 min');
      expect(duree(retard('10:21', '08:00')), '2 h 21');
    });
  });

  group('duree', () {
    test('sous une heure', () => expect(duree(45), '45 min'));
    test('avec les minutes sur deux chiffres', () {
      expect(duree(420), '7 h 00');
      expect(duree(485), '8 h 05');
    });
    test('rien à afficher', () => expect(duree(null), '—'));
    test('jamais de durée négative', () => expect(duree(-10), '0 min'));
  });

  group('metres', () {
    test('sous le kilomètre', () => expect(metres(22), '22 m'));
    test('au-delà, en kilomètres et virgule française',
        () => expect(metres(2400), '2,4 km'));
    test('rien à afficher', () => expect(metres(null), '—'));
  });

  group('dateCourte', () {
    test('les trois jours nommés', () {
      final n = DateTime.now();
      expect(dateCourte(jourISO(n)), "aujourd'hui");
      expect(dateCourte(jourISO(n.add(const Duration(days: 1)))), 'demain');
      expect(dateCourte(jourISO(n.subtract(const Duration(days: 1)))), 'hier');
    });

    test('au-delà, le jour est écrit', () {
      final loin = DateTime.now().add(const Duration(days: 4));
      final s = dateCourte(jourISO(loin));
      expect(s, isNot("aujourd'hui"));
      expect(s, contains('${loin.day}'));
    });
  });

  group('ecart', () {
    test('en deçà de la minute, on ne chipote pas',
        () => expect(ecart(0.4), "à l'heure"));
    test('dépassement', () => expect(ecart(35), '+ 35 min'));
    test('avance', () => expect(ecart(-90), '− 1 h 30'));
  });

  group('heure', () {
    test('depuis une heure seule', () => expect(heure('08:02:00'), '08:02'));
    test('depuis un DateTime', () {
      expect(heure(DateTime(2026, 8, 10, 17, 5)), '17:05');
    });
    test('rien à afficher', () => expect(heure(null), '—'));
  });
}
