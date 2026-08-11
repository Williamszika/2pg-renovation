import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../donnees.dart';
import '../motdepasse.dart';
import '../theme.dart';
import 'tableau.dart';

/// Ce qu'on affiche une fois le compte créé — et une seule fois. La base ne
/// garde du mot de passe qu'une empreinte bcrypt, que personne ne sait
/// inverser : fermer cette carte sans l'avoir transmis oblige à en fixer un
/// nouveau depuis Supabase.
typedef Identifiants = ({String nom, String email, String mdp, bool utilisable});

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

  final _nom = TextEditingController();
  final _email = TextEditingController();
  final _mdp = TextEditingController(text: tirerMotDePasse());
  bool _formulaire = false;
  bool _copie = false;
  Identifiants? _identifiants;

  @override
  void dispose() {
    _nom.dispose();
    _email.dispose();
    _mdp.dispose();
    super.dispose();
  }

  int get _actifs => widget.equipe.where((u) => u['actif'] == true).length;
  int get _bloques => widget.equipe.length - _actifs;

  void _dire(String texte, Ton ton) {
    if (mounted) setState(() { _message = texte; _tonMessage = ton; });
  }

  Future<void> _creer() async {
    final nom = _nom.text.trim();
    final email = _email.text.trim().toLowerCase();
    final mdp = _mdp.text;

    if (nom.isEmpty) {
      _dire('Il faut un nom : c\'est lui qui apparaîtra dans le suivi.', Ton.arret);
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _dire("Cette adresse e-mail n'est pas valide.", Ton.arret);
      return;
    }
    if (mdp.length < 6) {
      _dire('Le mot de passe doit faire au moins six caractères.', Ton.arret);
      return;
    }

    setState(() { _occupe = true; _message = null; _identifiants = null; });
    try {
      final c = await creerOuvrier(nom: nom, email: email, motDePasse: mdp);
      if (!mounted) return;
      setState(() {
        _identifiants =
            (nom: nom, email: email, mdp: mdp, utilisable: c.utilisable);
        _formulaire = false;
        _copie = false;
      });
      _nom.clear();
      _email.clear();
      _mdp.text = tirerMotDePasse();
      if (!c.utilisable) {
        _dire(
          'Compte créé, mais « Confirm email » est actif sur le projet : il '
          'devra ouvrir le lien reçu par courriel avant de pouvoir se '
          'connecter. Pour l\'éviter — Authentication → Sign In / Providers → '
          'Email → décocher « Confirm email ».',
          Ton.alerte,
        );
      }
      await widget.apresAction();
    } catch (e) {
      _dire('$e', Ton.arret);
    }
    if (mounted) setState(() => _occupe = false);
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
      action: TextButton(
        onPressed: _occupe
            ? null
            : () => setState(() {
                  _formulaire = !_formulaire;
                  if (_formulaire) _message = null;
                }),
        child: Text(_formulaire ? 'Fermer' : 'Ajouter un ouvrier',
            style: TextStyle(color: t.pigment, fontSize: 13)),
      ),
      enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_formulaire) _formulaireCreation(t),
        if (_identifiants != null) _carteIdentifiants(t, _identifiants!),
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

  Widget _formulaireCreation(Teintes t) => Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: t.traitPale))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _nom,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom de l\'ouvrier',
              hintText: 'Ex. : Karim Benali',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Adresse e-mail',
              hintText: 'Elle lui servira d\'identifiant',
            ),
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _mdp,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
              ),
            ),
            const SizedBox(width: 8),
            // Tiré d'avance : un patron pressé choisirait « 123456 », et ce
            // mot de passe ouvre les données de l'entreprise.
            IconButton(
              tooltip: 'En tirer un autre',
              onPressed:
                  _occupe ? null : () => setState(() => _mdp.text = tirerMotDePasse()),
              icon: Icon(Icons.casino_outlined, color: t.encreDouce),
            ),
          ]),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: t.pigment,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
            ),
            onPressed: _occupe ? null : _creer,
            child: Text(_occupe ? 'Création…' : 'Créer le compte',
                style:
                    const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _carteIdentifiants(Teintes t, Identifiants i) {
    final message = messageIdentifiants(
      nom: i.nom,
      email: i.email,
      motDePasse: i.mdp,
      adresseApp: adresseApp,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      decoration: BoxDecoration(
        color: i.utilisable ? t.okPale : t.alertePale,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Identifiants de ${i.nom}',
                style: TextStyle(
                    color: i.utilisable ? t.ok : t.alerte,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Fermer',
            onPressed: () => setState(() => _identifiants = null),
            icon: Icon(Icons.close, size: 18, color: t.encreDouce),
          ),
        ]),
        const SizedBox(height: 8),
        _ligne(t, 'E-mail', i.email),
        const SizedBox(height: 6),
        _ligne(t, 'Mot de passe', i.mdp),
        const SizedBox(height: 10),
        Text(
          i.utilisable
              ? "Notez-le maintenant : il n'est lisible qu'ici. La base n'en "
                  "garde qu'une empreinte, que personne ne sait inverser."
              : 'Ce compte ne pourra pas se connecter tant que le lien reçu '
                  "par courriel n'aura pas été ouvert.",
          style: TextStyle(color: t.encreDouce, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: message));
            if (mounted) setState(() => _copie = true);
          },
          icon: Icon(_copie ? Icons.check : Icons.copy_outlined, size: 16),
          label: Text(_copie ? 'Copié' : 'Copier le message'),
          style: OutlinedButton.styleFrom(
            foregroundColor: t.encre,
            side: BorderSide(color: t.trait),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ]),
    );
  }

  Widget _ligne(Teintes t, String etiquette, String valeur) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(etiquette,
                style: TextStyle(color: t.encrePale, fontSize: 12.5)),
          ),
          Expanded(
            child: SelectableText(valeur,
                style: TextStyle(
                    color: t.encre,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      );
}
