// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import {
  JOURNEY_STEPS,
  JARGON_BLOCKLIST,
  NEXT_STEP_COPY,
  ONBOARDING_COPY,
  PAGE_INTROS,
  PROJECT_FORM_COPY,
  SECTOR_PLAIN,
} from '@/features/plain-language/copy';
import { PlainIntro } from '@/features/plain-language/plain-intro';
import { JourneySteps } from '@/features/plain-language/journey-steps';
import { NextStep } from '@/features/plain-language/next-step';

/**
 * The plain-language layer contract.
 *
 * Stream A (simplification) gives a first-time owner who is not an
 * accountant: a guided step-by-step start, a one-line plain explanation on
 * every major page, friendlier labels, and a visible "what to do next". The
 * layer fails quietly the day someone adds a page key without its sentence
 * or lets jargon leak back into the plain register, so both are guarded.
 */

const plainSentences: Array<[string, string]> = [
  ...Object.entries(PAGE_INTROS).map(([key, text]) => [`PAGE_INTROS.${key}`, text] as [string, string]),
  ...JOURNEY_STEPS.map((step) => [`JOURNEY_STEPS.${step.id}`, step.plain] as [string, string]),
  ...JOURNEY_STEPS.map((step) => [`JOURNEY_STEPS.${step.id}.title`, step.title] as [string, string]),
  ...Object.entries(ONBOARDING_COPY).map(([key, text]) => [`ONBOARDING_COPY.${key}`, text] as [string, string]),
  ...Object.entries(PROJECT_FORM_COPY).map(([key, text]) => [`PROJECT_FORM_COPY.${key}`, text] as [string, string]),
  ...Object.entries(SECTOR_PLAIN).map(([key, text]) => [`SECTOR_PLAIN.${key}`, text] as [string, string]),
  ...Object.values(NEXT_STEP_COPY).flatMap((item) =>
    Object.values(item).map((text) => ['NEXT_STEP_COPY', text] as [string, string]),
  ),
];

describe('plain-language copy register', () => {
  it('covers every major page exactly once', () => {
    const expected = [
      'home',
      'projects',
      'projects-new',
      'portfolios',
      'portfolios-new',
      'assets',
      'documents',
      'inventory',
      'invoices',
      'journal',
      'transactions',
      'vat',
      'reports',
      'settings',
      'intake',
      'project-intake',
      'project-agriculture',
      'project-livestock',
    ];
    expect(Object.keys(PAGE_INTROS).sort()).toEqual(expected.sort());
  });

  it('keeps the journey at exactly three named steps in order', () => {
    expect(JOURNEY_STEPS.map((step) => step.id)).toEqual(['organization', 'project', 'record']);
  });

  it('keeps every plain sentence free of accounting jargon and internal codes', () => {
    for (const [where, text] of plainSentences) {
      for (const jargon of JARGON_BLOCKLIST) {
        expect(text, `${where} contains jargon «${jargon}»`).not.toContain(jargon);
      }
    }
  });

  it('keeps page intros to one short line', () => {
    for (const [key, text] of Object.entries(PAGE_INTROS)) {
      expect(text.length, `PAGE_INTROS.${key} is too long for a one-liner`).toBeLessThanOrEqual(110);
      expect(text, `PAGE_INTROS.${key} must be a single sentence`).not.toMatch(/[.!؟?].+\S/);
    }
  });

  it('explains all three sectors in plain words', () => {
    for (const sector of ['REAL_ESTATE', 'AGRICULTURE', 'LIVESTOCK']) {
      expect(SECTOR_PLAIN[sector]?.length ?? 0).toBeGreaterThan(20);
    }
  });
});

describe('PlainIntro', () => {
  afterEach(() => cleanup());

  it('renders the page sentence as a note', () => {
    render(<PlainIntro page="home" />);
    const note = screen.getByRole('note');
    expect(note.textContent).toContain(PAGE_INTROS.home);
  });

  it('renders nothing for an unknown key', () => {
    const { container } = render(<PlainIntro page={'nope' as never} />);
    expect(container.firstChild).toBeNull();
  });
});

