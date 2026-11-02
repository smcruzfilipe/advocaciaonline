export const displayName = 'Email de Notificação de Comunicação';
export const screenSize = 'desktop';

export default function EmailNotificacaoComunicacaoScreen() {
  return (
    <div className="bg-muted p-8 font-body" style={{ minHeight: '600px' }}>
      <div className="max-w-2xl mx-auto bg-background">
        {/* Header */}
        <div className="bg-foreground px-8 py-6">
          <h1 className="text-2xl font-semibold font-headings text-primary-foreground">{t('Central de Processos')}</h1>
          <p className="text-xs text-primary-foreground opacity-75 mt-1">{t('Notificação de comunicação judicial')}</p>
        </div>

        {/* Alert banner */}
        <div className="bg-warning-bg border-l-4 border-warning px-8 py-4">
          <p className="text-sm font-medium text-warning">{t('Nova publicação coletada')}</p>
        </div>

        {/* Content */}
        <div className="px-8 py-8 flex flex-col gap-6">
          {/* Greeting */}
          <div>
            <p className="text-base text-foreground">{t('Olá, Dr. Rafael,')}</p>
            <p className="text-sm text-muted-foreground mt-2">{t('Uma nova comunicação judicial foi coletada para seus monitoramentos.')}</p>
          </div>

          {/* Communication details */}
          <div className="border border-border p-5 flex flex-col gap-3 bg-input">
            <div className="flex items-start justify-between gap-4">
              <div className="flex flex-col gap-1">
                <p className="text-xs text-muted-foreground uppercase tracking-wide">{t('Tribunal')}</p>
                <p className="text-sm font-medium text-foreground">{t('TJMG — Tribunal de Justiça de Minas Gerais')}</p>
              </div>
              <div className="text-xs text-muted-foreground">{t('09/07/2025')}</div>
            </div>

            <div className="border-t border-border pt-3">
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Processo')}</p>
              <p className="text-sm font-mono text-foreground">{t('0012345-67.2023.8.13.0024')}</p>
            </div>

            <div className="border-t border-border pt-3">
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Conteúdo')}</p>
              <p className="text-sm text-foreground leading-relaxed">{t('Intimação para manifestação no prazo de 15 dias, nos termos do art. 351 do CPC. Processo n.º 0012345-67.2023.8.13.0024 — 2ª Vara Cível da Comarca de Belo Horizonte.')}</p>
            </div>

            <div className="border-t border-border pt-3">
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Monitoramento')}</p>
              <p className="text-sm text-foreground">{t('Advogado: Rafael Mendonça Souza — OAB/MG 123.456')}</p>
            </div>
          </div>

          {/* CTA */}
          <div className="flex flex-col gap-3">
            <p className="text-sm text-muted-foreground">{t('Para visualizar esta comunicação, clique no botão abaixo:')}</p>
            <div className="py-3">
              <button className="bg-primary text-primary-foreground px-6 py-3 text-sm font-medium inline-block">
                {t('Ver comunicação completa')}
              </button>
            </div>
            <p className="text-xs text-muted-foreground">{t('Ou acesse a plataforma em:')}</p>
            <p className="text-xs text-accent break-all font-mono">{t('https://centradeprocessos.app')}</p>
          </div>

          {/* Summary */}
          <div className="bg-secondary border border-border p-4 flex flex-col gap-2 text-xs text-muted-foreground">
            <p className="font-medium text-foreground">{t('Resumo do período')}</p>
            <p>{t('Comunicações hoje: 14')}</p>
            <p>{t('Processos distintos: 9')}</p>
          </div>

          {/* Footer notes */}
          <div className="border-t border-border pt-6 flex flex-col gap-3 text-xs text-muted-foreground leading-relaxed">
            <p>{t('Você está recebendo este e-mail porque tem monitoramentos ativos configurados na plataforma Central de Processos.')}</p>
            <p>{t('Para gerenciar suas notificações ou desativar monitoramentos, acesse as configurações da sua conta.')}</p>
            <p>{t('Este é um e-mail de notificação automática. Não responda a este endereço.')}</p>
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
