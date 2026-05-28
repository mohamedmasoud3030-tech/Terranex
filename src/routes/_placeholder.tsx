import { type ComponentType } from 'react';
import { useI18n } from '../core/i18n';
import { PageHeader } from '../components/layout/PageHeader';
import { EmptyState } from '../components/ui/States';
import type { TranslationKey } from '../core/i18n/ar';

interface PlaceholderPageProps {
  titleKey: TranslationKey;
  descriptionKey: TranslationKey;
  icon?: ComponentType<{ className?: string }>;
}

export function PlaceholderPage({ titleKey, descriptionKey, icon }: PlaceholderPageProps) {
  const { t } = useI18n();
  return (
    <>
      <PageHeader title={t(titleKey)} description={t(descriptionKey)} />
      <EmptyState
        title={t('state_empty_title')}
        description={t('state_empty_description')}
        icon={icon}
        action={{ label: t('action_add_record'), onClick: () => {} }}
      />
    </>
  );
}
