import 'package:flutter_test/flutter_test.dart';
import 'package:pg2_pointage/donnees.dart';

void main() {
  // Le chantier d'essai : Saint-Orens-de-Gameville.
  const lat = 43.5486, lon = 1.5308;

  group('pageCarte', () {
    test('sert la carte dans un iframe, jamais en page principale', () {
      final page = pageCarte(lat, lon, 16);
      final embarquee = urlCarte(lat, lon, 16);

      // Chargée telle quelle, Google répond « The Google Maps Embed API must
      // be used in an iframe » et la carte reste blanche.
      expect(page, contains('<iframe'));
      expect(page, contains(embarquee));
      expect(page.indexOf('<iframe'), lessThan(page.indexOf(embarquee)),
          reason: "l'adresse doit être la source de l'iframe");
    });

    test('la carte occupe toute la place qu'
        'on lui donne', () {
      final page = pageCarte(lat, lon, 16);
      expect(page, contains('height:100%'));
      expect(page, contains('margin:0'));
    });

    test('le zoom demandé arrive bien à Google', () {
      expect(pageCarte(lat, lon, 12), contains('z=12'));
      expect(pageCarte(lat, lon, 18), contains('z=18'));
    });
  });

  group('adresses Google', () {
    test('la carte intégrée ne demande aucune clé', () {
      final u = urlCarte(lat, lon, 16);
      expect(u, contains('output=embed'));
      expect(u, isNot(contains('key=')));
      expect(u, contains('hl=fr'));
    });

    test("l'itinéraire et le lieu sont deux adresses distinctes", () {
      expect(urlItineraire(lat, lon), contains('travelmode=driving'));
      expect(urlLieu(lat, lon), contains('search'));
      expect(urlLieu(lat, lon), isNot(contains('travelmode')));
    });

    test('la position part telle quelle, sans arrondi', () {
      expect(urlCarte(lat, lon, 16), contains('$lat,$lon'));
      expect(urlLieu(lat, lon), contains('$lat,$lon'));
    });
  });
}
