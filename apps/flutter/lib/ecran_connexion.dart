import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'donnees.dart';
import 'theme.dart';

const versionApp = '1.0.0';

class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key, this.refus});

  /// Message posé par le portail quand un compte bloqué ou retiré vient
  /// d'être déconnecté : il doit survivre au retour sur cet écran.
  final String? refus;

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion> {
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  bool _occupe = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _erreur = widget.refus;
  }

  @override
  void dispose() {
    _email.dispose();
    _mdp.dispose();
    super.dispose();
  }

  Future<void> _entrer() async {
    setState(() { _occupe = true; _erreur = null; });
    try {
      await sb.auth.signInWithPassword(
        email: _email.text.trim().toLowerCase(),
        password: _mdp.text,
      );
      // Le portail écoute les changements de session et prendra la suite.
    } on AuthException catch (e) {
      setState(() {
        _erreur = RegExp('invalid login', caseSensitive: false).hasMatch(e.message)
            ? 'Identifiant ou mot de passe incorrect.'
            : RegExp('not confirmed', caseSensitive: false).hasMatch(e.message)
                ? "Ce compte n'a pas encore été confirmé. Contactez le bureau."
                : e.message;
      });
    } catch (_) {
      setState(() {
        _erreur = 'Pas de connexion au serveur. Vérifiez votre réseau, puis réessayez.';
      });
    }
    if (mounted) setState(() => _occupe = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('2PG',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: t.pigment,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4)),
                  const SizedBox(height: 6),
                  Text('Suivi de chantier',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: t.encre,
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 26),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Adresse e-mail'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mdp,
                    obscureText: true,
                    onSubmitted: (_) => _occupe ? null : _entrer(),
                    decoration: const InputDecoration(labelText: 'Mot de passe'),
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(_erreur!,
                        style: TextStyle(color: t.arret, fontSize: 13, height: 1.4)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: t.pigment,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                    onPressed: _occupe ? null : _entrer,
                    child: Text(_occupe ? 'Connexion…' : 'Se connecter',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                  Text('version $versionApp',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: t.encrePale,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
