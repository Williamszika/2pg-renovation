import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'donnees.dart';
import 'theme.dart';

/// La carte se regarde, elle ne se conduit pas : la navigation reste au bouton
/// Itinéraire, qui ouvre la vraie application Google Maps.
///
/// L'ouvrier la voit pour trouver le chantier, le patron pour vérifier qu'il
/// envoie tout le monde au bon endroit avant que quiconque prenne la route.
class CarteIntegree extends StatefulWidget {
  const CarteIntegree({
    super.key,
    required this.lat,
    required this.lon,
    this.zoom = 16,
    this.hauteur = 168,
  });

  final double lat, lon;
  final int zoom;
  final double hauteur;

  @override
  State<CarteIntegree> createState() => _CarteIntegreeState();
}

class _CarteIntegreeState extends State<CarteIntegree> {
  late final WebViewController _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(urlCarte(widget.lat, widget.lon, widget.zoom)));

  @override
  void didUpdateWidget(CarteIntegree vieille) {
    super.didUpdateWidget(vieille);
    // Le patron change d'adresse sans quitter le formulaire : la carte doit
    // suivre, sinon elle montre le chantier précédent — pire qu'aucune carte.
    if (vieille.lat != widget.lat ||
        vieille.lon != widget.lon ||
        vieille.zoom != widget.zoom) {
      _c.loadRequest(Uri.parse(urlCarte(widget.lat, widget.lon, widget.zoom)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return Container(
      height: widget.hauteur,
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
