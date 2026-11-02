import Icon from '@global/Icon';

export const displayName = 'Communication Row';
export const shortDescription = 'Single row in the communications list';

export default function CommunicationRow({
  processo = '',
  tribunal = '',
  resumo = '',
  data = '',
  duplicidade = false,
}) {
  return (
    <div className="border-b border-border px-5 py-4 flex flex-col gap-1.5 font-body">
      <div className="flex items-start justify-between gap-4">
        <div className="flex flex-col gap-0.5">
          {processo && (
            <span className="text-xs text-muted-foreground font-mono">
              {processo}
            </span>
          )}
          <p className="text-sm text-foreground leading-relaxed">{resumo}</p>
        </div>
        <div className="flex-shrink-0 flex flex-col items-end gap-1">
          <span className="text-xs text-muted-foreground">{data}</span>
          <a className="text-xs text-accent underline">{t('abrir comunicação')}</a>
        </div>
      </div>
      {duplicidade && (
        <div className="flex items-center gap-1.5 text-xs text-warning mt-1">
          <Icon i="alert-triangle" size={12} />
          <span>{t('Possível duplicidade — aguardando verificação')}</span>
        </div>
      )}
    </div>
  );
}
