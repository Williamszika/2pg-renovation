import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'donnees.dart';
import 'ecran_connexion.dart';
import 'ecran_ouvrier.dart';
import 'patron/tableau.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  await Supabase.initialize(url: urlSupabase, publishableKey: clePublique);
  runApp(const Application());
}

/// Les réglages de langue, à un seul endroit. Le calendrier et le choix de
/// l'heure sont fournis par Flutter et ne parlent français que si ces
/// délégations sont posées ; sans elles, leur demander le français les fait
/// échouer en silence — un voile gris, rien dedans, aucun moyen de sortir.
/// Un test monte les écrans avec les mêmes réglages, pour qu'on ne puisse
/// plus les retirer sans que quelque chose crie.
const languesGerees = <Locale>[Locale('fr', 'FR')];
const delegationsLangue = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) {
    final sombre = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final t = sombre ? Teintes.sombre : Teintes.clair;
    return MaterialApp(
      title: '2PG Pointage',
      debugShowCheckedModeBanner: false,
      theme: themeDepuis(t, sombre ? Brightness.dark : Brightness.light),
      locale: languesGerees.first,
      supportedLocales: languesGerees,
      localizationsDelegates: delegationsLangue,
      // La palette est posee au-dessus du Navigator, pas dans la premiere
      // page : les dialogues sont des pages voisines, et depuis une page
      // voisine on ne voit pas ce qui est range dans une autre.
      builder: (_, page) => Palette(t: t, child: page ?? const SizedBox()),
      home: const Portail(),
    );
  }
}

/// Une seule application pour tout le monde : le rôle du compte décide de
/// l'écran. Personne ne peut voir celui d'un autre.
class Portail extends StatefulWidget {
  const Portail({super.key});

  @override
  State<Portail> createState() => _PortailState();
}

class _PortailState extends State<Portail> {
  Profil? _profil;
  bool _pret = false;
  String? _refus;

  @override
  void initState() {
    super.initState();
    _relire();
    sb.auth.onAuthStateChange.listen((_) => _relire());
  }

  Future<void> _relire() async {
    if (sb.auth.currentUser == null) {
      if (mounted) setState(() { _profil = null; _refus = null; _pret = true; });
      return;
    }
    Profil? p;
    try {
      p = await monProfil();
    } catch (_) {
      p = null;
    }
    if (!mounted) return;

    // Retiré : plus de fiche. Bloqué : la fiche existe mais est fermée. Dans
    // les deux cas la session est coupée ici, et le serveur refuserait de
    // toute façon — le verrou est dans la base, pas dans cet écran.
    if (p == null || !p.actif) {
      final message = p == null
          ? "Ce compte n'est plus rattaché à l'entreprise. Contactez le bureau."
          : 'Ce compte est bloqué. Contactez le bureau.';
      await sb.auth.signOut();
      if (!mounted) return;
      setState(() { _profil = null; _refus = message; _pret = true; });
      return;
    }
    setState(() { _profil = p; _refus = null; _pret = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_pret) {
      return Center(
        child: CircularProgressIndicator(color: Palette.de(context).pigment),
      );
    }
    if (_profil == null) return EcranConnexion(refus: _refus);
    return _profil!.encadrant
        ? TableauPatron(profil: _profil!)
        : EcranOuvrier(profil: _profil!);
  }
}
