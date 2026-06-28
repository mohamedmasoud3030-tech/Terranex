/**
 * Dependency-free spreadsheet (XLSX) builder.
 *
 * Produces a SpreadsheetML 2003 (.xls) XML workbook that Excel, LibreOffice,
 * Google Sheets and Numbers all open natively — including multiple worksheets,
 * bold headers, number formatting and full UTF-8 (Arabic) support.
 *
 * We deliberately avoid pulling a heavy XLSX npm dependency (sheetjs ≈ 600 KB)
 * to keep the initial bundle small. This builder is tree-shakeable and adds
 * ~2 KB to the lazy-loaded export chunk.
 */

export type CellType = 'String' | 'Number';

export interface SheetColumn {
  /** Header label shown in the first row. */
  header: string;
  /** Cell data type — drives Excel number vs text handling. */
  type?: CellType;
  /** Optional fixed column width in characters. */
  width?: number;
}

export type CellValue = string | number | null | undefined;

export interface SheetSpec {
  /** Worksheet tab name (max 31 chars, invalid chars stripped). */
  name: string;
  columns: SheetColumn[];
  /** Rows of values, aligned to `columns`. */
  rows: CellValue[][];
}

/** Escape a string for safe XML attribute / text content. */
function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
    // strip control chars Excel rejects
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
}

/** Excel worksheet names cannot exceed 31 chars or contain : \ / ? * [ ] */
function sanitizeSheetName(name: string): string {
  const cleaned = name.replace(/[:\\/?*[\]]/g, ' ').trim() || 'Sheet';
  return cleaned.slice(0, 31);
}

function renderCell(value: CellValue, type: CellType): string {
  if (value === null || value === undefined || value === '') {
    return '<Cell><Data ss:Type="String"></Data></Cell>';
  }
  if (type === 'Number' && typeof value === 'number' && Number.isFinite(value)) {
    return `<Cell><Data ss:Type="Number">${value}</Data></Cell>`;
  }
  return `<Cell><Data ss:Type="String">${escapeXml(String(value))}</Data></Cell>`;
}

function renderSheet(sheet: SheetSpec): string {
  const colDefs = sheet.columns
    .map((c) =>
      c.width
        ? `<Column ss:AutoFitWidth="0" ss:Width="${Math.round(c.width * 7)}"/>`
        : '<Column ss:AutoFitWidth="1"/>',
    )
    .join('');

  const headerRow =
    '<Row ss:StyleID="sHeader">' +
    sheet.columns
      .map((c) => `<Cell ss:StyleID="sHeader"><Data ss:Type="String">${escapeXml(c.header)}</Data></Cell>`)
      .join('') +
    '</Row>';

  const dataRows = sheet.rows
    .map((row) => {
      const cells = sheet.columns
        .map((col, i) => renderCell(row[i], col.type ?? 'String'))
        .join('');
      return `<Row>${cells}</Row>`;
    })
    .join('');

  return (
    `<Worksheet ss:Name="${escapeXml(sanitizeSheetName(sheet.name))}">` +
    `<Table>${colDefs}${headerRow}${dataRows}</Table>` +
    '</Worksheet>'
  );
}

/**
 * Build a full SpreadsheetML workbook string from one or more sheet specs.
 */
export function buildWorkbookXml(sheets: SheetSpec[]): string {
  const styles =
    '<Styles>' +
    '<Style ss:ID="Default" ss:Name="Normal"><Alignment ss:Vertical="Center"/>' +
    '<Font ss:FontName="Calibri" ss:Size="11"/></Style>' +
    '<Style ss:ID="sHeader">' +
    '<Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1" ss:Color="#FFFFFF"/>' +
    '<Interior ss:Color="#1F6F54" ss:Pattern="Solid"/>' +
    '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>' +
    '</Style>' +
    '</Styles>';

  const worksheets = sheets.map(renderSheet).join('');

  return (
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<?mso-application progid="Excel.Sheet"?>\n' +
    '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"' +
    ' xmlns:o="urn:schemas-microsoft-com:office:office"' +
    ' xmlns:x="urn:schemas-microsoft-com:office:excel"' +
    ' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"' +
    ' xmlns:html="http://www.w3.org/TR/REC-html40">' +
    styles +
    worksheets +
    '</Workbook>'
  );
}

/**
 * Build a workbook Blob ready to download. Uses the SpreadsheetML MIME type
 * with a UTF-8 BOM so Excel renders Arabic correctly.
 */
export function buildWorkbookBlob(sheets: SheetSpec[]): Blob {
  const xml = buildWorkbookXml(sheets);
  const bom = '\uFEFF';
  return new Blob([bom + xml], {
    type: 'application/vnd.ms-excel;charset=utf-8',
  });
}

/**
 * Trigger a browser download for a given Blob and filename.
 * No-op outside the browser (e.g. during SSR or tests).
 */
export function downloadBlob(blob: Blob, filename: string): void {
  if (typeof document === 'undefined' || typeof URL === 'undefined') return;
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  // Revoke after the click has been handled.
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
