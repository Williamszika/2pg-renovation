import 'dart:async';

import 'package:flutter/material.dart';

import '../carte.dart';
import '../donnees.dart';
import '../format.dart';
import '../theme.dart';
import 'tableau.dart';

/// Envoyer une adresse : recherche, jour, heure, seuil, destinataires.
class PanneauEnvoi extends StatefulWidget {
  const PanneauEnvoi({super.key, required this.equipe, required this.apresEnvoi});

  final List<Map<String, dynamic>> equipe;
  final Future<void> Function() apresEnvoi;

  @override
  State<PanneauEnvoi> createState() => _PanneauEnvoiState();
}

class _PanneauEnvoiState extends State<PanneauEnvoi> {
  final _recherche = TextEditingController();
  final _libelle = TextEditingController();

  Adresse? _choisie;
  List<Adresse> _suggestions = [];
  Timer? _minuteur;

  DateTime _jour = DateTime.now();
  TimeOfDay _heure = const TimeOfDay(hour: 8, minute: 0);
  int _duree = 480;
  int _rayon = 50;
  final Set<String> _coches = {};
  bool _occupe = false;
  String? _erreur;

  @override
  void dispose() {
    _minuteur?.cancel();
    _recherche.dispose();
    _libelle.dispose();
    super.dispose();
  }

