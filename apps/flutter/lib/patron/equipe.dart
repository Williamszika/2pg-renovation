import 'package:flutter/material.dart';

import '../donnees.dart';
import '../theme.dart';
import 'tableau.dart';

/// L'équipe : qui existe, qui est bloqué, et les trois gestes du patron.
class PanneauEquipe extends StatefulWidget {
  const PanneauEquipe({
    super.key,
    required this.equipe,
    required this.moiId,
    required this.apresAction,
  });

  final List<Map<String, dynamic>> equipe;
  final String moiId;
  final Future<void> Function() apresAction;

  @override
  State<PanneauEquipe> createState() => _PanneauEquipeState();
}

class _PanneauEquipeState extends State<PanneauEquipe> {
  bool _occupe = false;
  String? _message;
  Ton _tonMessage = Ton.neutre;

  int get _actifs => widget.equipe.where((u) => u['actif'] == true).length;
  int get _bloques => widget.equipe.length - _actifs;

  void _dire(String texte, Ton ton) {
    if (mounted) setState(() { _message = texte; _tonMessage = ton; });
  }

  Future<void> _basculer(Map<String, dynamic> u, bool actif) async {
    if (!actif) {
      final ok = await _confirmer(
        'Bloquer ${u['nom']} ?',
        '${u['nom']} ne pourra plus se connecter ni pointer, et les adresses '
        'du jour qu\'il n\'a pas encore confirmées lui seront retirées.\n\n'
        'Ses heures déjà enregistrées sont conservées.',
        'Bloquer',
      );
      if (!ok) return;
    }
    setState(() => _occupe = true);
    try {
      final r = await definirActif(u['id'] as String, actif);
      await widget.apresAction();
      _dire(
        actif
            ? '${r['nom']} peut de nouveau se connecter.'
            : '${r['nom']} est bloqué.',
        actif ? Ton.ok : Ton.alerte,
      );
    } catch (e) {
      _dire('$e', Ton.arret);
    }
    if (mounted) setState(() => _occupe = false);
  }

  Future<void> _retirer(Map<String, dynamic> u) async {
    final ok = await _confirmer(
      'Supprimer ${u['nom']} ?',
      'Définitif, et possible uniquement s\'il n\'a aucune heure enregistrée.',
      'Supprimer',
    );
    if (!ok) return;
    setState(() => _occupe = true);
    try {
      final r = await retirerUtilisateur(u['id'] as String);
      await widget.apresAction();
      if (r['ok'] == true) {
        _dire('${r['nom']} a été supprimé.', Ton.ok);
      } else {
        final n = r['pointages'] as int;
        _dire(
          '${r['nom']} a $n pointage${n > 1 ? 's' : ''} enregistré${n > 1 ? 's' : ''} : '
          'la loi impose de les garder cinq ans. Le compte reste bloqué, ce qui '
          'lui interdit tout accès.',
          Ton.alerte,
        );
      }
    } catch (e) {
      _dire('$e', Ton.arret);
    }
    if (mounted) setState(() => _occupe = false);
  }

  Future<bool> _confirmer(String titre, String corps, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre, style: const TextStyle(fontSize: 17)),
        content: Text(corps, style: const TextStyle(fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Panneau(
      titre: 'Équipe · $_actifs'
          '${_bloques > 0 ? ' + $_bloques bloqué${_bloques > 1 ? 's' : ''}' : ''}',
      enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.equipe.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('Aucun compte enregistré.',
                  style: TextStyle(color: t.encrePale, fontSize: 14)),
            ),
          ),
        for (final u in widget.equipe)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: t.traitPale))),
            child: Row(children: [
              Expanded(
                child: Opacity(
                  opacity: u['actif'] == true ? 1 : 0.55,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text('${u['nom']}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14.5, fontWeight: FontWeight.w700)),
                          ),
                          if (u['actif'] != true) ...[
                            const SizedBox(width: 6),
                            const Pastille('Bloqué', ton: Ton.arret),
                          ],
                        ]),
                        Text(_role(u['role'] as String?),
                            style:
                                TextStyle(color: t.encrePale, fontSize: 12.5)),
                      ]),
                ),
              ),
              if (u['id'] != widget.moiId)
                if (u['actif'] == true)
                  TextButton(
                    onPressed: _occupe ? null : () => _basculer(u, false),
                    child: Text('Bloquer',
                        style: TextStyle(color: t.encreDouce, fontSize: 13)),
                  )
                else ...[
                  TextButton(
                    onPressed: _occupe ? null : () => _basculer(u, true),
                    child: Text('Débloquer',
                        style: TextStyle(color: t.pigment, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: _occupe ? null : () => _retirer(u),
                    child: Text('Supprimer',
                        style: TextStyle(color: t.arret, fontSize: 13)),
                  ),
                ],
            ]),
          ),
        if (_message != null)
          Container(
            padding: const EdgeInsets.all(12),
            color: switch (_tonMessage) {
              Ton.ok => t.okPale,
              Ton.alerte => t.alertePale,
              Ton.arret => t.arretPale,
              _ => t.surface2,
            },
            child: Text(_message!,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: switch (_tonMessage) {
                      Ton.ok => t.ok,
                      Ton.alerte => t.alerte,
                      Ton.arret => t.arret,
                      _ => t.encreDouce,
                    })),
          ),
      ]),
    );
  }

  String _role(String? r) => r == 'patron'
      ? 'Patron'
      : r == 'chef_equipe'
          ? 'Chef d\'équipe'
          : 'Ouvrier';
}
