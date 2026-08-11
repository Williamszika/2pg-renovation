import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'donnees.dart';
import 'format.dart';
import 'theme.dart';

/// L'écran de l'ouvrier : son adresse du jour, et rien d'autre.
///
/// Pas d'historique, pas de chiffres, pas les autres. Il n'a rien à décider
/// non plus : dès qu'il entre dans le périmètre, sa présence part toute seule.
class EcranOuvrier extends StatefulWidget {
  const EcranOuvrier({super.key, required this.profil});

  final Profil profil;

  @override
  State<EcranOuvrier> createState() => _EcranOuvrierState();
}

class _EcranOuvrierState extends State<EcranOuvrier> {
  MaMission? _mission;
  bool _chargement = true;
  String? _erreur;

  StreamSubscription<Position>? _suivi;
  double? _distance;
  double? _precision;
  bool? _permis;

  /// Une confirmation automatique est déjà partie : sans ce verrou, chaque
  /// position reçue en relancerait une.
  bool _autoEnCours = false;
  bool _confirmeAuto = false;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _suivi?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final m = await maMissionDuJour();
      if (!mounted) return;
      setState(() { _mission = m; _chargement = false; });
      if (m != null) {
        unawaited(marquerVue(m.chantier.id).catchError((_) {}));
        await _demarrerPosition();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _erreur = '$e'; _chargement = false; });
    }
  }

  Future<void> _demarrerPosition() async {
    if (_suivi != null) return;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    final ok = p == LocationPermission.always || p == LocationPermission.whileInUse;
    if (!mounted) return;
    setState(() => _permis = ok);
    if (!ok) return;

    // Le filtre à 5 m évite de recalculer sans arrêt quand le téléphone est
    // posé : la position ne remonte que si l'ouvrier a vraiment bougé.
    _suivi = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_position, onError: (_) {});
  }

  void _position(Position p) {
    final c = _mission?.chantier;
    if (c == null) return;
    final d = Geolocator.distanceBetween(p.latitude, p.longitude, c.lat, c.lon);
    if (mounted) setState(() { _distance = d; _precision = p.accuracy; });
    _confirmerSiArrive(p);
  }

  /// Confirmation automatique. Le serveur recalcule la distance avec PostGIS
  /// et peut refuser : ce que le téléphone annonce ne l'engage pas.
  Future<void> _confirmerSiArrive(Position p) async {
    final m = _mission;
    if (m == null || _autoEnCours || _occupe) return;
    if (m.etat == 'confirme') return;
    final r = m.chantier.rayon;
    if (_distance == null || _distance! > r) return;
    if (p.accuracy > r) return;

    _autoEnCours = true;
    try {
      final rep = await confirmerArrivee(
        missionId: m.chantier.id,
        lat: p.latitude,
        lon: p.longitude,
        precision: p.accuracy,
      );
      if (rep['ok'] == true) {
        _confirmeAuto = true;
        await _charger();
      }
    } catch (_) {
      // Réseau coupé, serveur qui refuse : la prochaine position réessaiera.
    } finally {
      _autoEnCours = false;
    }
  }

  Future<void> _pointer(String type, {String? motif}) async {
    final m = _mission;
    if (m == null || _occupe) return;
    setState(() => _occupe = true);
    try {
      Position? p;
      try {
        p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 12));
      } catch (_) {
        p = null;
      }
      final rep = await pointer(
        missionId: m.chantier.id,
        type: type,
        lat: p?.latitude,
        lon: p?.longitude,
        precision: p?.accuracy,
        motif: motif,
      );
      if (rep['ok'] == false && rep['motif'] == 'motif_requis') {
        if (!mounted) return;
        setState(() => _occupe = false);
        final raison = await _demanderMotif(
          'Vous êtes à ${metres(rep['distance_m'] as num?)} du chantier',
          'Expliquez en une phrase pourquoi vous pointez votre départ d\'ici.',
        );
        if (raison != null) await _pointer(type, motif: raison);
        return;
      }
      await _charger();
    } catch (e) {
      _dire('$e');
    }
    if (mounted) setState(() => _occupe = false);
  }

  Future<String?> _demanderMotif(String titre, String aide) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre, style: const TextStyle(fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(aide, style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: 12),
          TextField(controller: c, autofocus: true, minLines: 2, maxLines: 3),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, c.text.trim().length >= 3 ? c.text.trim() : null),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  void _dire(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _charger,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              Text('Bonjour ${widget.profil.nom.split(' ').first}',
                  style: TextStyle(
                      color: t.encre, fontSize: 26, fontWeight: FontWeight.w700)),
              Text(dateLongue(),
                  style: TextStyle(color: t.encrePale, fontSize: 15)),
              const SizedBox(height: 18),
              ..._corps(t),
              const SizedBox(height: 26),
              Divider(color: t.trait),
              const SizedBox(height: 8),
              Text('Position relevée uniquement à l\'arrivée et au départ.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.encrePale, fontSize: 12)),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => sb.auth.signOut(),
                  child: Text('Se déconnecter',
                      style: TextStyle(color: t.encreDouce, fontSize: 13.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _corps(Teintes t) {
    if (_chargement) {
      return [
        const SizedBox(height: 60),
        Center(child: CircularProgressIndicator(color: t.pigment)),
      ];
    }
    if (_erreur != null) return [_Bandeau(_erreur!, ton: Ton.arret)];

    final m = _mission;
    if (m == null) {
      return [
        const SizedBox(height: 40),
        Center(
          child: Column(children: [
            Text('Rien pour aujourd\'hui',
                style: TextStyle(
                    color: t.encre, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Le bureau ne vous a envoyé aucune adresse.',
                style: TextStyle(color: t.encrePale, fontSize: 14)),
          ]),
        ),
      ];
    }

    final c = m.chantier;
    final j = m.journee;
    final w = <Widget>[];

    if (_permis == false) {
      w.add(_Bandeau(
        'L\'accès à votre position est refusé. Sans lui, impossible de '
        'confirmer votre arrivée. Autorisez-le dans les réglages du téléphone.',
        ton: Ton.arret,
      ));
      w.add(const SizedBox(height: 12));
    }

    if (m.etat != 'confirme') {
      w.addAll(_avantArrivee(t, m, c));
    } else if (j != null && !j.enCours) {
      w.add(_CarteAdresse(chantier: c));
      w.add(const SizedBox(height: 14));
      w.add(_JourneeFinie(journee: j));
    } else {
      w.addAll(_surPlace(t, m, c, j));
    }
    return w;
  }

  List<Widget> _avantArrivee(Teintes t, MaMission m, Chantier c) {
    final rayon = c.rayon;
    final pres = _distance != null && _distance! <= rayon;
    final fiable = _precision == null || _precision! <= rayon;
    final peut = pres && fiable;

    return [
      _CarteAdresse(chantier: c),
      const SizedBox(height: 12),
      _Carte(chantier: c),
      const SizedBox(height: 12),
      Center(
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Rendez-vous '),
            TextSpan(
                text: heure(c.heureRdv),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: '  ·  ${duree(c.dureeService)} de service'),
          ]),
          style: TextStyle(color: t.encreDouce, fontSize: 14),
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: pres ? t.okPale : t.alertePale,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              pres ? 'Vous êtes sur l\'adresse' : 'Approchez-vous de l\'adresse',
              style: TextStyle(
                  color: pres ? t.ok : t.alerte,
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ),
          Text(_distance == null ? 'recherche…' : metres(_distance),
              style: TextStyle(
                  color: pres ? t.ok : t.alerte,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
      const SizedBox(height: 12),
      if (peut)
        _GrosBouton(
          titre: 'Je suis arrivé',
          sous: 'Confirmation en cours…  ·  à ${metres(_distance)}',
          ton: Ton.ok,
          onTap: _occupe ? null : () => _confirmerAlaMain(),
        )
      else
        _GrosBoutonInactif(
          titre: !fiable
              ? 'GPS trop imprécis'
              : _distance == null
                  ? 'Recherche du signal…'
                  : 'Encore ${metres(_distance! - rayon)}',
          sous: !fiable
              ? '± ${_precision!.round()} m pour un seuil de $rayon m'
              : 'La confirmation part seule à moins de $rayon m',
        ),
      if (m.etat == 'probleme') ...[
        const SizedBox(height: 12),
        _Bandeau('Demande envoyée au bureau\n« ${m.motif ?? ''} »', ton: Ton.alerte),
      ] else if (!peut) ...[
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _occupe ? null : _signaler,
            child: Text('Je n\'arrive pas à confirmer',
                style: TextStyle(color: Palette.de(context).encreDouce)),
          ),
        ),
      ],
    ];
  }

  List<Widget> _surPlace(Teintes t, MaMission m, Chantier c, Journee? j) {
    final arrivee = j?.arrivee;
    final pause = j?.pauseMin ?? 0;
    final faites = arrivee == null
        ? 0.0
        : DateTime.now().difference(arrivee).inMinutes - pause.toDouble();
    final finPrevue = arrivee?.add(Duration(minutes: c.dureeService + pause.round()));
    final enPause = j?.enPause ?? false;

    return [
      _CarteAdresse(chantier: c),
      if (_confirmeAuto) ...[
        const SizedBox(height: 12),
        _Bandeau(
          'Présence confirmée automatiquement\n'
          'Vous êtes entré dans le périmètre à ${heure(arrivee)}. '
          'Le bureau en a été informé.',
          ton: Ton.ok,
        ),
      ],
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: enPause ? t.alertePale : t.okPale,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(enPause ? 'En pause' : 'Sur le chantier depuis',
              style: TextStyle(
                  color: enPause ? t.alerte : t.ok,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Text(duree(faites.clamp(0, double.infinity)),
              style: TextStyle(
                  color: enPause ? t.alerte : t.ok,
                  fontSize: 34,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Arrivé ${heure(arrivee)}'
            '${finPrevue != null ? '   ·   Fin prévue ${heure(finPrevue)}' : ''}',
            style: TextStyle(color: t.encreDouce, fontSize: 13),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (enPause)
        _GrosBouton(
          titre: 'Reprendre',
          sous: heure(DateTime.now()),
          ton: Ton.ok,
          onTap: _occupe ? null : () => _pointer('pause_fin'),
        )
      else ...[
        _GrosBouton(
          titre: 'J\'ai terminé',
          sous: heure(DateTime.now()),
          ton: Ton.arret,
          onTap: _occupe ? null : () => _pointer('depart'),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _occupe ? null : () => _pointer('pause_debut'),
            child: Text('Prendre ma pause',
                style: TextStyle(color: t.encreDouce)),
          ),
        ),
      ],
    ];
  }

  Future<void> _confirmerAlaMain() async {
    final m = _mission;
    if (m == null) return;
    setState(() => _occupe = true);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      final r = await confirmerArrivee(
        missionId: m.chantier.id,
        lat: p.latitude,
        lon: p.longitude,
        precision: p.accuracy,
      );
      if (r['ok'] == true) {
        _confirmeAuto = true;
        await _charger();
      } else {
        _dire(r['motif'] == 'trop_loin'
            ? 'Encore trop loin : ${metres(r['distance_m'] as num?)} du chantier.'
            : 'Le GPS n\'est pas assez précis pour confirmer.');
      }
    } catch (e) {
      _dire('$e');
    }
    if (mounted) setState(() => _occupe = false);
  }

  Future<void> _signaler() async {
    final m = _mission;
    if (m == null) return;
    final motif = await _demanderMotif(
      'Signaler au bureau',
      'Dites en une phrase ce qui vous empêche de confirmer — sous-sol, pas de '
      'réseau, adresse introuvable.',
    );
    if (motif == null) return;
    setState(() => _occupe = true);
    try {
      await signalerProbleme(missionId: m.chantier.id, motif: motif);
      await _charger();
    } catch (e) {
      _dire('$e');
    }
    if (mounted) setState(() => _occupe = false);
  }
}

// ══ Morceaux d'écran ════════════════════════════════════════════════════════

class _CarteAdresse extends StatelessWidget {
  const _CarteAdresse({required this.chantier});

  final Chantier chantier;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => launchUrl(
        Uri.parse(urlItineraire(chantier.lat, chantier.lon)),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.trait),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(chantier.libelle,
                  style: TextStyle(
                      color: t.encrePale, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(chantier.adresse,
                  style: TextStyle(
                      color: t.encre,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.25)),
              if (chantier.lieu.isNotEmpty)
                Text(chantier.lieu,
                    style: TextStyle(color: t.encre, fontSize: 17, height: 1.3)),
            ]),
          ),
          const SizedBox(width: 10),
          Column(children: [
            Icon(Icons.navigation_outlined, color: t.pigment, size: 28),
            const SizedBox(height: 2),
            Text('ITINÉRAIRE',
                style: TextStyle(
                    color: t.pigment,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ]),
        ]),
      ),
    );
  }
}

/// La carte se regarde, elle ne se conduit pas : la navigation reste au
/// bouton Itinéraire, qui ouvre la vraie application Google Maps.
class _Carte extends StatefulWidget {
  const _Carte({required this.chantier});

  final Chantier chantier;

  @override
  State<_Carte> createState() => _CarteState();
}

class _CarteState extends State<_Carte> {
  late final WebViewController _c;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
          Uri.parse(urlCarte(widget.chantier.lat, widget.chantier.lon, 16)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.trait),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: WebViewWidget(controller: _c),
    );
  }
}

