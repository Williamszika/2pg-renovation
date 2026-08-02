import { useColorScheme } from 'react-native';

const clair = {
  fond: '#F6F5F2',
  surface: '#FFFFFF',
  surface2: '#EFEDE8',
  encre: '#1B1F26',
  encreDouce: '#5A626E',
  encrePale: '#8A909B',
  trait: '#E2DFD8',
  traitPale: '#EDEBE5',
  pigment: '#2E3FA3',
  pigmentPale: '#E8EAF7',
  ok: '#2E7A57',
  okPale: '#E3F0EA',
  alerte: '#A8721A',
  alertePale: '#F6EEDF',
  arret: '#A93A34',
  arretPale: '#F7E7E5',
  surPigment: '#FFFFFF',
};

const sombre: typeof clair = {
  fond: '#111317',
  surface: '#191C21',
  surface2: '#21252B',
  encre: '#E9E7E2',
  encreDouce: '#99A0AB',
  encrePale: '#6E7681',
  trait: '#2A2E35',
  traitPale: '#222630',
  pigment: '#8496F5',
  pigmentPale: '#1D2340',
  ok: '#4FB183',
  okPale: '#14291F',
  alerte: '#D3A24A',
  alertePale: '#2C2416',
  arret: '#E2726B',
  arretPale: '#2E1917',
  surPigment: '#0F1116',
};

export type Palette = typeof clair;

export function usePalette(): Palette {
  return useColorScheme() === 'dark' ? sombre : clair;
}
