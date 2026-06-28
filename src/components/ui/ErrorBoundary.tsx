import { Component, type ReactNode, type ErrorInfo } from 'react';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
  scope?: string;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error?: Error;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    // eslint-disable-next-line no-console
    console.error(`[Terranex ErrorBoundary${this.props.scope ? `:${this.props.scope}` : ''}]`, error, errorInfo);
    this.props.onError?.(error, errorInfo);
  }

  private handleReset = () => {
    this.setState({ hasError: false, error: undefined });
  };

  private handleReload = () => {
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="flex min-h-[40vh] items-center justify-center p-6" dir="rtl">
          <div className="w-full max-w-lg rounded-2xl border border-danger/30 bg-danger/5 p-6 text-center shadow-sm">
            <div className="mb-3 text-2xl">⚠️</div>
            <h2 className="mb-2 text-lg font-bold text-danger">حدث خطأ غير متوقع</h2>
            <p className="mb-1 text-sm text-muted-foreground">
              تعذّر عرض هذا القسم. تم تسجيل الخطأ تلقائياً.
            </p>
            {this.state.error && (
              <details className="my-3 text-start">
                <summary className="cursor-pointer text-xs text-muted-foreground hover:text-foreground">
                  تفاصيل فنية
                </summary>
                <pre className="mt-2 max-h-32 overflow-auto rounded-lg bg-muted p-3 text-[11px] text-muted-foreground ltr:text-left rtl:text-right" dir="ltr">
                  {this.state.error.message}
                  {this.state.error.stack ? `\n\n${this.state.error.stack.slice(0, 800)}` : ''}
                </pre>
              </details>
            )}
            <div className="mt-4 flex justify-center gap-3">
              <button
                onClick={this.handleReset}
                className="rounded-xl border border-border bg-card px-4 py-2 text-sm font-medium hover:bg-muted transition"
              >
                إعادة المحاولة
              </button>
              <button
                onClick={this.handleReload}
                className="rounded-xl bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:opacity-90 transition"
              >
                إعادة تحميل الصفحة
              </button>
            </div>
            <p className="mt-3 text-[11px] text-muted-foreground">
              Terranex — نظام التشغيل الاستثماري • {this.props.scope ?? 'global'}
            </p>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

/**
 * Feature-level error boundary wrapper — use at the top of each feature page.
 */
export function FeatureErrorBoundary({ children, feature }: { children: ReactNode; feature: string }) {
  return <ErrorBoundary scope={feature}>{children}</ErrorBoundary>;
}
