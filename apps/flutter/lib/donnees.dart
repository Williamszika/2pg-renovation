import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// L'URL et la clé publique sont faites pour être distribuées : elles ne
/// donnent accès qu'à ce que les règles de sécurité de la base autorisent.
/// La clé secrète n'a rien à faire dans une application installée.
const urlSupabase = 'https://xugujaxoqzsypltvzyny.supabase.co';
const clePublique = 'sb_publishable__jvFyZBXCQaJoorIxLGJIQ_F0Us5-9N';

SupabaseClient get sb => Supabase.instance.client;

// ══ Le compte connecté ══════════════════════════════════════════════════════

class Profil {
  Profil({
    required this.id,
    required this.nom,
    required this.role,
    required this.entrepriseId,
    required this.actif,
  });

  final String id;
  final String nom;
  final String role;
  final String entrepriseId;
  final bool actif;

  bool get encadrant => role == 'patron' || role == 'chef_equipe';

  static Profil? depuis(Map<String, dynamic>? m) => m == null
      ? null
      : Profil(
          id: m['id'] as String,
          nom: (m['nom'] ?? '') as String,
          role: (m['role'] ?? 'ouvrier') as String,
          entrepriseId: (m['entreprise_id'] ?? '') as String,
          actif: (m['actif'] ?? true) as bool,
        );
}

/// Le profil du compte connecté, ou null s'il n'est rattaché à rien.
Future<Profil?> monProfil() async {
  final u = sb.auth.currentUser;
  if (u == null) return null;
  final m = await sb
      .from('utilisateurs')
      .select('id, nom, role, entreprise_id, actif')
      .eq('id', u.id)
      .maybeSingle();
  return Profil.depuis(m);
}

// ══ Côté ouvrier ════════════════════════════════════════════════════════════

class Chantier {
  Chantier(this.m);
  final Map<String, dynamic> m;

  String get id => m['id'] as String;
  String get libelle => (m['libelle'] ?? '') as String;
  String get adresse => (m['adresse'] ?? '') as String;
  String? get codePostal => m['code_postal'] as String?;
  String? get ville => m['ville'] as String?;
  double get lat => (m['lat'] as num).toDouble();
  double get lon => (m['lon'] as num).toDouble();
  int get rayon => (m['rayon_m'] as num).toInt();
  String get heureRdv => (m['heure_rdv'] ?? '08:00') as String;
  int get dureeService => (m['duree_service_min'] as num).toInt();

  String get lieu => [codePostal, ville].where((x) => x != null && x.isNotEmpty).join(' ');
}

class Journee {
  Journee(this.m);
  final Map<String, dynamic> m;

  DateTime? get arrivee => m['arrivee'] == null ? null : DateTime.parse(m['arrivee'] as String);
  DateTime? get depart => m['depart'] == null ? null : DateTime.parse(m['depart'] as String);
  num get pauseMin => (m['pause_min'] ?? 0) as num;
  num? get dureeMin => m['duree_min'] as num?;
  bool get enCours => (m['en_cours'] ?? false) as bool;
  bool get enPause => (m['en_pause'] ?? false) as bool;
}

class MaMission {
  MaMission(this.m);
  final Map<String, dynamic> m;

  String get etat => (m['etat'] ?? 'envoye') as String;
  String? get motif => m['motif'] as String?;
  Chantier get chantier => Chantier(m['mission'] as Map<String, dynamic>);
  Journee? get journee =>
      m['journee'] == null ? null : Journee(m['journee'] as Map<String, dynamic>);
}

Future<MaMission?> maMissionDuJour() async {
  final r = await sb.rpc('ma_mission_du_jour');
  if (r == null) return null;
  return MaMission(Map<String, dynamic>.from(r as Map));
}

Future<void> marquerVue(String missionId) =>
    sb.rpc('marquer_vue', params: {'p_mission_id': missionId});

/// Le serveur recalcule la distance avec PostGIS et tranche : ce que le
/// téléphone annonce ne l'engage pas.
Future<Map<String, dynamic>> confirmerArrivee({
  required String missionId,
  required double lat,
  required double lon,
  double? precision,
}) async {
  final r = await sb.rpc('confirmer_arrivee', params: {
    'p_mission_id': missionId,
    'p_lat': lat,
    'p_lon': lon,
    'p_precision': precision,
  });
  return Map<String, dynamic>.from(r as Map);
}

Future<Map<String, dynamic>> pointer({
  required String missionId,
  required String type,
  double? lat,
  double? lon,
  double? precision,
  String? motif,
}) async {
  final r = await sb.rpc('pointer', params: {
    'p_mission_id': missionId,
    'p_type': type,
    'p_lat': lat,
    'p_lon': lon,
    'p_precision': precision,
    'p_motif': motif,
  });
  return Map<String, dynamic>.from(r as Map);
}

Future<void> signalerProbleme({
  required String missionId,
  required String motif,
  double? lat,
  double? lon,
  double? precision,
}) =>
    sb.rpc('signaler_probleme', params: {
      'p_mission_id': missionId,
      'p_motif': motif,
      'p_lat': lat,
      'p_lon': lon,
      'p_precision': precision,
    });

