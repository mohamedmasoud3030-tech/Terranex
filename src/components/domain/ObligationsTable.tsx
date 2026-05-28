import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  flexRender,
  createColumnHelper,
  type SortingState,
} from '@tanstack/react-table';
import { useState } from 'react';
import { ChevronDown, ChevronUp, ChevronsUpDown } from 'lucide-react';
import { Badge } from '../ui/Badge';
import { MoneyValue } from '../ui/MoneyValue';
import { useI18n } from '../../core/i18n';
import { formatDate } from '../../core/lib/date';
import type { ObligationRowVM } from '../../core/types/ui';
import type { StatusTone } from '../../core/types/ui';

const statusTone: Record<string, StatusTone> = {
  open: 'warning',
  partial: 'info',
  settled: 'positive',
  disputed: 'negative',
  written_off: 'neutral',
};

const columnHelper = createColumnHelper<ObligationRowVM>();

export function ObligationsTable({ data }: { data: ObligationRowVM[] }) {
  const { locale, t } = useI18n();
  const [sorting, setSorting] = useState<SortingState>([]);

  const columns = [
    columnHelper.accessor('date', {
      header: t('col_date'),
      cell: (info) => formatDate(info.getValue(), locale),
    }),
    columnHelper.accessor('direction', {
      header: t('col_type'),
      cell: (info) =>
        info.getValue() === 'receivable' ? t('direction_receivable') : t('direction_payable'),
    }),
    columnHelper.accessor(locale === 'ar' ? 'sector_ar' : 'sector_en', {
      id: 'sector',
      header: t('col_sector'),
    }),
    columnHelper.accessor(locale === 'ar' ? 'counterparty_ar' : 'counterparty_en', {
      id: 'counterparty',
      header: t('col_party'),
    }),
    columnHelper.accessor('amount_egp', {
      header: `${t('col_amount')} (EGP)`,
      cell: (info) => (
        <MoneyValue
          amount={info.row.original.amount}
          currency={info.row.original.currency}
          egpEquivalent={info.getValue()}
          showEquivalent={info.row.original.currency !== 'EGP'}
        />
      ),
    }),
    columnHelper.accessor('status', {
      header: t('col_status'),
      cell: (info) => {
        const s = info.getValue();
        const labelKey = `status_${s}` as const;
        return <Badge tone={statusTone[s] ?? 'neutral'}>{t(labelKey as Parameters<typeof t>[0])}</Badge>;
      },
    }),
    columnHelper.accessor('document_title', {
      header: t('col_document'),
      cell: (info) => info.getValue() ?? '—',
    }),
  ];

  const table = useReactTable({
    data,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  });

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[760px] border-separate border-spacing-0 text-sm">
        <thead>
          {table.getHeaderGroups().map((hg) => (
            <tr key={hg.id} className="text-muted-foreground">
              {hg.headers.map((header) => (
                <th
                  key={header.id}
                  className="border-b border-border px-3 py-3 text-start font-semibold cursor-pointer select-none hover:text-foreground"
                  onClick={header.column.getToggleSortingHandler()}
                  aria-sort={
                    header.column.getIsSorted() === 'asc'
                      ? 'ascending'
                      : header.column.getIsSorted() === 'desc'
                        ? 'descending'
                        : 'none'
                  }
                >
                  <span className="inline-flex items-center gap-1">
                    {flexRender(header.column.columnDef.header, header.getContext())}
                    {header.column.getCanSort() && (
                      <span aria-hidden="true">
                        {header.column.getIsSorted() === 'asc' ? (
                          <ChevronUp className="h-3 w-3" />
                        ) : header.column.getIsSorted() === 'desc' ? (
                          <ChevronDown className="h-3 w-3" />
                        ) : (
                          <ChevronsUpDown className="h-3 w-3 opacity-40" />
                        )}
                      </span>
                    )}
                  </span>
                </th>
              ))}
            </tr>
          ))}
        </thead>
        <tbody>
          {table.getRowModel().rows.map((row) => (
            <tr
              key={row.id}
              className="align-top transition hover:bg-muted/50"
            >
              {row.getVisibleCells().map((cell) => (
                <td key={cell.id} className="border-b border-border px-3 py-3">
                  {flexRender(cell.column.columnDef.cell, cell.getContext())}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
