'use client';


/** Light/dark switch. The initial theme is set before paint by the inline
 * script in the root layout; this control only flips and remembers it. */
export function ThemeToggle() {
  // No React state: the DOM attribute is the single source of truth and CSS
  // picks the icon and label from it, so there is nothing to sync in an effect.
  function flip() {
    const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem('tx-theme', next);
    } catch {
      /* private mode: the choice just will not persist */
    }
  }
  return (
    <button type="button" className="theme-toggle" onClick={flip}>
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" aria-hidden="true">
        <path className="theme-icon-moon" d="M13.2 9.6A5.6 5.6 0 0 1 6.4 2.8a5.6 5.6 0 1 0 6.8 6.8z" />
        <path className="theme-icon-sun" d="M8 1.5v1.6M8 12.9v1.6M1.5 8h1.6M12.9 8h1.6M3.4 3.4l1.1 1.1M11.5 11.5l1.1 1.1M3.4 12.6l1.1-1.1M11.5 4.5l1.1-1.1M8 5.2a2.8 2.8 0 1 0 0 5.6 2.8 2.8 0 0 0 0-5.6z" />
      </svg>
      <span className="theme-label-to-dark">الوضع الداكن</span>
      <span className="theme-label-to-light">الوضع الفاتح</span>
    </button>
  );
}
