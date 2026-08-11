import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'donnees.dart';
import 'theme.dart';

/// La carte se regarde, elle ne se conduit pas. Un doigt posé dessus sert à
/// faire défiler la page, pas à déplacer la carte : dans un formulaire long,
/// une carte qui capte le glissement est un piège dont on ne sort plus.
/// Explorer les lieux se fait dans la vraie application Maps, d'une tape.
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
    ..loadHtmlString(pageCarte(widget.lat, widget.lon, widget.zoom),
        baseUrl: 'https://maps.google.com/');

  @override
  void didUpdateWidget(CarteIntegree vieille) {
    super.didUpdateWidget(vieille);
    // Le patron change d'adresse sans quitter le formulaire : la carte doit
    // suivre, sinon elle montre le chantier précédent — pire qu'aucune carte.
    if (vieille.lat != widget.lat ||
        vieille.lon != widget.lon ||
        vieille.zoom != widget.zoom) {
      _c.loadHtmlString(pageCarte(widget.lat, widget.lon, widget.zoom),
          baseUrl: 'https://maps.google.com/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Palette.de(context);
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(urlLieu(widget.lat, widget.lon)),
          mode: LaunchMode.externalApplication),
      child: Container(
        height: widget.hauteur,
        decoration: BoxDecoration(
          color: t.surface2,
          border: Border.all(color: t.trait),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          IgnorePointer(child: WebViewWidget(controller: _c)),
          Positioned(
            right: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface.withValues(alpha: 0.92),
                border: Border.all(color: t.trait),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.open_in_new, size: 13, color: t.encreDouce),
                  const SizedBox(width: 5),
                  Text('Ouvrir dans Maps',
                      style: TextStyle(
                          color: t.encreDouce,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
