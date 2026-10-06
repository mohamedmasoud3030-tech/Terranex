import { describe, expect, it } from 'vitest';
import {
  REAL_ESTATE_SECTION_IDS,
  AGRICULTURE_SECTION_IDS,
  LIVESTOCK_SECTION_IDS,
  assertSectionGroupingIsExact,
  sectionGroupsFor,
  sectionHref,
  sectionsFor,
  sectorLandingHref,
} from '@/features/workspace/nav';

/**
 * UI/UX upgrade guard.
 *
 * `sectionGroupsFor` is a *presentation* of the workspace navigation: it puts
 * a visible name over the same sections. It must never become a second source
 * of truth for what a sector can reach. These tests fail if a group ever
 * exposes a section the flat navigation withholds, drops one, duplicates one,
 * or points at a different route.
 */

const SECTORS = ['REAL_ESTATE', 'AGRICULTURE', 'LIVESTOCK'] as const;

const FLAT_IDS: Record<(typeof SECTORS)[number], ReadonlyArray<string>> = {
  REAL_ESTATE: REAL_ESTATE_SECTION_IDS,
  AGRICULTURE: AGRICULTURE_SECTION_IDS,
  LIVESTOCK: LIVESTOCK_SECTION_IDS,
};

describe('workspace navigation grouping', () => {
  it.each(SECTORS)('groups exactly the sections %s already exposes', (sector) => {
    const flat = sectionsFor(sector).map((section) => section.id);
    const grouped = sectionGroupsFor(sector).flatMap((group) =>
      group.sections.map((section) => section.id),
    );

    expect(grouped).toHaveLength(flat.length);
    expect([...grouped].sort()).toEqual([...flat].sort());
    expect(new Set(grouped).size).toBe(grouped.length);
  });

  it.each(SECTORS)('never widens %s beyond its declared section ids', (sector) => {
    const allowed = new Set(FLAT_IDS[sector]);
    const grouped = sectionGroupsFor(sector).flatMap((group) =>
      group.sections.map((section) => section.id),
    );
    for (const id of grouped) expect(allowed.has(id)).toBe(true);
  });

  it.each(SECTORS)('reuses the canonical section objects for %s', (sector) => {
    const canonical = sectionsFor(sector);
    for (const group of sectionGroupsFor(sector)) {
      for (const section of group.sections) {
        // Identity, not equality: proves the group did not re-declare a
        // section with a drifted label, description, or href.
        expect(canonical).toContain(section);
      }
    }
  });

  it.each(SECTORS)('renders no empty group for %s', (sector) => {
    for (const group of sectionGroupsFor(sector)) {
      expect(group.label.trim().length).toBeGreaterThan(0);
      expect(group.sections.length).toBeGreaterThan(0);
    }
  });

  it('names the first group after the sector', () => {
    const first = (sector: 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK') =>
      sectionGroupsFor(sector).find((group) => group.id === 'sector')?.label;
    expect(first('REAL_ESTATE')).toBe('الأصول العقارية');
    expect(first('AGRICULTURE')).toBe('مساحة الزراعة');
    expect(first('LIVESTOCK')).toBe('مساحة الثروة الحيوانية');
  });

  it.each(SECTORS)('passes the runtime exactness assertion for %s', (sector) => {
    expect(() => assertSectionGroupingIsExact(sector)).not.toThrow();
  });

  it('gives real estate the money group and withholds it from the other sectors', () => {
    const ids = (sector: 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK') =>
      sectionGroupsFor(sector).map((group) => group.id);
    expect(ids('REAL_ESTATE')).toEqual(['overview', 'sector', 'money', 'transparency', 'control']);
    expect(ids('AGRICULTURE')).toEqual(['sector', 'control']);
    expect(ids('LIVESTOCK')).toEqual(['sector', 'control']);
  });

  it('keeps livestock out of the real-estate money sections', () => {
    const livestock = sectionGroupsFor('LIVESTOCK').flatMap((group) =>
      group.sections.map((section) => section.id),
    );
    expect(livestock).not.toContain('capital');
    expect(livestock).not.toContain('revenue');
    expect(livestock).not.toContain('statements');
  });

  it('keeps sector landing routes unchanged', () => {
    expect(sectorLandingHref('REAL_ESTATE', 'p1')).toBe('/projects/p1/operations');
    expect(sectorLandingHref('AGRICULTURE', 'p1')).toBe('/projects/p1/agriculture');
    expect(sectorLandingHref('LIVESTOCK', 'p1')).toBe('/projects/p1/livestock');
  });

  it('keeps section hrefs unchanged', () => {
    expect(sectionHref('capital', 'p1')).toBe('/projects/p1/funding');
    expect(sectionHref('procurement', 'p1')).toBe('/projects/p1/procurement');
    expect(sectionHref('governance', 'p1')).toBe('/projects/p1/governance');
    expect(sectionHref('unknown-section' as never, 'p1')).toBe('/projects/p1');
  });
});
