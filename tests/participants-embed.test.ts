import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('project participants query', () => {
  it('names the foreign key when embedding parties (two FKs exist, PostgREST rejects an ambiguous embed)', () => {
    const src = readFileSync('src/features/funding/queries.ts', 'utf8');
    expect(src).toContain('parties!project_participants_party_id_fkey(legal_name)');
    expect(src).not.toMatch(/project_participants[^\n]*\n?[^\n]*,parties\(legal_name\)/);
  });
});
