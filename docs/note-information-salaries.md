# Note d'information aux salariés — modèle à adapter

> **Comment s'en servir.** Ce document est un modèle de travail, pas un conseil juridique.
> Les champs entre crochets sont à compléter. **Faites-le relire par le comptable ou le
> juriste de l'entreprise avant diffusion** — comptez une heure, c'est l'heure la mieux
> investie du projet.
>
> Il doit être remis à chaque salarié **contre signature, avant la mise en service** de
> l'application. Sans cette remise préalable, le dispositif est irrégulier et les données
> qu'il produit sont inexploitables en cas de litige.

---

## Note d'information — mise en place d'un outil de décompte du temps de travail

**2PG Rénovation** — 34 rue de Ribaute, 31650 Saint-Orens-de-Gameville
Date de mise en service : **[JJ/MM/AAAA]**

### Pourquoi cet outil

L'entreprise a l'obligation légale de décompter chaque jour le temps de travail de chacun
(articles L3171-1 et suivants du Code du travail). Ce décompte se fait aujourd'hui sur des
feuilles d'heures papier, remplies de mémoire, souvent en fin de semaine.

À compter du **[JJ/MM/AAAA]**, il est remplacé par une application mobile de pointage.
Concrètement, pour vous :

- vos heures sont enregistrées à la minute près, sans avoir à les reconstituer de mémoire ;
- vos heures supplémentaires sont comptées automatiquement ;
- vous consultez vos heures à tout moment depuis votre téléphone ;
- vous n'avez plus de feuille d'heures à remplir.

### Comment ça marche

Le matin, l'application affiche l'adresse du chantier, l'heure de rendez-vous et une carte.

**Votre arrivée s'enregistre toute seule.** Tant que l'application est ouverte, elle compare
votre position à celle du chantier pour vous afficher la distance restante. Dès que vous
entrez dans le périmètre défini (50 mètres par défaut), la présence est enregistrée : vous
n'avez aucun bouton à appuyer. Un bouton **Je suis arrivé** reste disponible si le signal
tarde.

En partant, vous appuyez sur **J'ai terminé**. Pour la coupure du midi, sur **Pause** puis
**Reprise**.

### Ce qui est relevé, et ce qui ne l'est pas

Ces points sont importants, ils sont donc écrits noir sur blanc.

**Ce que l'application lit sans le conserver.** Quand elle est ouverte, elle lit votre
position pour calculer la distance qui vous sépare du chantier et l'afficher à l'écran. Cette
lecture reste **dans votre téléphone** : rien n'est transmis ni enregistré. Elle s'arrête dès
que vous fermez l'application.

**Ce qui est enregistré.** Uniquement au moment de l'arrivée et du départ : votre position à
cet instant précis et la distance calculée jusqu'au chantier, pour attester que le pointage a
bien été fait sur place.

**Ce qui n'est jamais fait :**

- **Vous n'êtes pas suivi ni localisé en continu.** Aucun trajet, aucun déplacement, aucun
  historique de positions n'est constitué.
- **Rien n'est relevé quand l'application est fermée** — ni sur le trajet domicile-travail,
  ni pendant les pauses, ni le soir, ni le week-end.
- **Aucune photo de vous n'est prise.** Les photos éventuelles concernent le chantier
  (avancement des travaux), jamais les personnes.
- Si vous ne parvenez pas à pointer (sous-sol, absence de réseau, GPS indisponible), **le
  pointage reste possible** : il vous est simplement demandé d'indiquer pourquoi.

### Données enregistrées et durées de conservation

| Donnée | Durée de conservation |
|---|---|
| Nom, rôle, coordonnées professionnelles | Durée du contrat de travail |
| Heures d'arrivée, de départ, de pause, durée travaillée | 5 ans (obligations liées à la paie) |
| Chantier affecté | 5 ans |
| Coordonnées GPS relevées au moment du pointage | **2 mois**, puis effacement automatique |
| Distance au chantier au moment du pointage | 5 ans |

