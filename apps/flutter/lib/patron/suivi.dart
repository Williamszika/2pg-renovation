import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../donnees.dart';
import '../format.dart';
import '../theme.dart';
import 'tableau.dart';

/// Le suivi d'une adresse envoyée.
///
/// Rien ne s'y valide à la main : l'état se déduit des faits. Le seul bouton
/// qui apparaisse sert au cas où le GPS d'un ouvrier ne descend pas.
class SuiviMission extends StatelessWidget {
  const SuiviMission({super.key, required this.mission, required this.apresAction});

  final Map<String, dynamic> mission;
  final Future<void> Function() apresAction;

  Map<String, dynamic> get _m => Map<String, dynamic>.from(mission['mission'] as Map);

  List<Map<String, dynamic>> get _dest =>
      ((mission['destinataires'] ?? []) as List)
          .map((d) => Map<String, dynamic>.from(d as Map))
          .toList();

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    final m = _m;
    final lieu = [m['code_postal'], m['ville']]
        .where((x) => x != null && '$x'.isNotEmpty)
        .join(' ');

    return Panneau(
      titre: '${m['libelle']} · ${heure(m['heure_rdv'])}',
      action: Pastille('sous ${m['rayon_m']} m', ton: Ton.pigment),
      enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(children: [
            Expanded(
              child: Text('${m['adresse']}${lieu.isEmpty ? '' : ', $lieu'}',
                  style: TextStyle(color: t.encreDouce, fontSize: 13.5)),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(urlItineraire(
                    (m['lat'] as num).toDouble(), (m['lon'] as num).toDouble())),
                mode: LaunchMode.externalApplication,
              ),
              icon: Icon(Icons.place_outlined, size: 17, color: t.pigment),
              label: Text('Carte',
                  style: TextStyle(color: t.pigment, fontSize: 12.5)),
            ),
          ]),
        ),
        for (final d in _dest)
          _Ligne(
            d: d,
            heureRdv: (m['heure_rdv'] ?? '08:00') as String,
            dureeService: (m['duree_service_min'] as num).toInt(),
            apresAction: apresAction,
          ),
      ]),
    );
  }
}

class _Ligne extends StatefulWidget {
  const _Ligne({
    required this.d,
    required this.heureRdv,
    required this.dureeService,
    required this.apresAction,
  });

  final Map<String, dynamic> d;
  final String heureRdv;
  final int dureeService;
  final Future<void> Function() apresAction;

  @override
  State<_Ligne> createState() => _LigneState();
}

class _LigneState extends State<_Ligne> {
  bool _occupe = false;

  /// Retard à l'arrivée, en minutes. Null si pas encore arrivé.
  int? get _retard {
    final d = widget.d;
    final t = d['arrivee'] ?? d['confirme_le'];
    if (t == null) return null;
    return minutesDuJour(t) - minutesDuJour(widget.heureRdv);
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    final d = widget.d;
    final fait = d['duree_min'] as num?;
    final arrivee = d['arrivee'] ?? d['confirme_le'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.traitPale)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(d['nom'] as String,
                style: TextStyle(
                    color: t.encre, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          ..._etat(t),
        ]),
        const SizedBox(height: 5),
        Wrap(spacing: 14, runSpacing: 3, children: [
          _bribe(t, 'Arrivé', arrivee == null ? '—' : heure(arrivee)),
          if (_retard != null && _retard! > 5)
            _bribe(t, 'Retard', duree(_retard), couleur: t.alerte),
          if (d['confirme_dist_m'] != null)
            _bribe(t, 'Distance', metres(d['confirme_dist_m'] as num?)),
          if ((d['pause_min'] ?? 0) as num > 0)
            _bribe(t, 'Pause', '${((d['pause_min'] as num)).round()} min'),
          if (d['depart'] != null) _bribe(t, 'Départ', heure(d['depart'])),
          if (fait != null)
            _bribe(t, 'Réalisé', duree(fait),
                couleur: fait > widget.dureeService ? t.arret : null),
        ]),
        if (d['motif'] != null) ...[
          const SizedBox(height: 5),
          Text('« ${d['motif']} »',
              style: TextStyle(
                  color: t.encrePale, fontSize: 12.5, fontStyle: FontStyle.italic)),
        ],
        if (d['etat'] == 'probleme') ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _occupe ? null : _debloquer,
              child: const Text('Débloquer'),
            ),
          ),
        ],
      ]),
    );
  }

  /// L'état se déduit des faits, personne ne le décide.
  List<Widget> _etat(Teintes t) {
    final d = widget.d;
    if (d['etat'] == 'confirme') {
      if (d['depart'] != null) return [const Pastille('Journée close')];
      final r = _retard;
      return [
        const Pastille('Sur le chantier', ton: Ton.ok),
        if (r != null && r > 5) ...[
          const SizedBox(width: 6),
          const Pastille('Arrivé en retard', ton: Ton.alerte),
        ],
      ];
    }
    if (d['etat'] == 'probleme') {
      return [const Pastille('GPS insuffisant', ton: Ton.arret)];
    }
    final ecoule = minutesDuJour(DateTime.now()) - minutesDuJour(widget.heureRdv);
    if (ecoule > 30) return [const Pastille('Absent', ton: Ton.arret)];
    if (ecoule > 5) {
      return [Pastille('En retard · ${duree(ecoule)}', ton: Ton.alerte)];
    }
    if (d['vue_le'] != null) {
      return [Pastille('Vue ${heure(d['vue_le'])}', ton: Ton.pigment)];
    }
    return [Pastille('Attendu ${heure(widget.heureRdv)}')];
  }

  Widget _bribe(Teintes t, String libelle, String valeur, {Color? couleur}) =>
      RichText(
        text: TextSpan(children: [
          TextSpan(
              text: '$libelle ',
              style: TextStyle(color: t.encrePale, fontSize: 12)),
          TextSpan(
              text: valeur,
              style: TextStyle(
                  color: couleur ?? t.encre,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ]),
      );

  Future<void> _debloquer() async {
    setState(() => _occupe = true);
    try {
      await sb.rpc('valider_presence',
          params: {'p_dest_id': widget.d['destinataire_id']});
      await widget.apresAction();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _occupe = false);
  }
}
