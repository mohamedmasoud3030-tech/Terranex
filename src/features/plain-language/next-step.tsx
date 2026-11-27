import Link from 'next/link';

/**
 * A prominent "what to do next" prompt.
 *
 * The dense pages already compute what is missing; this component says it
 * out loud in plain words with one obvious action, so a first-time owner is
 * never left staring at a cockpit wondering where to click. Hash targets
 * use a plain anchor (same-page scroll); routes use Link.
 */
export function NextStep({
  title,
  description,
  href,
  actionLabel,
}: Readonly<{
  title: string;
  description: string;
  href: string;
  actionLabel: string;
}>) {
  const action = href.startsWith('#') ? (
    <a className="button" href={href}>
      {actionLabel}
    </a>
  ) : (
    <Link className="button" href={href}>
      {actionLabel}
    </Link>
  );
  return (
    <div className="next-step" role="note">
      <div className="next-step-text">
        <strong>{title}</strong>
        <p>{description}</p>
      </div>
      {action}
    </div>
  );
}
