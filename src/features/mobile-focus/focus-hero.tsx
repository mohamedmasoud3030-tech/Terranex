import Link from 'next/link';

export type FocusNumber = Readonly<{
  label: string;
  value: string | number;
}>;

/**
 * FocusHero: the phone-sized home in the spirit of a simple records app —
 * a greeting, three numbers, and one clear button. Rendered only on small
 * screens (CSS hides it on larger ones, where the executive dashboard keeps
 * its full density). The three numbers answer "what do I have" and the one
 * button answers "what do I do now"; everything else opens on demand below.
 */
export function FocusHero({
  orgName,
  numbers,
  action,
}: Readonly<{
  orgName: string;
  numbers: readonly FocusNumber[];
  action: Readonly<{ href: string; label: string }>;
}>) {
  return (
    <section className="focus-hero" aria-label="ملخص سريع">
      <p className="focus-hello">{orgName}</p>
      <div className="focus-numbers">
        {numbers.map((item) => (
          <div className="focus-number" key={item.label}>
            <strong>{item.value}</strong>
            <span className="muted">{item.label}</span>
          </div>
        ))}
      </div>
      <Link className="button hero-cta" href={action.href}>
        {action.label}
      </Link>
    </section>
  );
}
