export const displayName = 'Team Member Row';
export const shortDescription = 'Row in the team/credentials list';

import Badge from '@components/Badge';

export default function TeamMemberRow({
  name = 'Membro',
  email = '',
  credentialStatus = 'ativa',
  validity = '',
  groups = [],
}) {
  const statusVariant = {
    ativa: 'active',
    expirada: 'warning',
    revogada: 'error',
    pendente: 'info',
  }[credentialStatus] || 'muted';

  const statusLabel = {
    ativa: t('Ativa'),
    expirada: t('Expirada'),
    revogada: t('Revogada'),
    pendente: t('Convite pendente'),
  }[credentialStatus] || credentialStatus;

  return (
    <div className="border-b border-border px-5 py-3.5 flex items-center justify-between gap-4 font-body">
      <div className="flex flex-col gap-0.5 flex-1 min-w-0">
        <span className="text-sm font-medium text-foreground">{name}</span>
        <span className="text-xs text-muted-foreground">{email}</span>
        {groups.length > 0 && (
          <div className="flex gap-1 flex-wrap mt-1">
            {groups.map((g, i) => (
              <span key={i} className="bg-secondary text-secondary-foreground px-1.5 py-0.5 text-xs border border-border">{g}</span>
            ))}
          </div>
        )}
      </div>
      <div className="flex items-center gap-3 flex-shrink-0">
        <Badge label={statusLabel} variant={statusVariant} />
        {validity && <span className="text-xs text-muted-foreground">{validity}</span>}
        <a className="text-xs text-accent underline">{t('gerenciar')}</a>
      </div>
    </div>
  );
}
