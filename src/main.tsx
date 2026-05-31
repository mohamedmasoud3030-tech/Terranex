import React from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from '@tanstack/react-router';
import { QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from './core/i18n';
import { ThemeProvider } from './core/theme';
import { queryClient } from './core/query';
import { createAppRouter } from './router';
import { runAppStorageMigrations } from './core/storage/migrations';
import './styles.css';

runAppStorageMigrations();

const router = createAppRouter(queryClient);

const rootElement = document.getElementById('root');
if (!rootElement) throw new Error('Root element #root not found.');

createRoot(rootElement).render(
  <React.StrictMode>
    <I18nProvider defaultLocale="ar">
      <ThemeProvider>
        <QueryClientProvider client={queryClient}>
          <RouterProvider router={router} />
        </QueryClientProvider>
      </ThemeProvider>
    </I18nProvider>
  </React.StrictMode>,
);
