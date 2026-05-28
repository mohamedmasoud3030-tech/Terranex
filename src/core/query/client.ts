import { QueryClient } from '@tanstack/react-query';

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Data is considered fresh for 2 minutes
      staleTime: 2 * 60 * 1000,
      // Cache kept for 10 minutes
      gcTime: 10 * 60 * 1000,
      // Retry once on failure, not three times (ERP data rarely recovers on retry)
      retry: 1,
      retryDelay: 2000,
      // Refetch on window focus for financial data — important for multi-tab use
      refetchOnWindowFocus: true,
    },
    mutations: {
      // Surface errors — never swallow silently
      throwOnError: false,
    },
  },
});
