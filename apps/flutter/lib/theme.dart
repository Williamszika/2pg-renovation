import 'package:flutter/material.dart';

/// La palette de l'application web, reprise à l'identique : les deux versions
/// coexisteront un temps sur les mêmes chantiers, elles doivent se ressembler.
class Teintes {
  const Teintes({
    required this.fond,
    required this.surface,
    required this.surface2,
    required this.encre,
    required this.encreDouce,
    required this.encrePale,
    required this.trait,
    required this.traitPale,
    required this.pigment,
    required this.pigmentPale,
    required this.ok,
    required this.okPale,
    required this.alerte,
    required this.alertePale,
    required this.arret,
    required this.arretPale,
  });

  final Color fond, surface, surface2;
  final Color encre, encreDouce, encrePale;
  final Color trait, traitPale;
  final Color pigment, pigmentPale;
  final Color ok, okPale;
  final Color alerte, alertePale;
  final Color arret, arretPale;

  static const clair = Teintes(
    fond: Color(0xFFF6F5F2),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEFEDE8),
    encre: Color(0xFF1B1F26),
    encreDouce: Color(0xFF5A626E),
    encrePale: Color(0xFF8A909B),
    trait: Color(0xFFE2DFD8),
    traitPale: Color(0xFFEDEBE5),
    pigment: Color(0xFF2E3FA3),
    pigmentPale: Color(0xFFE8EAF7),
    ok: Color(0xFF2E7A57),
    okPale: Color(0xFFE3F0EA),
    alerte: Color(0xFFA8721A),
    alertePale: Color(0xFFF6EEDF),
    arret: Color(0xFFA93A34),
    arretPale: Color(0xFFF7E7E5),
  );

  static const sombre = Teintes(
    fond: Color(0xFF111317),
    surface: Color(0xFF191C21),
    surface2: Color(0xFF21252B),
    encre: Color(0xFFE9E7E2),
    encreDouce: Color(0xFF99A0AB),
    encrePale: Color(0xFF6E7681),
    trait: Color(0xFF2A2E35),
    traitPale: Color(0xFF222630),
    pigment: Color(0xFF8496F5),
    pigmentPale: Color(0xFF1D2340),
    ok: Color(0xFF4FB183),
    okPale: Color(0xFF14291F),
    alerte: Color(0xFFD3A24A),
    alertePale: Color(0xFF2C2416),
    arret: Color(0xFFE2726B),
    arretPale: Color(0xFF2E1917),
  );
}

/// Rend la palette accessible sans la passer de widget en widget.
class Palette extends InheritedWidget {
  const Palette({super.key, required this.t, required super.child});

  final Teintes t;

  static Teintes de(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<Palette>()!.t;

  @override
  bool updateShouldNotify(Palette vieux) => vieux.t != t;
}

ThemeData themeDepuis(Teintes t, Brightness luminosite) {
  final base = ThemeData(brightness: luminosite, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: t.fond,
    colorScheme: base.colorScheme.copyWith(
      primary: t.pigment,
      surface: t.surface,
      error: t.arret,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: t.encre,
      displayColor: t.encre,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.trait),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.trait),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.pigment, width: 1.6),
      ),
      labelStyle: TextStyle(color: t.encrePale),
    ),
  );
}

/// Pastille d'état, la même qu'au tableau de bord web.
class Pastille extends StatelessWidget {
  const Pastille(this.texte, {super.key, this.ton = Ton.neutre});

  final String texte;
  final Ton ton;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    final (fond, encre) = switch (ton) {
      Ton.ok => (t.okPale, t.ok),
      Ton.alerte => (t.alertePale, t.alerte),
      Ton.arret => (t.arretPale, t.arret),
      Ton.pigment => (t.pigmentPale, t.pigment),
      Ton.neutre => (t.surface2, t.encreDouce),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
            color: encre, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

enum Ton { neutre, ok, alerte, arret, pigment }
