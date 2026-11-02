export const displayName = 'Email de Confirmação de Ação';
export const screenSize = 'desktop';

export default function EmailConfirmacaoScreen() {
  return (
    <div className="bg-muted p-8 font-body" style={{ minHeight: '600px' }}>
      <div className="max-w-2xl mx-auto bg-background">
        {/* Header */}
        <div className="bg-foreground px-8 py-6">
          <h1 className="text-2xl font-semibold font-headings text-primary-foreground">{t('Central de Processos')}</h1>
          <p className="text-xs text-primary-foreground opacity-75 mt-1">{t('Confirmação de ação')}</p>
        </div>

        {/* Alert banner */}
        <div className="bg-success-bg border-l-4 border-success px-8 py-4">
          <p className="text-sm font-medium text-success">{t('Operação concluída com sucesso')}</p>
        </div>

        {/* Content */}
        <div className="px-8 py-8 flex flex-col gap-6">
          {/* Greeting */}
          <div>
            <p className="text-base text-foreground">{t('Olá, Dr. Rafael,')}</p>
            <p className="text-sm text-muted-foreground mt-2">{t('Confirmamos que a seguinte ação foi executada em sua conta:')}</p>
          </div>

          {/* Action details */}
          <div className="border border-border p-5 flex flex-col gap-3 bg-success-bg">
            <p className="text-sm font-medium text-success">{t('Novo monitoramento adicionado')}</p>
            <div className="border-t border-success pt-3">
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Tipo')}</p>
              <p className="text-sm text-foreground">{t('Parte monitorada')}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Nome')}</p>
              <p className="text-sm text-foreground">{t('PETROBRAS — Petróleo Brasileiro S.A.')}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Tribunais')}</p>
              <p className="text-sm text-foreground">{t('TJSP, TJRJ, TRF-2')}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Data/Hora')}</p>
              <p className="text-sm text-foreground">{t('09 de julho de 2025 às 14h32 (Brasília)')}</p>
            </div>
          </div>

          {/* CTA */}
          <div className="flex flex-col gap-3">
            <p className="text-sm text-muted-foreground">{t('Para gerenciar seus monitoramentos, acesse:')}</p>
            <div className="py-3">
              <button className="bg-primary text-primary-foreground px-6 py-3 text-sm font-medium inline-block">
                {t('Ir para Monitoramentos')}
              </button>
            </div>
            <p className="text-xs text-muted-foreground">{t('Ou acesse diretamente:')}</p>
            <p className="text-xs text-accent break-all font-mono">{t('https://centradeprocessos.app/monitoramentos')}</p>
          </div>

          {/* Additional actions */}
          <div className="bg-secondary border border-border p-4">
            <p className="text-sm font-medium text-foreground mb-3">{t('O que fazer em seguida?')}</p>
            <ul className="text-sm text-foreground flex flex-col gap-2">
              <li className="flex gap-2">
                <span className="text-muted-foreground">•</span>
                <span>{t('Verifique se o monitoramento está correto nas configurações.')}</span>
              </li>
              <li className="flex gap-2">
                <span className="text-muted-foreground">•</span>
                <span>{t('As publicações começarão a ser coletadas a partir de agora.')}</span>
              </li>
              <li className="flex gap-2">
                <span className="text-muted-foreground">•</span>
                <span>{t('Você receberá notificações de novas comunicações conforme forem publicadas.')}</span>
              </li>
            </ul>
          </div>

          {/* Security note */}
          <div className="border-t border-border pt-6 flex flex-col gap-2 text-xs text-muted-foreground leading-relaxed">
            <p className="font-medium text-foreground">{t('Não reconhece esta ação?')}</p>
            <p>{t('Se você não solicitou esta ação ou identificar qualquer atividade suspeita, entre em contato conosco imediatamente através de ')}<a className="text-accent underline">{t('suporte@centradeprocessos.app')}</a></p>
          </div>
        </div>

        {/* Footer */}
        <div className="bg-secondary border-t border-border px-8 py-6 text-center text-xs text-muted-foreground">
          <p className="mb-2">{t('© 2025 Central de Processos. Todos os direitos reservados.')}</p>
          <div className="flex items-center justify-center gap-4">
            <a className="underline">{t('Termos de uso')}</a>
            <a className="underline">{t('Privacidade')}</a>
            <a className="underline">{t('Suporte')}</a>
          </div>
        </div>
      </div>
    </div>
  );
}