class _JourneeFinie extends StatelessWidget {
  const _JourneeFinie({required this.journee});

  final Journee journee;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Icon(Icons.check_circle_outline, color: t.ok, size: 40),
        const SizedBox(height: 8),
        Text('Journée terminée',
            style: TextStyle(
                color: t.encre, fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${duree(journee.dureeMin)} sur le chantier',
            style: TextStyle(color: t.encreDouce, fontSize: 15)),
        Text('${heure(journee.arrivee)} – ${heure(journee.depart)}',
            style: TextStyle(color: t.encrePale, fontSize: 13.5)),
      ]),
    );
  }
}

class _GrosBouton extends StatelessWidget {
  const _GrosBouton({
    required this.titre,
    required this.sous,
    required this.ton,
    this.onTap,
  });

  final String titre, sous;
  final Ton ton;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    final couleur = switch (ton) {
      Ton.ok => t.ok,
      Ton.arret => t.arret,
      _ => t.pigment,
    };
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: couleur,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        child: Column(children: [
          Text(titre,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text(sous,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _GrosBoutonInactif extends StatelessWidget {
  const _GrosBoutonInactif({required this.titre, required this.sous});

  final String titre, sous;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(titre,
            style: TextStyle(
                color: t.encrePale, fontSize: 19, fontWeight: FontWeight.w800)),
        Text(sous, style: TextStyle(color: t.encrePale, fontSize: 12.5)),
      ]),
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau(this.texte, {this.ton = Ton.pigment});

  final String texte;
  final Ton ton;

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    final (fond, encre) = switch (ton) {
      Ton.ok => (t.okPale, t.ok),
      Ton.alerte => (t.alertePale, t.alerte),
      Ton.arret => (t.arretPale, t.arret),
      _ => (t.pigmentPale, t.pigment),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
      child: Text(texte,
          style: TextStyle(color: encre, fontSize: 13.5, height: 1.45)),
    );
  }
}
