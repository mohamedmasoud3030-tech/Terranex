/**
 * Sector identity — shared by the workspace header, project cards and chips.
 *
 * The three verticals belong to one system, so they share geometry (16px
 * stroke-based glyphs on the same grid) and differ in hue only. The glyph is
 * always paired with the Arabic label: colour marks the vertical, it never
 * carries meaning by itself.
 */

import { SECTOR_TONE_CLASS, SECTOR_THEME_CLASS, type SectorKey } from '@/features/workspace/sectors';

export { SECTOR_TONE_CLASS, SECTOR_THEME_CLASS };

const PATHS: Record<SectorKey, string> = {
  /* Parcel with a building line — real-world property, not a stock ticker. */
  REAL_ESTATE:
    'M2 13.5 8 3.2l6 10.3M4.6 12.8V8.2h2.9v4.6M9.4 12.8V6.4h2.9v6.4M1.6 13.5h12.8',
  /* Two leaves on a stem — the productive activity, not a spreadsheet. */
  AGRICULTURE:
    'M8 14.4V6.6M8 9.9C8 7.2 9.9 5.2 12.6 5c.3 2.8-1.6 4.9-4.6 4.9M8 11.7c0-2.4-1.7-4.2-4.1-4.4-.3 2.5 1.4 4.4 4.1 4.4M3.4 14.4h9.2',
  /* Herd head — a living productive asset. */
  LIVESTOCK:
    'M5.4 4.2c-1.5.5-2.3 1.8-2.3 3.3 0 1.9 1.2 2.9 1.2 4.4 0 1.4 1.1 2.5 3.7 2.5s3.7-1.1 3.7-2.5c0-1.5 1.2-2.5 1.2-4.4 0-1.5-.8-2.8-2.3-3.3M5.4 4.2 4 2.6M10.6 4.2 12 2.6',
};

export function SectorGlyph({ sector }: { sector: SectorKey }) {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d={PATHS[sector]} />
    </svg>
  );
}

/** Brand mark: a parcel with a furrow — the product is grounded in
 * real-world assets. */
export function BrandMark() {
  return (
    <span className="brand-mark" aria-hidden="true">
      <svg
        width="16"
        height="16"
        viewBox="0 0 16 16"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M2.2 12.6 8 2.6l5.8 10M2.2 12.6h11.6M4.4 12.6 8 6.4l3.6 6.2" />
      </svg>
    </span>
  );
}
