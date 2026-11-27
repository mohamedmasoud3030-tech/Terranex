import Link from 'next/link';
import { getActiveOrganization } from '@/features/organizations/context';
import { getParties, getParticipantUsage, getObligationUsage } from '@/features/parties/queries';
import { buildPartyDirectory, partyRolesAr, type PartyDirectoryRow } from '@/features/parties/directory';
import { formatMinorUnits } from '@/shared/money';
import { EmptyState, PageHeader, Section } from '@/shared/ui';

export const dynamic = 'force-dynamic';

const PARTY_TYPE_AR: Record<PartyDirectoryRow['partyType'], string> = {
  PERSON: 'شخص',
  ORGANIZATION: 'منظمة',
};

function PartyRow({ row }: { row: PartyDirectoryRow }) {
  const outstanding = Object.entries(row.outstandingByCurrency);
  return (
    <tr>
      <td data-label="الطرف">
        <strong>{row.legalName}</strong>
        <br />
        <small className="muted">{PARTY_TYPE_AR[row.partyType]}</small>
      </td>
      <td data-label="أدواره">{partyRolesAr(row)}</td>
      <td className="num" data-label="التزامات مفتوحة عليه">
        {outstanding.length > 0
          ? outstanding.map(([currency, total]) => (
              <div key={currency}>{formatMinorUnits(total, currency)}</div>
            ))
          : <span className="muted">—</span>}
      </td>
    </tr>
  );
}

/**
 * Party directory: every person or organization the company deals with, with
 * each one's roles across projects. Read-only by design — a party is created
 * inside the flow that needs it (investor, supplier, customer), never here.
 */
export default async function PartiesPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="دليل الأطراف يعرض من تتعامل معهم منظمتك، فأنشئ المنظمة أولًا."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }

  const [parties, participants, obligations] = await Promise.all([
    getParties(org.id),
    getParticipantUsage(org.id),
    getObligationUsage(org.id),
  ]);
  const rows = buildPartyDirectory(parties, participants, obligations);

  return (
    <>
      <PageHeader
        eyebrow={org.name}
        title="دليل الأطراف"
        description="كل شخص أو منظمة تتعامل معها، ودور كل منهم: مستثمر أو مورد أو غيره. تُضاف الأطراف من شاشاتها: المستثمر من صفحة المستثمرين، والمورد من المشتريات، والعميل من الفواتير."
      />
      <Section title={`الأطراف المسجلون (${rows.length})`}>
        {rows.length === 0 ? (
          <EmptyState
            title="لا أطراف بعد"
            description="أول طرف يظهر هنا بعد أن تضيف مستثمرًا أو موردًا أو عميلًا من الشاشة المناسبة."
          />
        ) : (
          <table className="table-stackable">
            <thead>
              <tr>
                <th>الطرف</th>
                <th>أدواره</th>
                <th>التزامات مفتوحة عليه</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => <PartyRow key={row.id} row={row} />)}
            </tbody>
          </table>
        )}
      </Section>
    </>
  );
}
