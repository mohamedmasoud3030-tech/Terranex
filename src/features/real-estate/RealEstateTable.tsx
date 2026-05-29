import { useMemo, useState } from 'react';
import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  type SortingState,
  useReactTable,
} from '@tanstack/react-table';
import { ChevronDown, ChevronUp, ChevronsUpDown, FileText } from 'lucide-react';
import { Badge } from '../../components/ui/Badge';
import { MoneyValue } from '../../components/ui/MoneyValue';
import { useI18n } from '../../core/i18n';
import { cn } from '../../core/lib/cn';
import { formatMoney } from '../../core/lib/format';
import type { AssetRowStatus, AssetRowType, AssetRowVM, StatusTone } from '../../core/types/ui';

const typeLabelAr: Record<AssetRowType, string> = {
  land: 'أرض',
  building: 'مبنى',
  mixed_property: 'عقار متعدد الاستخدامات',
  farm: 'مزرعة',
  equipment: 'معدات',
  crop: 'محصول',
  herd: 'قطيع',
  animal_group: 'مجموعة حيوانات',
  vehicle: 'مركبة',
  other: 'أخرى',
};

const statusLabelAr: Record<AssetRowStatus, string> = {
  owned: 'مملوك',
  under_development: 'قيد التطوير',
  for_sale: 'جاهز للبيع',
  sold: 'مُباع',
  leased_out: 'مؤجر',
  disposed: 'مستبعد',
};

const statusTone: Record<AssetRowStatus, StatusTone> = {
  owned: 'neutral',
  under_development: 'warning',
  for_sale: 'info',
  sold: 'positive',
  leased_out: 'info',
  disposed: 'negative',
};

const columnHelper = createColumnHelper<AssetRowVM>();

interface RealEstateTableProps {
  data: AssetRowVM[];
  onRowClick: (row: AssetRowVM) => void;
}

