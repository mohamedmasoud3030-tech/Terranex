-- P3 beneficiary coherence.
-- Every cash-out payment identifies the counterparty it was paid to. This makes
-- later allocation auditable and prevents one supplier's prepayment from being
-- applied to another supplier's payable.

alter table public.unapplied_payments
  add column party_id uuid not null;

alter table public.unapplied_payments
  add constraint unapplied_payments_party_org_fkey
  foreign key (party_id,organization_id)
  references public.parties(id,organization_id) on delete restrict;

create index unapplied_payments_party_idx
  on public.unapplied_payments(organization_id,party_id,payment_date desc);
