import { JOURNEY_STEPS } from './copy';

/**
 * The first-run journey indicator: organization → first project → record.
 *
 * Shown on each page of the onboarding path so a first-time owner always
 * knows where they are and what comes after. Presentation only; the flow
 * itself (forms, redirects) is unchanged.
 */
export function JourneySteps({ current }: { current: 1 | 2 | 3 }) {
  return (
    <nav className="journey-steps" aria-label="خطوات البدء">
      {JOURNEY_STEPS.map((step, index) => {
        const position = index + 1;
        const state = position < current ? 'done' : position === current ? 'current' : 'todo';
        return (
          <div
            key={step.id}
            className={`journey-step journey-step-${state}`}
            aria-current={position === current ? 'step' : undefined}
          >
            <span className="journey-step-num" aria-hidden="true">
              {position < current ? '✓' : position}
            </span>
            <div className="journey-step-body">
              <strong>{step.title}</strong>
              <p className="muted">{step.plain}</p>
            </div>
          </div>
        );
      })}
    </nav>
  );
}