export function RealEstateTable({ data, onRowClick }: RealEstateTableProps) {
  const { locale } = useI18n();
  const [sorting, setSorting] = useState<SortingState>([]);

  const columns = useMemo(
    () => [
      columnHelper.accessor('name_ar', {
        id: 'asset',
        header: 'الأصل',
        cell: (info) => (
          <div>
            <p className="font-semibold text-foreground">{info.getValue()}</p>
            <p className="mt-0.5 text-xs leading-5 text-muted-foreground">{info.row.original.project_name_ar}</p>
          </div>
        ),
      }),
      columnHelper.accessor('type', {
        header: 'النوع',
        cell: (info) => <span className="text-sm">{typeLabelAr[info.getValue()]}</span>,
      }),
      columnHelper.accessor('location', {
        header: 'الموقع',
        cell: (info) => <span className="text-sm text-muted-foreground">{info.getValue() ?? '—'}</span>,
      }),
      columnHelper.accessor('status', {
        header: 'الحالة',
        cell: (info) => {
          const status = info.getValue();
          return <Badge tone={statusTone[status]}>{statusLabelAr[status]}</Badge>;
        },
      }),
      columnHelper.accessor('acquisition_cost_egp', {
        header: 'تكلفة الشراء',
        cell: (info) => <MoneyValue amount={info.getValue()} currency="EGP" size="sm" />,
        sortingFn: 'basic',
      }),
      columnHelper.accessor('development_cost_egp', {
        header: 'تكلفة التطوير',
        cell: (info) =>
          info.getValue() > 0 ? (
            <MoneyValue amount={info.getValue()} currency="EGP" size="sm" />
          ) : (
            <span className="text-sm text-muted-foreground">—</span>
          ),
        sortingFn: 'basic',
      }),
      columnHelper.accessor('current_valuation_egp', {
        header: 'التقييم الحالي',
        cell: (info) => <MoneyValue amount={info.getValue()} currency="EGP" size="sm" />,
        sortingFn: 'basic',
      }),
      columnHelper.accessor('profit_loss_egp', {
        header: 'الربح / الخسارة',
        cell: (info) => {
          const pnl = info.getValue();
          const pct = info.row.original.profit_loss_pct;
          const isPositive = pnl >= 0;
          return (
            <div className={cn('text-sm font-semibold tabular-nums', isPositive ? 'text-success' : 'text-danger')}>
              <span>{isPositive ? '+' : ''}{formatMoney(pnl, 'EGP', locale)}</span>
              <span className="ms-1.5 text-xs opacity-70">({isPositive ? '+' : ''}{pct.toFixed(1)}%)</span>
            </div>
          );
        },
        sortingFn: 'basic',
      }),
      columnHelper.accessor('document_count', {
        header: 'المستندات',
        cell: (info) => (
          <div className="flex items-center gap-1.5 text-sm text-muted-foreground">
            <FileText className="h-4 w-4" aria-hidden="true" />
            <span>{info.getValue()}</span>
          </div>
        ),
      }),
    ],
    [locale],
  );

  const table = useReactTable({
    data,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  });

  return (
    <div className="overflow-x-auto" role="region" aria-label="جدول محفظة الاستثمار العقاري">
      <table className="w-full min-w-[980px] border-separate border-spacing-0 text-sm">
        <thead>
          {table.getHeaderGroups().map((headerGroup) => (
            <tr key={headerGroup.id}>
              {headerGroup.headers.map((header) => {
                const sorted = header.column.getIsSorted();
                return (
                  <th
                    key={header.id}
                    className={cn(
                      'border-b border-border bg-muted/50 px-4 py-3 text-start text-xs font-bold text-muted-foreground',
                      header.column.getCanSort() && 'cursor-pointer select-none hover:text-foreground',
                    )}
                    onClick={header.column.getToggleSortingHandler()}
                    aria-sort={sorted === 'asc' ? 'ascending' : sorted === 'desc' ? 'descending' : 'none'}
                  >
                    <span className="inline-flex items-center gap-1">
                      {flexRender(header.column.columnDef.header, header.getContext())}
                      {header.column.getCanSort() && (
                        <span aria-hidden="true" className="opacity-50">
                          {sorted === 'asc' ? <ChevronUp className="h-3 w-3" /> : sorted === 'desc' ? <ChevronDown className="h-3 w-3" /> : <ChevronsUpDown className="h-3 w-3" />}
                        </span>
                      )}
                    </span>
                  </th>
                );
              })}
            </tr>
          ))}
        </thead>
        <tbody>
          {table.getRowModel().rows.map((row) => (
            <tr
              key={row.original.id}
              className="cursor-pointer align-top transition hover:bg-primary/5 focus-within:bg-primary/5"
              tabIndex={0}
              role="button"
              aria-label={`عرض تفاصيل ${row.original.name_ar}`}
              onClick={() => onRowClick(row.original)}
              onKeyDown={(event) => {
                if (event.key === 'Enter' || event.key === ' ') {
                  event.preventDefault();
                  onRowClick(row.original);
                }
              }}
            >
              {row.getVisibleCells().map((cell) => (
                <td key={cell.id} className="border-b border-border px-4 py-3">
                  {flexRender(cell.column.columnDef.cell, cell.getContext())}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="bg-muted/30">
            <td colSpan={4} className="border-t-2 border-border px-4 py-3 text-sm font-bold">
              الإجمالي ({data.length} أصول)
            </td>
            <td className="border-t-2 border-border px-4 py-3">
              <MoneyValue amount={data.reduce((total, row) => total + row.acquisition_cost_egp, 0)} currency="EGP" size="sm" />
            </td>
            <td className="border-t-2 border-border px-4 py-3">
              <MoneyValue amount={data.reduce((total, row) => total + row.development_cost_egp, 0)} currency="EGP" size="sm" />
            </td>
            <td className="border-t-2 border-border px-4 py-3">
              <MoneyValue amount={data.reduce((total, row) => total + row.current_valuation_egp, 0)} currency="EGP" size="sm" />
            </td>
            <td className="border-t-2 border-border px-4 py-3">
              {(() => {
                const total = data.reduce((acc, row) => acc + row.profit_loss_egp, 0);
                return (
                  <span className={cn('text-sm font-bold tabular-nums', total >= 0 ? 'text-success' : 'text-danger')}>
                    {total >= 0 ? '+' : ''}{formatMoney(total, 'EGP', locale)}
                  </span>
                );
              })()}
            </td>
            <td className="border-t-2 border-border px-4 py-3" />
          </tr>
        </tfoot>
      </table>
    </div>
  );
}
