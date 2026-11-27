import { notFound } from 'next/navigation';

/** Target of the proxy's 404 rewrite for malformed project ids; renders the branded not-found card. */
export default function NotFoundTarget(): never {
  notFound();
}
