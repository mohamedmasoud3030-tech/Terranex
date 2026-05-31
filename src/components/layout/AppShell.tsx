import { type ReactNode } from 'react';
import { Sidebar } from './Sidebar';
import { TopBar } from './TopBar';

interface AppShellProps {
  children: ReactNode;
  activeHref?: string; // kept for backward compat but Sidebar now reads from router
}

export function AppShell({ children }: AppShellProps) {
  return (
    <div className="flex min-h-screen bg-background/70 text-foreground">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <TopBar />
        <main className="flex-1 px-4 py-5 sm:px-5 lg:px-8 lg:py-7">
          <div className="mx-auto w-full max-w-[1440px]">{children}</div>
        </main>
      </div>
    </div>
  );
}
