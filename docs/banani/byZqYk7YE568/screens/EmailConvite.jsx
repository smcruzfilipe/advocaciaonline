export const displayName = 'Email de Convite';
export const screenSize = 'desktop';

export default function EmailConviteScreen() {
  return (
    <div className="bg-muted p-8 font-body" style={{ minHeight: '600px' }}>
      <div className="max-w-2xl mx-auto bg-background">
        {/* Header */}
        <div className="bg-foreground px-8 py-6">
          <h1 className="text-2xl font-semibold font-headings text-primary-foreground">{t('Central de Processos')}</h1>
        </div>

        {/* Content */}
        <div className="px-8 py-8 flex flex-col gap-6">
          {/* Greeting */}
          <div>
            <p className="text-base text-foreground">{t('Olá,')}</p>
            <p className="text-sm text-muted-foreground mt-2">{t('Você foi convidado para fazer parte da equipe ')}<span className="font-medium text-foreground">{t('Souza & Associados Advocacia')}</span>{t(' na plataforma Central de Processos.')}</p>
          </div>

          {/* Main message */}
          <div className="bg-secondary border border-border p-5 flex flex-col gap-3">
            <p className="text-sm text-foreground">{t('Convite enviado por:')}</p>
            <p className="text-base font-medium text-foreground">{t('Dr. Rafael Mendonça Souza')}</p>
            <p className="text-xs text-muted-foreground">{t('OAB/MG 123.456')}</p>
          </div>

          {/* CTA */}
          <div className="flex flex-col gap-3">
            <p className="text-sm text-muted-foreground">{t('Para aceitar este convite, clique no botão abaixo:')}</p>
            <div className="py-4">
              <button className="bg-primary text-primary-foreground px-6 py-3 text-sm font-medium inline-block">
                {t('Aceitar convite e entrar')}
              </button>
            </div>
            <p className="text-xs text-muted-foreground">{t('Ou copie e cole o seguinte link no seu navegador:')}</p>
            <p className="text-xs text-accent break-all bg-input p-3 border border-border font-mono">
              {t('https://centradeprocessos.app/convite/c3b8d9e2f4a1b6c9d8e2f4a1b6c9d8e2')}
            </p>
          </div>

          {/* Details */}
          <div className="border-t border-border pt-6 flex flex-col gap-3">
            <p className="text-xs font-medium text-foreground uppercase tracking-wide">{t('Informações do convite')}</p>
            <table className="w-full text-sm">
              <tbody className="flex flex-col gap-2">
                <tr className="flex">
                  <td className="text-muted-foreground w-32 font-medium">{t('Plataforma:')}</td>
                  <td className="text-foreground">{t('Central de Processos')}</td>
                </tr>
                <tr className="flex">
                  <td className="text-muted-foreground w-32 font-medium">{t('Equipe:')}</td>
                  <td className="text-foreground">{t('Souza & Associados Advocacia')}</td>
                </tr>
                <tr className="flex">
                  <td className="text-muted-foreground w-32 font-medium">{t('Válido até:')}</td>
                  <td className="text-foreground">{t('16 de julho de 2025')}</td>
                </tr>
                <tr className="flex">
                  <td className="text-muted-foreground w-32 font-medium">{t('Enviado em:')}</td>
                  <td className="text-foreground">{t('09 de julho de 2025 às 14h32')}</td>
                </tr>
              </tbody>
            </table>
          </div>

          {/* Footer notes */}
          <div className="border-t border-border pt-6 flex flex-col gap-4 text-xs text-muted-foreground leading-relaxed">
            <p>{t('Este convite foi enviado porque seu e-mail foi registrado como um dos membros da equipe. Se você não esperava receber este convite, entre em contato com o titular da plataforma.')}</p>
            <p>{t('Este é um e-mail de notificação. Não responda a este endereço.')}</p>
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
