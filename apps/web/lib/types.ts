/** Types du domaine, alignés sur les vues et fonctions SQL. */

export type Role = 'patron' | 'chef_equipe' | 'ouvrier';

export type EtatDestinataire = 'envoye' | 'vue' | 'confirme' | 'probleme' | 'refuse';

export type Utilisateur = {
  id: string;
  nom: string;
  role: Role;
  telephone: string | null;
  actif: boolean;
  appareil_nom: string | null;
  appareil_valide_le: string | null;
};

export type Chantier = {
  id: string;
  libelle: string;
  client_nom: string | null;
  adresse: string;
  code_postal: string | null;
  ville: string | null;
  heures_devisees: number | null;
  statut: 'prevu' | 'en_cours' | 'termine' | 'annule';
};

export type Mission = {
  id: string;
  chantier_id: string | null;
  libelle: string;
  adresse: string;
  code_postal: string | null;
  ville: string | null;
  lat: number;
  lon: number;
  rayon_m: number;
  jour: string;
  heure_rdv: string;
  duree_service_min: number;
  envoyee_le: string;
};

export type Destinataire = {
  destinataire_id: string;
  utilisateur_id: string;
  nom: string;
  role: Role;
  etat: EtatDestinataire;
  vue_le: string | null;
  confirme_le: string | null;
  confirme_dist_m: number | null;
  confirme_source: 'gps' | 'bureau' | null;
  motif: string | null;
  arrivee: string | null;
  depart: string | null;
  pause_min: number | null;
  duree_min: number | null;
  en_cours: boolean | null;
  fin_prevue: string | null;
};

export type SuiviMission = {
  mission: Mission;
  destinataires: Destinataire[];
};

export type Alerte = {
  id: string;
  type: string;
  titre: string;
  detail: string | null;
  lue: boolean;
  cree_le: string;
};

export type MargeChantier = {
  id: string;
  libelle: string;
  client_nom: string | null;
  statut: string;
  heures_devisees: number | null;
  heures_realisees: number;
  ecart_pct: number | null;
};

/** Ce que le formulaire d'envoi remonte au tableau de bord. */
export type NouvelleMission = {
  libelle: string;
  adresse: string;
  codePostal: string | null;
  ville: string | null;
  lat: number;
  lon: number;
  rayon: number;
  heure: string;
  duree: number;
  chantierId: string | null;
  destinataires: string[];
};