// ══ Côté encadrement ════════════════════════════════════════════════════════

Future<List<Map<String, dynamic>>> missionsDuJour([String? jour]) async {
  final r = await sb.rpc('missions_du_jour', params: {'p_jour': jour ?? jourCourant()});
  return (r as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
}

String jourCourant() {
  final d = DateTime.now();
  String p(int n) => n < 10 ? '0$n' : '$n';
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}

Future<List<Map<String, dynamic>>> equipe() async {
  final r = await sb
      .from('utilisateurs')
      .select('*')
      .order('actif', ascending: false)
      .order('nom');
  return (r as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
}

Future<String> creerMission({
  required String libelle,
  required String adresse,
  String? codePostal,
  String? ville,
  required double lat,
  required double lon,
  required int rayon,
  required String jour,
  required String heureRdv,
  required int dureeMin,
  required List<String> destinataires,
}) async {
  final r = await sb.rpc('creer_mission', params: {
    'p_libelle': libelle,
    'p_adresse': adresse,
    'p_code_postal': codePostal,
    'p_ville': ville,
    'p_lat': lat,
    'p_lon': lon,
    'p_rayon_m': rayon,
    'p_jour': jour,
    'p_heure_rdv': heureRdv,
    'p_duree_min': dureeMin,
    'p_chantier_id': null,
    'p_destinataires': destinataires,
  });
  return r as String;
}

Future<Map<String, dynamic>> definirActif(String utilisateurId, bool actif) async {
  final r = await sb.rpc('definir_actif',
      params: {'p_utilisateur_id': utilisateurId, 'p_actif': actif});
  return Map<String, dynamic>.from(r as Map);
}

Future<Map<String, dynamic>> retirerUtilisateur(String utilisateurId) async {
  final r = await sb.rpc('retirer_utilisateur', params: {'p_utilisateur_id': utilisateurId});
  return Map<String, dynamic>.from(r as Map);
}

Future<List<Map<String, dynamic>>> exportMois(String debut, String fin) async {
  final r = await sb.rpc('export_mois', params: {'p_debut': debut, 'p_fin': fin});
  return (r as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
}

// ══ Recherche d'adresse ═════════════════════════════════════════════════════

class Adresse {
  Adresse({
    required this.label,
    required this.voie,
    required this.cp,
    required this.ville,
    required this.lat,
    required this.lon,
  });

  final String label, voie, cp, ville;
  final double lat, lon;
}

/// Base Adresse Nationale : service public, gratuit, sans clé, et meilleur que
/// Google sur les adresses françaises puisque c'est la base officielle.
Future<List<Adresse>> chercherAdresse(String q) async {
  if (q.trim().length < 3) return [];
  final u = Uri.parse(
      'https://api-adresse.data.gouv.fr/search/?q=${Uri.encodeQueryComponent(q)}&limit=6');
  final r = await http.get(u).timeout(const Duration(seconds: 8));
  if (r.statusCode != 200) return [];
  final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  return (d['features'] as List).map((f) {
    final p = f['properties'] as Map<String, dynamic>;
    final c = (f['geometry'] as Map<String, dynamic>)['coordinates'] as List;
    return Adresse(
      label: (p['label'] ?? '') as String,
      voie: (p['name'] ?? p['label'] ?? '') as String,
      cp: (p['postcode'] ?? '') as String,
      ville: (p['city'] ?? '') as String,
      lat: (c[1] as num).toDouble(),
      lon: (c[0] as num).toDouble(),
    );
  }).toList();
}

// ══ Cartes ══════════════════════════════════════════════════════════════════

/// La carte intégrée, par l'adresse que Google sert à qui demande
/// « output=embed » : pas de clé, pas de compte de facturation.
String urlCarte(double lat, double lon, int zoom) =>
    'https://maps.google.com/maps?q=$lat,$lon&z=$zoom&hl=fr&output=embed';

String urlItineraire(double lat, double lon) =>
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving';

/// Le lieu ouvert dans la vraie application Maps, pour regarder autour sans
/// lancer un itinéraire.
String urlLieu(double lat, double lon) =>
    'https://www.google.com/maps/search/?api=1&query=$lat,$lon';

/// Google refuse de servir sa carte intégrée en page principale :
/// « The Google Maps Embed API must be used in an iframe. » L'application web
/// y échappait sans le savoir, étant elle-même faite d'iframes ; dans un
/// WebView il faut fabriquer l'iframe à la main.
///
/// Mesuré le 11 août 2026 : l'adresse répond 301 vers
/// `www.google.com/maps/embed`, en portant `x-frame-options: SAMEORIGIN` ; la
/// réponse finale, elle, n'impose plus rien — ni `x-frame-options`, ni
/// `frame-ancestors`. D'où la base donnée au document dans `carte.dart` :
/// `https://maps.google.com/`, qui met aussi la redirection en règle.
String pageCarte(double lat, double lon, int zoom) =>
    '<!doctype html>'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<style>html,body{margin:0;height:100%;overflow:hidden;background:#fff}'
    'iframe{border:0;display:block;width:100%;height:100%}</style>'
    '<iframe src="${urlCarte(lat, lon, zoom)}" allowfullscreen></iframe>';
