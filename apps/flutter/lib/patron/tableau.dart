import 'dart:async';

import 'package:flutter/material.dart';

import '../donnees.dart';
import '../format.dart';
import '../theme.dart';
import 'envoi.dart';
import 'equipe.dart';
import 'historique.dart';
import 'suivi.dart';

/// Le tableau de bord de l'encadrement.
class TableauPatron extends StatefulWidget {
  const TableauPatron({super.key, required this.profil});

  final Profil profil;

  @override
  State<TableauPatron> createState() => _TableauPatronState();
}

class _TableauPatronState extends State<TableauPatron> {
  List<Map<String, dynamic>> _missions = [];
  List<Map<String, dynamic>> _equipe = [];
  bool _chargement = true;
  String? _erreur;
  Timer? _rafraichir;
  Timer? _redessiner;

  @override
  void initState() {
    super.initState();
    _charger();
    // Les durées en cours avancent sans qu'aucun évènement ne soit émis.
    _rafraichir = Timer.periodic(const Duration(minutes: 1), (_) => _charger());
    // Le retard d'un ouvrier qui n'est pas encore arrivé se calcule à
    // l'affichage : sans redessin, il resterait figé.
    _redessiner = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _rafraichir?.cancel();
    _redessiner?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final r = await Future.wait([missionsDuJour(), equipe()]);
      if (!mounted) return;
      setState(() {
        _missions = r[0];
        _equipe = r[1];
        _chargement = false;
        _erreur = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _erreur = '$e'; _chargement = false; });
    }
  }

  /// Tous les destinataires de la journée, missions confondues.
  List<Map<String, dynamic>> get _tous => _missions
      .expand((m) => ((m['destinataires'] ?? []) as List)
          .map((d) => Map<String, dynamic>.from(d as Map)))
      .toList();

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _charger,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              _entete(t),
              const SizedBox(height: 16),
              if (_chargement)
                Center(child: CircularProgressIndicator(color: t.pigment))
              else ...[
                if (_erreur != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: t.arretPale,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(_erreur!, style: TextStyle(color: t.arret)),
                  ),
                  const SizedBox(height: 14),
                ],
                _compteurs(t),
                const SizedBox(height: 16),
                PanneauEnvoi(equipe: _equipe, apresEnvoi: _charger),
                const SizedBox(height: 16),
                for (final m in _missions) ...[
                  SuiviMission(mission: m, apresAction: _charger),
                  const SizedBox(height: 16),
                ],
                if (_missions.isEmpty) ...[
                  _Panneau(
                    titre: 'Aujourd\'hui',
                    enfant: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text('Aucune adresse envoyée pour aujourd\'hui.',
                            style: TextStyle(color: t.encrePale, fontSize: 14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const PanneauHistorique(),
                const SizedBox(height: 16),
                PanneauEquipe(
                  equipe: _equipe,
                  moiId: widget.profil.id,
                  apresAction: _charger,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _entete(Teintes t) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('2PG RÉNOVATION',
                  style: TextStyle(
                      color: t.pigment,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4)),
              Text('Suivi de chantier',
                  style: TextStyle(
                      color: t.encre,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4)),
              Text('${dateLongue()} · connecté en tant que ${widget.profil.nom}',
                  style: TextStyle(color: t.encrePale, fontSize: 13)),
            ]),
          ),
          TextButton(
            onPressed: () => sb.auth.signOut(),
            child: Text('Se déconnecter',
                style: TextStyle(color: t.encreDouce, fontSize: 13)),
          ),
        ],
      );

  Widget _compteurs(Teintes t) {
    final tous = _tous;
    final surPlace =
        tous.where((d) => d['etat'] == 'confirme' && d['depart'] == null).length;
    final attente =
        tous.where((d) => d['etat'] == 'envoye' || d['etat'] == 'vue').length;
    final bloques = tous.where((d) => d['etat'] == 'probleme').length;
    final realise = tous.fold<num>(
        0, (s, d) => s + ((d['duree_min'] ?? 0) as num));
    // Le prévu ne compte que ceux qui ont confirmé : un ouvrier jamais arrivé
    // ne doit pas gonfler l'objectif de la journée.
    final prevu = _missions.fold<num>(0, (s, m) {
      final mm = Map<String, dynamic>.from(m['mission'] as Map);
      final n = ((m['destinataires'] ?? []) as List)
          .where((d) => (d as Map)['etat'] == 'confirme')
          .length;
      return s + (mm['duree_service_min'] as num) * n;
    });

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: [
        _Compteur('Sur le chantier', '$surPlace', t.ok),
        _Compteur('En attente', '$attente', t.alerte),
        _Compteur('Bloqués', '$bloques', t.arret),
        _Compteur('Réalisé / prévu',
            '${heuresDecimales(realise)} / ${heuresDecimales(prevu)}', t.encre),
      ],
    );
  }
}

class _Compteur extends StatelessWidget {
  const _Compteur(this.libelle, this.valeur, this.couleur);

  final String libelle, valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.trait),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(libelle.toUpperCase(),
              style: TextStyle(
                  color: t.encrePale,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valeur,
                style: TextStyle(
                    color: couleur, fontSize: 24, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Le cadre commun à tous les panneaux du tableau de bord.
class Panneau extends StatelessWidget {
  const Panneau({
    super.key,
    required this.titre,
    required this.enfant,
    this.action,
    this.accent = false,
  });

  final String titre;
  final Widget enfant;
  final Widget? action;
  final bool accent;

  @override
  Widget build(BuildContext context) => _Panneau(
        titre: titre,
        enfant: enfant,
        action: action,
        accent: accent,
      );
}

class _Panneau extends StatelessWidget {
  const _Panneau({
    required this.titre,
    required this.enfant,
    this.action,
    this.accent = false,
  });

  final String titre;
  final Widget enfant;
  final Widget? action;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: accent ? t.pigment : t.trait),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          color: accent ? t.pigmentPale : t.surface2,
          child: Row(children: [
            Expanded(
              child: Text(titre.toUpperCase(),
                  style: TextStyle(
                      color: accent ? t.pigment : t.encreDouce,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9)),
            ),
            if (action != null) action!,
          ]),
        ),
        enfant,
      ]),
    );
  }
}
