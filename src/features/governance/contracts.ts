export interface GovernanceHandoff {
  destination: 'portfolio' | 'operations' | 'finance';
  entityId: string;
  relationship: string;
}
