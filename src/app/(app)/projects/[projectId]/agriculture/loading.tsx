import { PageSkeleton } from '@/shared/ui';

/** Renders a `role="status"` live region (inside PageSkeleton) while agriculture data loads. */
export default function Loading() {
  return <PageSkeleton blocks={4} withNav />;
}
