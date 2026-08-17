export type PostedSourceBatchRef = {
  id: string;
  source_id: string | null;
};

export type ReversalBatchRef = {
  reversal_of_batch_id: string | null;
};

/**
 * Returns business source ids whose posting batch has not been reversed.
 *
 * A reversal points to journal_batches.id, never journal_batches.source_id.
 * Keeping this mapping explicit prevents a reversed business event from being
 * mistaken for an active posting merely because the two UUID domains differ.
 */
export function activePostedSourceIds(
  batches: readonly PostedSourceBatchRef[],
  reversals: readonly ReversalBatchRef[],
): Set<string> {
  const reversedBatchIds = new Set(
    reversals.flatMap((row) => row.reversal_of_batch_id ? [row.reversal_of_batch_id] : []),
  );
  const activeSourceIds = new Set<string>();

  for (const batch of batches) {
    if (batch.source_id && !reversedBatchIds.has(batch.id)) {
      activeSourceIds.add(batch.source_id);
    }
  }

  return activeSourceIds;
}
