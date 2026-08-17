import { describe, expect, it } from 'vitest';
import { activePostedSourceIds } from '../src/features/finance/reversal';

describe('finance reversal mapping', () => {
  it('matches reversal_of_batch_id to the journal batch id, not the business source id', () => {
    const active = activePostedSourceIds(
      [
        { id: 'batch-reversed', source_id: 'contribution-a' },
        { id: 'batch-active', source_id: 'contribution-b' },
      ],
      [{ reversal_of_batch_id: 'batch-reversed' }],
    );

    expect([...active]).toEqual(['contribution-b']);
    expect(active.has('contribution-a')).toBe(false);
  });

  it('ignores null source ids and null reversal references', () => {
    const active = activePostedSourceIds(
      [
        { id: 'batch-empty', source_id: null },
        { id: 'batch-active', source_id: 'contribution-c' },
      ],
      [{ reversal_of_batch_id: null }],
    );

    expect([...active]).toEqual(['contribution-c']);
  });
});
