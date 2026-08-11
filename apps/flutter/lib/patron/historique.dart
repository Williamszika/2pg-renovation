import 'package:flutter/material.dart';

import '../donnees.dart';
import '../format.dart';
import '../theme.dart';
import 'tableau.dart';

/// L'historique : combien chacun a fait, et ce qui s'est passé chaque jour.
///
/// Rien de nouveau en base — export_mois() renvoie déjà, pour une période, une
/// ligne par salarié et par journée.
class PanneauHistorique extends StatefulWidget {
  const PanneauHistorique({super.key});

  @override
  State<PanneauHistorique> createState() => _PanneauHistoriqueState();
}

class _PanneauHistoriqueState extends State<PanneauHistorique> {
  bool _ouvert = false;
  bool _chargement = false;
  String? _erreur;
  List<Map<String, dynamic>> _lignes = [];
  String _periode = '7';

  (String, String) _bornes(String nom) {
    final d = DateTime.now();
    if (nom == 'mois') {
      return ('${d.year}-${deuxChiffres(d.month)}-01', jourISO());
    }
    if (nom == 'precedent') {
      final debut = DateTime(d.year, d.month - 1, 1);
      // Le jour 0 du mois courant est le dernier jour du mois précédent.
      final fin = DateTime(d.year, d.month, 0);
      return (jourISO(debut), jourISO(fin));
    }
    return (jourISO(d.subtract(const Duration(days: 6))), jourISO());
  }

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final (debut, fin) = _bornes(_periode);
      final r = await exportMois(debut, fin);
      if (!mounted) return;
      setState(() { _lignes = r; _chargement = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _erreur = '$e'; _chargement = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Panneau(
      titre: 'Historique',
      action: TextButton(
        onPressed: () {
          setState(() => _ouvert = !_ouvert);
          // On ne va chercher le relevé qu'à la première ouverture.
          if (_ouvert && _lignes.isEmpty && !_chargement) _charger();
        },
        child: Text(_ouvert ? 'Fermer' : 'Ouvrir',
            style: TextStyle(color: t.pigment, fontSize: 13)),
      ),
      enfant: !_ouvert
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      for (final (cle, nom) in [
                        ('7', '7 jours'),
                        ('mois', 'Ce mois'),
                        ('precedent', 'Mois dernier')
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () {
                                setState(() => _periode = cle);
                                _charger();
                              },
                              borderRadius: BorderRadius.circular(9),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 9),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _periode == cle ? t.pigment : t.surface2,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(nom,
                                    style: TextStyle(
                                        color: _periode == cle
                                            ? Colors.white
                                            : t.encreDouce,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 14),
                    if (_chargement)
                      Center(child: CircularProgressIndicator(color: t.pigment))
                    else if (_erreur != null)
                      Text(_erreur!, style: TextStyle(color: t.arret))
                    else
                      ..._contenu(t),
                  ]),
            ),
    );
  }

  List<Widget> _contenu(Teintes t) {
    if (_lignes.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text('Aucune journée sur cette période.',
                style: TextStyle(color: t.encrePale, fontSize: 13.5)),
          ),
        ),
      ];
    }

    final parQui = <String, ({int jours, num heures})>{};
    final parJour = <String, List<Map<String, dynamic>>>{};
    num total = 0;

    for (final r in _lignes) {
      final h = (r['duree_h'] ?? 0) as num;
      total += h;
      final nom = r['salarie'] as String;
      final q = parQui[nom] ?? (jours: 0, heures: 0 as num);
      parQui[nom] = (jours: q.jours + 1, heures: q.heures + h);
      final jour = '${r['jour']}';
      (parJour[jour] ??= []).add(r);
    }

    final tries = parQui.entries.toList()
      ..sort((a, b) => b.value.heures.compareTo(a.value.heures));
    final jours = parJour.keys.toList()..sort((a, b) => b.compareTo(a));

    String hh(num h) {
      final m = (h * 60).round();
      return '${m ~/ 60} h ${deuxChiffres(m % 60)}';
    }

    return [
      _Titre('Total · ${hh(total)} sur ${parQui.length} personne'
          '${parQui.length > 1 ? 's' : ''}'),
      for (final e in tries)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: t.traitPale))),
          child: Row(children: [
            Expanded(
                child: Text(e.key,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600))),
            Text('${e.value.jours} jour${e.value.jours > 1 ? 's' : ''}',
                style: TextStyle(color: t.encrePale, fontSize: 12.5)),
            const SizedBox(width: 12),
            Text(hh(e.value.heures),
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      _Titre('Jour par jour'),
      for (final j in jours) ...[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(dateCourte(j),
              style: TextStyle(
                  color: t.pigment, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        for (final r in parJour[j]!)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.traitPale))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['salarie']}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text('${r['chantier'] ?? r['adresse'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: t.encrePale, fontSize: 12)),
                    ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${heure(r['arrivee'])} – ${heure(r['depart'])}',
                    style: TextStyle(color: t.encreDouce, fontSize: 12.5)),
                if (((r['pause_min'] ?? 0) as num) > 0)
                  Text('${r['pause_min']} min pause',
                      style: TextStyle(color: t.encrePale, fontSize: 11.5)),
              ]),
              const SizedBox(width: 10),
              SizedBox(
                width: 56,
                child: Text(hh((r['duree_h'] ?? 0) as num),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
      ],
    ];
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(texte.toUpperCase(),
            style: TextStyle(
                color: Palette.de(context).encreDouce,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );
}
