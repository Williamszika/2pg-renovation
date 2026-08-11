import 'dart:math';

const _consonnes = 'bcdfgjkmnpqrstvwxz';
const _voyelles = 'aeiou';
const _chiffres = '23456789';

/// Un mot de passe qui se dicte au téléphone sans se tromper : trois syllabes
/// et trois chiffres, « bakumo-473 ».
///
/// Sur un chantier, le patron lit ce mot de passe à voix haute dans le bruit.
/// Chaque paire qui se confond est donc écartée : pas de `0` ni de `1` dans
/// les chiffres, pas de `l` dans les consonnes — les trois seuls caractères
/// qui s'échangent à l'œil. Le `h` et le `y`, muets ou ambigus à l'oral,
/// sortent aussi. Les voyelles restent entières : lettres et chiffres
/// occupent des segments séparés, et comme aucun zéro n'existe ici, le `o`
/// ne peut être pris pour autre chose.
///
/// `Random.secure` et non `Random()` : ce mot de passe ouvre l'accès aux
/// données de l'entreprise le temps que son porteur en change. Un générateur
/// prévisible les ouvrirait à qui sait l'heure de création du compte.
String tirerMotDePasse() {
  final d = Random.secure();
  final m = StringBuffer();
  for (var i = 0; i < 3; i++) {
    m.write(_consonnes[d.nextInt(_consonnes.length)]);
    m.write(_voyelles[d.nextInt(_voyelles.length)]);
  }
  m.write('-');
  for (var i = 0; i < 3; i++) {
    m.write(_chiffres[d.nextInt(_chiffres.length)]);
  }
  return m.toString();
}

/// Le message prêt à envoyer, pour que le patron n'ait rien à recopier.
String messageIdentifiants({
  required String nom,
  required String email,
  required String motDePasse,
  required String adresseApp,
}) {
  final prenom = nom.trim().split(' ').first;
  return "Bonjour $prenom, voici tes identifiants pour l'application 2PG.\n\n"
      'Adresse : $adresseApp\n'
      'E-mail : $email\n'
      'Mot de passe : $motDePasse\n\n'
      "Sur iPhone, ouvre le lien avec Safari puis Partager > Sur l'écran "
      "d'accueil.\nSur Android, Chrome proposera d'installer l'application.";
}