  /// On attend 300 ms après la dernière lettre : chercher à chaque frappe
  /// enverrait dix requêtes pour une rue.
  void _chercher(String q) {
    _minuteur?.cancel();
    _minuteur = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await chercherAdresse(q);
        if (mounted) setState(() => _suggestions = r);
      } catch (_) {
        if (mounted) setState(() => _suggestions = []);
      }
    });
  }

  List<Map<String, dynamic>> get _ouvriers =>
      widget.equipe.where((u) => u['actif'] == true).toList();

  static final _durees = [for (var d = 60; d <= 660; d += 30) d];

  /// Vingt-et-une durées ne tiennent pas dans un menu déroulant sur un
  /// téléphone : il couvrait l'écran entier sans montrer par où sortir. Une
  /// feuille par le bas, titrée, avec un bouton Fermer.
  Future<void> _choisirDuree() async {
    final t = Palette.de(context);
    final choix = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: t.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _FeuilleDuree(valeurs: _durees, courante: _duree),
    );
    if (choix != null && mounted) setState(() => _duree = choix);
  }

  bool get _pret => _choisie != null && _coches.isNotEmpty;

  Future<void> _envoyer() async {
    if (!_pret) return;
    setState(() { _occupe = true; _erreur = null; });
    try {
      final a = _choisie!;
      await creerMission(
        libelle: _libelle.text.trim().isEmpty ? a.voie : _libelle.text.trim(),
        adresse: a.voie,
        codePostal: a.cp.isEmpty ? null : a.cp,
        ville: a.ville.isEmpty ? null : a.ville,
        lat: a.lat,
        lon: a.lon,
        rayon: _rayon,
        jour: jourISO(_jour),
        heureRdv: '${deuxChiffres(_heure.hour)}:${deuxChiffres(_heure.minute)}',
        dureeMin: _duree,
        destinataires: _coches.toList(),
      );
      if (!mounted) return;
      setState(() {
        _choisie = null;
        _recherche.clear();
        _libelle.clear();
        _coches.clear();
        _suggestions = [];
      });
      await widget.apresEnvoi();
    } catch (e) {
      setState(() => _erreur = '$e');
    }
    if (mounted) setState(() => _occupe = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    final plusTard = jourISO(_jour) != jourISO();

    return Panneau(
      titre: 'Envoyer une adresse',
      accent: true,
      enfant: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_choisie == null) ...[
            TextField(
              controller: _recherche,
              onChanged: _chercher,
              decoration: const InputDecoration(
                labelText: 'Adresse du chantier',
                hintText: 'Tapez une rue, une ville…',
              ),
            ),
            for (final a in _suggestions)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(a.voie, style: const TextStyle(fontSize: 14)),
                subtitle: Text('${a.cp} ${a.ville}',
                    style: TextStyle(color: t.encrePale, fontSize: 12.5)),
                onTap: () => setState(() {
                  _choisie = a;
                  _suggestions = [];
                  if (_libelle.text.trim().isEmpty) _libelle.text = a.voie;
                }),
              ),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_choisie!.voie,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        Text('${_choisie!.cp} ${_choisie!.ville}',
                            style:
                                TextStyle(color: t.encrePale, fontSize: 12.5)),
                      ]),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _choisie = null;
                    _recherche.clear();
                  }),
                  child: const Text('Modifier'),
                ),
              ]),
            ),
          // Une adresse juste peut désigner le mauvais endroit : deux rues du
          // même nom, un numéro à l'autre bout. Le patron voit le lieu avant
          // que trois ouvriers y aillent.
          if (_choisie != null) ...[
            const SizedBox(height: 10),
            CarteIntegree(
              lat: _choisie!.lat,
              lon: _choisie!.lon,
              hauteur: 150,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _libelle,
            decoration: const InputDecoration(
              labelText: 'Client ou libellé',
              hintText: 'Ex. : Mme Durand — salle de bains',
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _Choix(
                libelle: 'Jour',
                valeur: dateCourte(jourISO(_jour)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _jour,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    locale: const Locale('fr', 'FR'),
                  );
                  if (d != null) setState(() => _jour = d);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choix(
                libelle: 'Rendez-vous',
                valeur:
                    '${deuxChiffres(_heure.hour)}:${deuxChiffres(_heure.minute)}',
                onTap: () async {
                  final h = await showTimePicker(
                      context: context, initialTime: _heure);
                  if (h != null) setState(() => _heure = h);
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _Choix(
            libelle: 'Temps de service',
            valeur: duree(_duree),
            onTap: _choisirDuree,
          ),
          const SizedBox(height: 12),
          const _Etiquette('Seuil de confirmation'),
          Row(children: [
            for (final (r, note) in [
              (20, 'strict'),
              (50, 'conseillé'),
              (100, 'ville dense')
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Segment(
                    titre: '$r m',
                    note: note,
                    actif: _rayon == r,
                    onTap: () => setState(() => _rayon = r),
                  ),
                ),
              ),
          ]),
          if (_rayon == 20) ...[
            const SizedBox(height: 6),
            Text('Souvent hors de portée du GPS.',
                style: TextStyle(color: t.alerte, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          const _Etiquette('Envoyer à'),
          if (_ouvriers.isEmpty)
            Text('Aucun compte actif.',
                style: TextStyle(color: t.encrePale, fontSize: 13))
          else
            for (final u in _ouvriers)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _coches.contains(u['id']),
                title: Text('${u['nom']}',
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _coches.add(u['id'] as String);
                  } else {
                    _coches.remove(u['id']);
                  }
                }),
              ),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(_erreur!, style: TextStyle(color: t.arret, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: t.pigment,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
            ),
            onPressed: (_pret && !_occupe) ? _envoyer : null,
            child: Text(
              _occupe
                  ? 'Envoi…'
                  : _choisie == null
                      ? 'Choisissez une adresse'
                      : _coches.isEmpty
                          ? 'Sélectionnez au moins un ouvrier'
                          : plusTard
                              ? 'Programmer pour ${dateCourte(jourISO(_jour))} · ${_coches.length} ouvrier${_coches.length > 1 ? 's' : ''}'
                              : 'Envoyer à ${_coches.length} ouvrier${_coches.length > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    );
  }
}

/// La liste des durées, ouverte sur la valeur en cours plutôt qu'en haut :
/// huit heures est le cas courant, et il est au quatorzième rang.
class _FeuilleDuree extends StatefulWidget {
  const _FeuilleDuree({required this.valeurs, required this.courante});

  final List<int> valeurs;
  final int courante;

  @override
  State<_FeuilleDuree> createState() => _FeuilleDureeState();
}

class _FeuilleDureeState extends State<_FeuilleDuree> {
  static const _hauteurLigne = 50.0;
  late final ScrollController _defilement;

  @override
  void initState() {
    super.initState();
    final rang = widget.valeurs.indexOf(widget.courante);
    // Deux lignes au-dessus, pour qu'on voie qu'il y a du choix avant. Un
    // décalage trop grand est ramené dans les bornes une fois la hauteur
    // réelle connue.
    _defilement = ScrollController(
      initialScrollOffset:
          rang < 0 ? 0 : ((rang - 2) * _hauteurLigne).clamp(0.0, 1e6),
    );
  }

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 8, 6),
          child: Row(children: [
            Expanded(
              child: Text('Temps de service',
                  style: TextStyle(
                      color: t.encre, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ]),
        ),
        Divider(height: 1, color: t.traitPale),
        Flexible(
          child: ListView.builder(
            controller: _defilement,
            shrinkWrap: true,
            itemExtent: _hauteurLigne,
            itemCount: widget.valeurs.length,
            itemBuilder: (_, i) {
              final d = widget.valeurs[i];
              final actif = d == widget.courante;
              return InkWell(
                onTap: () => Navigator.pop(context, d),
                child: Container(
                  color: actif ? t.pigmentPale : null,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(children: [
                    Expanded(
                      child: Text(duree(d),
                          style: TextStyle(
                              color: actif ? t.pigment : t.encre,
                              fontSize: 15.5,
                              fontWeight:
                                  actif ? FontWeight.w700 : FontWeight.w400)),
                    ),
                    if (actif) Icon(Icons.check, size: 19, color: t.pigment),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _Etiquette extends StatelessWidget {
  const _Etiquette(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texte.toUpperCase(),
            style: TextStyle(
                color: Palette.de(context).encrePale,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7)),
      );
}

class _Choix extends StatelessWidget {
  const _Choix({required this.libelle, required this.valeur, required this.onTap});

  final String libelle, valeur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Etiquette(libelle),
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: t.surface2,
            border: Border.all(color: t.trait),
            borderRadius: BorderRadius.circular(10),
          ),
          // Le chevron dit que ça s'ouvre. Sans lui, les trois champs
          // ressemblent à du texte affiché et personne n'y touche.
          child: Row(children: [
            Expanded(
              child: Text(valeur,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.encre, fontSize: 14.5)),
            ),
            Icon(Icons.expand_more, size: 19, color: t.encrePale),
          ]),
        ),
      ),
    ]);
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.titre,
    required this.note,
    required this.actif,
    required this.onTap,
  });

  final String titre, note;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: actif ? t.pigment : t.surface2,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(children: [
          Text(titre,
              style: TextStyle(
                  color: actif ? Colors.white : t.encreDouce,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          Text(note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: actif ? Colors.white70 : t.encrePale, fontSize: 10)),
        ]),
      ),
    );
  }
}
