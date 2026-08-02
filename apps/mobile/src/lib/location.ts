import * as Location from 'expo-location';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import * as TaskManager from 'expo-task-manager';

export const TACHE_APPROCHE = 'approche-chantier';

export type Position = {
  lat: number;
  lon: number;
  precision: number | null;
  /** Position simulée par une application tierce (« mock location »). */
  mock: boolean;
};

/**
 * Distance en mètres entre deux points (formule de haversine).
 * Sert uniquement à l'affichage en direct sur le téléphone : la distance qui
 * fait foi est recalculée côté serveur par PostGIS au moment du pointage.
 */
export function distanceM(
  aLat: number, aLon: number, bLat: number, bLon: number
): number {
  const R = 6371000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(bLat - aLat);
  const dLon = rad(bLon - aLon);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLon / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(s)));
}

/** Rayon auquel le téléphone prévient l'ouvrier qu'il approche. */
export function rayonApproche(rayonM: number): number {
  return Math.max(300, rayonM * 5);
}

export async function demanderPermissionPremierPlan(): Promise<boolean> {
  const { status } = await Location.requestForegroundPermissionsAsync();
  return status === 'granted';
}

/**
 * Permission d'arrière-plan, demandée seulement pour le signal d'approche.
 * Elle n'est jamais nécessaire pour pointer : si l'ouvrier refuse, tout le
 * reste continue de fonctionner, il n'est simplement pas prévenu à l'arrivée.
 */
export async function demanderPermissionArrierePlan(): Promise<boolean> {
  const avant = await Location.getForegroundPermissionsAsync();
  if (avant.status !== 'granted') return false;
  const { status } = await Location.requestBackgroundPermissionsAsync();
  return status === 'granted';
}

export async function positionActuelle(): Promise<Position> {
  const p = await Location.getCurrentPositionAsync({
    accuracy: Location.Accuracy.High,
    // Une position de plus de 10 s n'est pas une preuve de présence.
    mayShowUserSettingsDialog: true,
  });
  return {
    lat: p.coords.latitude,
    lon: p.coords.longitude,
    precision: p.coords.accuracy ?? null,
    mock: (p as { mocked?: boolean }).mocked === true,
  };
}

export async function appareilCompromis(): Promise<boolean> {
  // Un appareil rooté ou jailbreaké peut falsifier sa position sans que le
  // drapeau « mock » soit levé. On le signale, on ne bloque pas.
  return Device.isRootedExperimentalAsync ? await Device.isRootedExperimentalAsync() : false;
}

/**
 * Surveillance de zone.
 *
 * Le système d'exploitation réveille l'application au franchissement de la
 * limite, et ne lui livre jamais de flux de positions : l'app ne sait pas où se
 * trouve l'ouvrier, seulement qu'il vient d'entrer dans la zone du chantier.
 * C'est ce qui distingue ce déclencheur d'un traçage continu.
 */
export async function surveillerApproche(
  lat: number, lon: number, rayonM: number, libelle: string
): Promise<boolean> {
  const perm = await Location.getBackgroundPermissionsAsync();
  if (perm.status !== 'granted') return false;

  await arreterSurveillance();
  await Location.startGeofencingAsync(TACHE_APPROCHE, [
    {
      identifier: libelle,
      latitude: lat,
      longitude: lon,
      radius: rayonApproche(rayonM),
      notifyOnEnter: true,
      notifyOnExit: false,
    },
  ]);
  return true;
}

export async function arreterSurveillance(): Promise<void> {
  try {
    if (await Location.hasStartedGeofencingAsync(TACHE_APPROCHE)) {
      await Location.stopGeofencingAsync(TACHE_APPROCHE);
    }
  } catch {
    /* la tâche n'était pas enregistrée */
  }
}

/**
 * Tâche d'arrière-plan. Doit être définie au niveau module, avant le rendu :
 * le système peut relancer l'application directement sur cet évènement.
 */
TaskManager.defineTask(TACHE_APPROCHE, async ({ data, error }) => {
  if (error) return;
  const { eventType, region } = data as {
    eventType: Location.GeofencingEventType;
    region: Location.LocationRegion & { identifier?: string };
  };
  if (eventType !== Location.GeofencingEventType.Enter) return;

  await Notifications.scheduleNotificationAsync({
    content: {
      title: 'Vous approchez du chantier',
      body: `${region.identifier ?? 'Chantier'} — ouvrez l'application pour confirmer votre arrivée.`,
      sound: true,
    },
    trigger: null,
  });
});

export async function preparerNotifications(): Promise<void> {
  Notifications.setNotificationHandler({
    handleNotification: async () => ({
      shouldShowAlert: true,
      shouldPlaySound: true,
      shouldSetBadge: false,
    }),
  });
  await Notifications.requestPermissionsAsync();
}
