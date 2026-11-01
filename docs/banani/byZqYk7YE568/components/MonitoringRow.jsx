export const displayName = 'Monitoring Row';
export const shortDescription = 'Single row in monitored parties or processes list';

import Badge from '@components/Badge';

export default function MonitoringRow({
  name = '',
  tribunals = 'Todos os tribunais',
  status = 'ativo',
  detail = true,
}) {
  return (
    <div className="border-b border-border px-5 py-3.5 flex items-center justify-between gap-4 font-body">
      <div className="flex flex-col gap-0.5 flex-1 min-w-0">
        <span className="text-sm text-foreground font-medium truncate">{name}</span>
        <span className="text-xs text-muted-foreground">{tribunals}</span>
      </div>
      <div className="flex items-center gap-3 flex-shrink-0">
        <Badge label={status === 'ativo' ? t('Ativo') : t('Inativo')} variant={status === 'ativo' ? 'active' : 'inactive'} />
        {detail && <a className="text-xs text-accent underline">{t('detalhe')}</a>}
      </div>
    </div>
  );
}
