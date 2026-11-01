export const displayName = 'Equipe e Credenciais';
export const screenSize = 'desktop';

import TopBar from '@components/TopBar';
import PageShell from '@components/PageShell';
import SectionHeader from '@components/SectionHeader';
import TeamMemberRow from '@components/TeamMemberRow';
import Btn from '@components/Btn';
import FormField from '@components/FormField';
import TextInput from '@components/TextInput';
import AlertBanner from '@components/AlertBanner';
import Icon from '@global/Icon';

const members = [
  {
    name: t('Ana Paula Ferreira'),
    email: 'ana.ferreira@email.com',
    credentialStatus: 'ativa',
    validity: t('Sem expiração'),
    groups: [t('Leitores'), t('Triagem')],
  },
  {
    name: t('Carlos Eduardo Lima'),
    email: 'carloslima@email.com',
    credentialStatus: 'expirada',
    validity: t('Expirou em 01/07/2025'),
    groups: [t('Leitores')],
  },
  {
    name: t('Fernanda Oliveira'),
    email: 'fernanda.o@email.com',
    credentialStatus: 'pendente',
    validity: t('Convite expira em 16/07/2025'),
    groups: [],
  },
  {
    name: t('Ricardo Matos'),
    email: 'rmatos@email.com',
    credentialStatus: 'revogada',
    validity: t('Revogada em 20/06/2025'),
    groups: [],
  },
];

export default function EquipeScreen() {
  return (
    <div className="bg-background font-body">
      <TopBar activeTab="equipe" />

      <PageShell maxWidth="max-w-4xl">
        <div className="mb-6">
          <h1 className="text-xl font-semibold font-headings text-foreground">{t('Equipe e credenciais')}</h1>
          <p className="text-sm text-muted-foreground mt-0.5">{t('Gerencie os membros da equipe e o acesso de cada um à plataforma. Visível apenas para o titular.')}</p>
        </div>

        {/* Members list */}
        <div className="mb-10">
          <SectionHeader title={t('Membros da equipe')} subtitle={t('Credenciais ativas, pendentes, expiradas e revogadas.')} />
          <div className="border border-border flex flex-col">
            {members.map((m, i) => (
              <TeamMemberRow key={i} name={m.name} email={m.email} credentialStatus={m.credentialStatus} validity={m.validity} groups={m.groups} />
            ))}
          </div>
        </div>

        {/* Invite form */}
        <div className="mb-6">
          <SectionHeader title={t('Enviar convite')} subtitle={t('O convidado receberá um link para aceitar o vínculo com sua conta Google.')} />
          <div className="border border-border p-5 flex flex-col gap-5">
            <FormField label={t('E-mail do convidado')} required={true}>
              <TextInput value="" placeholder="email@exemplo.com" />
            </FormField>

            <div>
              <p className="text-sm font-medium text-foreground mb-2">{t('Validade da credencial')}</p>
              <div className="flex flex-col gap-2">
                <div className="flex items-center gap-3 px-3 py-2.5 border border-foreground bg-secondary">
                  <div className="w-4 h-4 rounded-full border-2 border-foreground flex items-center justify-center flex-shrink-0">
                    <div className="w-2 h-2 rounded-full bg-foreground" />
                  </div>
                  <span className="text-sm text-foreground">{t('Sem expiração')}</span>
                </div>
                <div className="flex items-center gap-3 px-3 py-2.5 border border-border bg-background">
                  <div className="w-4 h-4 rounded-full border border-border flex-shrink-0" />
                  <span className="text-sm text-foreground">{t('Número de dias')}</span>
                  <div className="ml-2 border border-border px-3 py-1 text-sm bg-input text-muted-foreground w-24">
                    {t('Ex.: 30')}
                  </div>
                </div>
              </div>
            </div>

            <FormField label={t('Grupos (opcional)')} hint={t('O membro herdará as permissões dos grupos selecionados.')}>
              <div className="border border-border px-3 py-2 text-sm bg-input text-muted-foreground flex justify-between items-center">
                {t('Selecionar grupos')} <Icon i="chevron-down" size={13} />
              </div>
            </FormField>

            <div className="flex justify-end">
              <Btn variant="primary" icon="send">{t('Enviar convite')}</Btn>
            </div>

            {/* Send error */}
            <AlertBanner variant="error">
              {t('O envio do convite falhou. O convite pode ter sido criado mas não entregue. Aguarde e, se necessário, reemita um novo convite — isso não indica que a credencial deixou de existir.')}
            </AlertBanner>
          </div>
        </div>

        {/* Admin notes */}
        <div className="border border-border bg-input p-4">
          <p className="text-xs text-muted-foreground leading-relaxed">
            <span className="font-medium text-foreground">{t('Sobre validade e renovação: ')}</span>
            {t('A alteração da validade passa a valer na próxima renovação — a credencial vigente não é interrompida. Uma credencial revogada não é reativada por renovação: é necessário emitir um novo convite.')}
          </p>
        </div>
      </PageShell>
    </div>
  );
}
