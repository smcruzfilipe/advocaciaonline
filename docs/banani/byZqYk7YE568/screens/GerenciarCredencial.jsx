export const displayName = 'Gerenciar Credencial (modal)';
export const screenSize = 'desktop';

import AlertBanner from '@components/AlertBanner';
import Btn from '@components/Btn';
import Badge from '@components/Badge';
import Icon from '@global/Icon';

export default function GerenciarCredencialScreen() {
  return (
    <div className="bg-foreground bg-opacity-50 flex items-start justify-center py-16 px-4 font-body" style={{ minHeight: '600px', backgroundColor: 'rgba(0,0,0,0.5)' }}>
      <div className="bg-background border border-border w-full max-w-md flex flex-col gap-0">
        {/* Header */}
        <div className="border-b border-border px-5 py-4 flex items-center justify-between">
          <h2 className="text-base font-semibold font-headings text-foreground">{t('Gerenciar credencial')}</h2>
          <button className="text-muted-foreground"><Icon i="x" size={18} /></button>
        </div>

        <div className="px-5 py-5 flex flex-col gap-4">
          {/* Member info */}
          <div className="flex items-start justify-between">
            <div>
              <p className="text-sm font-medium text-foreground">{t('Carlos Eduardo Lima')}</p>
              <p className="text-xs text-muted-foreground">carloslima@email.com</p>
            </div>
            <Badge label={t('Expirada')} variant="warning" />
          </div>

          <div className="border-t border-border pt-4 flex flex-col gap-2">
            <p className="text-xs text-muted-foreground uppercase tracking-wide">{t('Validade atual')}</p>
            <p className="text-sm text-foreground">{t('Expirou em 01/07/2025')}</p>
          </div>

          {/* Validity change */}
          <div className="flex flex-col gap-2">
            <p className="text-sm font-medium text-foreground">{t('Alterar validade')}</p>
            <p className="text-xs text-muted-foreground">{t('A alteração passa a valer na próxima renovação — a credencial vigente não é interrompida.')}</p>
            <div className="flex gap-3">
              <div className="flex-1 flex items-center gap-2 border border-border px-3 py-2">
                <div className="w-4 h-4 rounded-full border border-border flex-shrink-0" />
                <span className="text-sm text-foreground">{t('Sem expiração')}</span>
              </div>
              <div className="flex-1 flex items-center gap-2 border border-foreground bg-secondary px-3 py-2">
                <div className="w-4 h-4 rounded-full border-2 border-foreground flex items-center justify-center flex-shrink-0">
                  <div className="w-2 h-2 rounded-full bg-foreground" />
                </div>
                <span className="text-sm text-foreground">{t('Dias:')}</span>
                <div className="border border-border px-2 py-0.5 text-sm bg-background w-16 text-foreground">30</div>
              </div>
            </div>
          </div>

          {/* Actions */}
          <div className="border-t border-border pt-4 flex flex-col gap-2">
            <Btn variant="secondary" icon="refresh-cw">{t('Renovar credencial')}</Btn>
            <Btn variant="secondary" icon="send">{t('Reemitir convite')}</Btn>
            <button className="text-sm text-error underline text-left mt-1">{t('Revogar credencial')}</button>
          </div>

          <AlertBanner variant="warning">
            {t('Uma credencial revogada não é reativada por renovação. Para reativar o acesso, será necessário emitir um novo convite.')}
          </AlertBanner>

          {/* Confirm revoke */}
          <div className="border border-error bg-error-bg p-4 flex flex-col gap-3">
            <p className="text-sm font-medium text-error">{t('Confirmar revogação')}</p>
            <p className="text-sm text-foreground">{t('Carlos Eduardo Lima perderá o acesso imediatamente. Esta ação não pode ser desfeita.')}</p>
            <div className="flex gap-2">
              <Btn variant="secondary" size="sm">{t('Cancelar')}</Btn>
              <Btn variant="danger" size="sm">{t('Revogar agora')}</Btn>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