- **Finalité :** décompte du temps de travail, établissement de la paie, suivi de la
  réalisation des chantiers.
- **Base légale :** obligation légale de l'employeur (article L3171-2 du Code du travail) et
  intérêt légitime de l'entreprise.
- **Qui a accès :** le dirigeant et, pour son équipe uniquement, le chef d'équipe. Aucune
  transmission à un tiers, en dehors du cabinet comptable pour l'établissement des bulletins
  de paie et des prestataires techniques ci-dessous.

### Prestataires techniques

L'application s'appuie sur trois services extérieurs. Aucun ne reçoit vos heures ni vos
positions, à l'exception du premier, qui héberge la base :

| Prestataire | Ce qu'il reçoit | Où |
|---|---|---|
| **Supabase** | héberge la base de données : comptes, heures, positions de pointage | Irlande (Union européenne) |
| **GitHub Pages** | sert les fichiers de l'application. Reçoit l'adresse IP de votre téléphone à l'ouverture | États-Unis |
| **Google Maps** | affiche la carte du chantier. Reçoit l'adresse IP de votre téléphone et peut déposer des cookies | États-Unis |

La carte Google sert uniquement à vous montrer où se trouve le chantier. **Elle ne transmet
pas votre position à Google** : c'est l'adresse du chantier qui lui est envoyée, pas la
vôtre. Comme tout site consulté depuis un téléphone, l'affichage révèle en revanche votre
adresse IP.

### Vos droits

Vous disposez d'un droit d'accès, de rectification, d'opposition et de limitation sur vos
données.

**Pour consulter vos heures, demandez-les au bureau** : le relevé vous est remis sous un mois.
L'application ne vous affiche que votre journée en cours — elle ne conserve aucun historique
de votre côté.

Pour toute demande ou réclamation : **[nom du contact]** — **[email / téléphone]**.

Vous pouvez également introduire une réclamation auprès de la CNIL (www.cnil.fr).

---

**Remise de la note**

Je soussigné(e) **[Prénom NOM]** reconnais avoir reçu et pris connaissance de la présente
note d'information relative à la mise en place de l'application de décompte du temps de
travail.

Fait à ......................................, le ......................................

Signature du salarié :

---

## Rappels pour l'employeur

À faire en parallèle de la remise de cette note :

1. **Registre des traitements** — créer une fiche « gestion du temps de travail » décrivant
   la finalité, les données, les destinataires et les durées ci-dessus. Obligatoire même
   avec trois salariés.
2. **Analyse d'impact (AIPD)** — recommandée pour un dispositif de suivi des employés. Une
   version allégée suffit à cette taille d'entreprise.
3. **CSE** — information/consultation obligatoire uniquement si l'effectif atteint
   11 salariés. À vérifier.
4. **Téléphone personnel** — si l'application est installée sur le téléphone personnel du
   salarié, son accord écrit est nécessaire et une indemnisation doit être prévue. La
   solution la plus simple reste de fournir un téléphone professionnel.
5. **Conserver les notes signées** pendant toute la durée de vie du dispositif : ce sont
   elles qui rendent les données opposables en cas de litige.
6. **Transferts hors Union européenne** — GitHub et Google sont établis aux États-Unis. Ils
   ne reçoivent ni heures ni positions, seulement l'adresse IP du téléphone au moment de
   l'affichage. À mentionner dans le registre des traitements. Pour s'en dispenser
   entièrement, il faudrait renoncer à la carte et héberger les fichiers ailleurs — la base,
   elle, est déjà en Irlande.
7. **Relire cette note à chaque évolution de l'application.** Une note qui décrit un
   fonctionnement périmé ne protège plus rien. Deux passages l'étaient déjà : la confirmation
   d'arrivée est devenue automatique, et l'écran « Mes heures » annoncé aux salariés n'existe
   pas — l'ouvrier ne voit que sa journée en cours, sans historique.
