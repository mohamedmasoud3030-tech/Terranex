import React from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from '@tanstack/react-router';
import { QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from './core/i18n';
import { queryClient } from './core/query';
import { createAppRouter } from './router';
import './styles.css';
import './core/lib/seedData'; // exposes window.seedTerranexDemo for dev

const router = createAppRouter(queryClient);

const rootElement = document.getElementById('root');
if (!rootElement) throw new Error('Root element #root not found.');

createRoot(rootElement).render(
  <React.StrictMode>
    {/*
      Provider order (outer → inner):
      1. I18nProvider   — locale + direction — affects every component
      2. QueryClientProvider — server state — affects data fetching
      3. RouterProvider  — routing — consumes queryClient via context
    */}
    <I18nProvider defaultLocale="ar">
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </I18nProvider>
  </React.StrictMode>,
);
