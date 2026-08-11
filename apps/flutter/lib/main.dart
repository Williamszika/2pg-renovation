import 'package:flutter/material.dart';
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
  await Supabase.initialize(url: urlSupabase, anonKey: clePublique);
  runApp(const Application());
}

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
      home: Palette(t: t, child: const Portail()),
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
