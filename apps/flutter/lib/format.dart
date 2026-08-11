import 'package:intl/intl.dart';

String deuxChiffres(int n) => n < 10 ? '0$n' : '$n';

/// « 08:02 ». Accepte un DateTime, une chaîne ISO ou une heure « 08:02:00 ».
String heure(dynamic v) {
  if (v == null) return '—';
  if (v is String && RegExp(r'^\d{1,2}:\d{2}').hasMatch(v)) return v.substring(0, 5);
  final d = v is DateTime ? v.toLocal() : DateTime.parse(v as String).toLocal();
  return '${deuxChiffres(d.hour)}:${deuxChiffres(d.minute)}';
}

/// « 45 min », « 7 h 30 ».
String duree(num? minutes) {
  if (minutes == null) return '—';
  final m = minutes.round().clamp(0, 1 << 30);
  final h = m ~/ 60;
  return h == 0 ? '$m min' : '$h h ${deuxChiffres(m % 60)}';
}

/// « + 12 min », « − 40 min », « à l'heure ».
String ecart(num minutes) {
  if (minutes.abs() < 1) return "à l'heure";
  return (minutes > 0 ? '+ ' : '− ') + duree(minutes.abs());
}

String metres(num? m) {
  if (m == null) return '—';
  return m >= 1000
      ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
      : '${m.round()} m';
}

String jourISO([DateTime? d]) {
  final x = d ?? DateTime.now();
  return '${x.year}-${deuxChiffres(x.month)}-${deuxChiffres(x.day)}';
}

/// « Lundi 10 août » — en français seule la première lettre prend la majuscule.
String dateLongue([DateTime? d]) {
  final s = DateFormat('EEEE d MMMM', 'fr_FR').format(d ?? DateTime.now());
  return s[0].toUpperCase() + s.substring(1);
}

/// « aujourd'hui », « demain », sinon « lundi 11 août ».
///
/// La date est construite à midi : à minuit, un changement d'heure ou un
/// décalage de fuseau ferait basculer la journée d'un cran.
String dateCourte(String? iso) {
  if (iso == null || iso.isEmpty) return "aujourd'hui";
  final d = DateTime.parse('${iso.substring(0, 10)}T12:00:00');
  final n = DateTime.parse('${jourISO()}T12:00:00');
  final ecartJours = d.difference(n).inDays;
  if (ecartJours == 0) return "aujourd'hui";
  if (ecartJours == 1) return 'demain';
  if (ecartJours == -1) return 'hier';
  return DateFormat('EEEE d MMMM', 'fr_FR').format(d);
}

/// « 7,5 h » — pour les cumuls, où le quart d'heure compte moins que l'ordre
/// de grandeur.
String heuresDecimales(num? minutes) {
  if (minutes == null) return '—';
  return '${(minutes / 60).toStringAsFixed(1).replaceAll('.', ',')} h';
}

/// Minutes écoulées depuis minuit, pour une heure « 08:00 » comme pour un
/// horodatage. On reconnaît l'heure seule à sa forme : un horodatage ISO est
/// lui aussi une chaîne.
int minutesDuJour(dynamic v) {
  if (v is String && RegExp(r'^\d{1,2}:\d{2}').hasMatch(v)) {
    final p = v.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
  final d = v is DateTime ? v.toLocal() : DateTime.parse(v as String).toLocal();
  return d.hour * 60 + d.minute;
}
