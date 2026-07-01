import { useState, type FormEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormLabel, TextInput } from '../../components/ui/FormControls';
import { useAuth } from '../../core/auth/AuthProvider';

export function LoginPage() {
  const { signInWithPassword } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);
    const { error: signInError } = await signInWithPassword(email.trim(), password);
    setSubmitting(false);
    if (signInError) setError(signInError);
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/40 px-4">
      <div className="w-full max-w-sm rounded-2xl border border-border bg-card p-8 shadow-sm">
        <div className="mb-6 text-center">
          <h1 className="text-xl font-bold text-foreground">Terranex</h1>
          <p className="mt-1 text-sm text-muted-foreground">تسجيل الدخول للوصول إلى النظام</p>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <FormField>
            <FormLabel htmlFor="email">البريد الإلكتروني</FormLabel>
            <TextInput
              id="email"
              type="email"
              autoComplete="username"
              required
              dir="ltr"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </FormField>
          <FormField>
            <FormLabel htmlFor="password">كلمة المرور</FormLabel>
            <TextInput
              id="password"
              type="password"
              autoComplete="current-password"
              required
              dir="ltr"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </FormField>
          {error && <FormError>{error}</FormError>}
          <Button type="submit" className="w-full" disabled={submitting}>
            {submitting ? 'جارٍ الدخول...' : 'دخول'}
          </Button>
        </form>
      </div>
    </div>
  );
}
