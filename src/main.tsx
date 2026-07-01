import React from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from '@tanstack/react-router';
import { QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from './core/i18n';
import { ThemeProvider } from './core/theme';
import { queryClient } from './core/query';
import { createAppRouter } from './router';
import { AuthProvider } from './core/auth/AuthProvider';
import { registerServiceWorker } from './registerServiceWorker';
import { ErrorBoundary } from './components/ui/ErrorBoundary';
import './styles.css';

registerServiceWorker();

const router = createAppRouter(queryClient);

const rootElement = document.getElementById('root');
if (!rootElement) throw new Error('Root element #root not found.');

createRoot(rootElement).render(
  <React.StrictMode>
    <ErrorBoundary scope="root">
      <I18nProvider defaultLocale="ar">
        <ThemeProvider>
          <QueryClientProvider client={queryClient}>
            <AuthProvider>
              <ErrorBoundary scope="router">
                <RouterProvider router={router} />
              </ErrorBoundary>
            </AuthProvider>
          </QueryClientProvider>
        </ThemeProvider>
      </I18nProvider>
    </ErrorBoundary>
  </React.StrictMode>,
);
