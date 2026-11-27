import { PAGE_INTROS, type PageIntroKey } from './copy';

/**
 * The one-line plain explanation at the top of a major page.
 *
 * The page's own header keeps its precise operational description; this
 * strip answers the first-timer's only question — "what is this page for?" —
 * in everyday words before any dense content. Pure presentation: the copy
 * lives in copy.ts so the sentence is never re-authored inline.
 */
export function PlainIntro({ page }: { page: PageIntroKey }) {
  const text = PAGE_INTROS[page];
  if (!text) return null;
  return (
    <p className="plain-intro" role="note">
      <span className="plain-intro-marker" aria-hidden="true">
        ℹ
      </span>
      <span>{text}</span>
    </p>
  );
}
