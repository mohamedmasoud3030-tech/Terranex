import { beforeEach, describe, expect, it } from 'vitest';
import { guardAssetDeletion, guardDocumentDeletion, guardPartnerDeletion, guardProjectDeletion } from './deletionGuards';

function setItems(key: string, items: unknown[]) {
  localStorage.setItem(key, JSON.stringify(items));
}

describe('deletion guards', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('blocks linked projects', () => {
    setItems('terranex.transactions.v2', [{ id: 'tx-1', project_id: 'project-1' }]);

    expect(guardProjectDeletion('project-1').canDelete).toBe(false);
  });

  it('blocks linked partners', () => {
    setItems('terranex.obligations.v1', [{ id: 'obl-1', partner_id: 'partner-1' }]);

    expect(guardPartnerDeletion('partner-1').canDelete).toBe(false);
  });

  it('blocks linked assets', () => {
    setItems('terranex.documents.v1', [{ id: 'doc-1', asset_id: 'asset-1' }]);

    expect(guardAssetDeletion('asset-1').canDelete).toBe(false);
  });

  it('blocks linked documents', () => {
    setItems('terranex.operationalEvents.v1', [{ id: 'event-1', document_id: 'document-1' }]);

    expect(guardDocumentDeletion('document-1').canDelete).toBe(false);
  });

  it('allows deletion when no blocking links exist', () => {
    expect(guardProjectDeletion('project-1').canDelete).toBe(true);
    expect(guardPartnerDeletion('partner-1').canDelete).toBe(true);
    expect(guardAssetDeletion('asset-1').canDelete).toBe(true);
    expect(guardDocumentDeletion('document-1').canDelete).toBe(true);
  });
});