describe('JourneySteps', () => {
  afterEach(() => cleanup());

  it('marks only the current step', () => {
    render(<JourneySteps current={2} />);
    const current = document.querySelectorAll('[aria-current="step"]');
    expect(current).toHaveLength(1);
    expect(current[0]?.textContent).toContain(JOURNEY_STEPS[1].title);
  });

  it('exposes the journey as named navigation', () => {
    render(<JourneySteps current={1} />);
    expect(screen.getByRole('navigation', { name: 'خطوات البدء' })).toBeDefined();
  });
});

describe('NextStep', () => {
  afterEach(() => cleanup());

  it('renders a route action through Link', () => {
    render(
      <NextStep
        title={NEXT_STEP_COPY.createFirstProject.title}
        description={NEXT_STEP_COPY.createFirstProject.description}
        href="/projects/new"
        actionLabel={NEXT_STEP_COPY.createFirstProject.actionLabel}
      />,
    );
    const action = screen.getByRole('link', { name: NEXT_STEP_COPY.createFirstProject.actionLabel });
    expect(action.getAttribute('href')).toBe('/projects/new');
  });

  it('renders an in-page target as a plain anchor', () => {
    render(<NextStep title="ت" description="د" href="#DS03_PARTIES" actionLabel="اذهب" />);
    const action = screen.getByRole('link', { name: 'اذهب' });
    expect(action.getAttribute('href')).toBe('#DS03_PARTIES');
  });
});

describe('plain layer is wired into the real pages', () => {
  const pagesUsingIntro = execSync(
    "grep -rl \"PlainIntro page=\" 'src/app' --include='page.tsx' --include='project-form.tsx'",
    { encoding: 'utf8' },
  )
    .trim()
    .split('\n')
    .filter(Boolean);

  it('every major page mounts its PlainIntro', () => {
    const required = [
      'src/app/(app)/page.tsx',
      'src/app/(app)/projects/page.tsx',
      'src/app/(app)/portfolios/page.tsx',
      'src/app/(app)/assets/page.tsx',
      'src/app/(app)/documents/page.tsx',
      'src/app/(app)/inventory/page.tsx',
      'src/app/(app)/invoices/page.tsx',
      'src/app/(app)/journal/page.tsx',
      'src/app/(app)/transactions/page.tsx',
      'src/app/(app)/vat/page.tsx',
      'src/app/(app)/reports/page.tsx',
      'src/app/(app)/settings/page.tsx',
      'src/app/(app)/intake/page.tsx',
      'src/app/(app)/projects/[projectId]/intake/page.tsx',
      'src/app/(app)/projects/[projectId]/agriculture/page.tsx',
      'src/app/(app)/projects/[projectId]/livestock/page.tsx',
    ];
    for (const page of required) {
      expect(pagesUsingIntro, `${page} lost its PlainIntro`).toContain(page);
    }
  });

  it('every mounted key exists in the register', () => {
    for (const page of pagesUsingIntro) {
      const source = readFileSync(page, 'utf8');
      for (const match of source.matchAll(/PlainIntro page="([^"]+)"/g)) {
        expect(PAGE_INTROS, `${page} uses unknown key ${match[1]}`).toHaveProperty(match[1]);
      }
    }
  });

  it('keeps the guided journey on the onboarding path pages', () => {
    const withJourney = [
      'src/app/(app)/onboarding/page.tsx',
      'src/app/(app)/intake/page.tsx',
      'src/app/(app)/projects/new/project-form.tsx',
      'src/app/(app)/projects/[projectId]/intake/page.tsx',
    ];
    for (const page of withJourney) {
      expect(readFileSync(page, 'utf8'), `${page} lost its JourneySteps`).toContain('JourneySteps');
    }
  });

  it('keeps the plain CSS classes defined once', () => {
    const css = readFileSync('src/app/globals.css', 'utf8');
    for (const cls of ['.plain-intro', '.journey-steps', '.journey-step', '.next-step']) {
      expect(css).toContain(cls);
    }
  });
});
