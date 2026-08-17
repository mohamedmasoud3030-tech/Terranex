import { ForgotPasswordForm } from './forgot-password-form';

export const dynamic = 'force-dynamic';

type ForgotPasswordPageProps = {
  searchParams: Promise<{ recovery_error?: string }>;
};

export default async function ForgotPasswordPage({ searchParams }: ForgotPasswordPageProps) {
  const params = await searchParams;
  return <ForgotPasswordForm recoveryError={params.recovery_error === '1'} />;
}
