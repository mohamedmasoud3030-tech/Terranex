/**
 * Sector identity constants — dependency-free on purpose.
 *
 * Both the UI layer (`src/shared/ui/sector.tsx`) and feature label modules
 * need these, and feature labels must not import from `shared/ui` (that would
 * create a cycle through `features/workspace/nav`). Keeping them here lets
 * either side import them safely.
 */

export type SectorKey = 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK';

export const SECTOR_KEYS: ReadonlyArray<SectorKey> = ['REAL_ESTATE', 'AGRICULTURE', 'LIVESTOCK'];

/** Arabic operator label. Authored source language; English is a translation. */
export const SECTOR_AR: Record<SectorKey, string> = {
  REAL_ESTATE: 'عقارات',
  AGRICULTURE: 'زراعة',
  LIVESTOCK: 'ثروة حيوانية',
};

/** Colour token class for chips and rails. Identity only — never meaning. */
export const SECTOR_TONE_CLASS: Record<SectorKey, string> = {
  REAL_ESTATE: 'sector-real-estate',
  AGRICULTURE: 'sector-agriculture',
  LIVESTOCK: 'sector-livestock',
};

/**
 * Theming class. Set on a container so its tab strip, rails and card accents
 * inherit the vertical's colour. Applies to any element wrapping a card.
 */
export const SECTOR_THEME_CLASS: Record<SectorKey, string> = {
  REAL_ESTATE: 'sector-theme-real-estate',
  AGRICULTURE: 'sector-theme-agriculture',
  LIVESTOCK: 'sector-theme-livestock',
};

export function isSectorKey(value: string | null | undefined): value is SectorKey {
  return value === 'REAL_ESTATE' || value === 'AGRICULTURE' || value === 'LIVESTOCK';
}
