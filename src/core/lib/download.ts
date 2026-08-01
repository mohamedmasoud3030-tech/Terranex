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
