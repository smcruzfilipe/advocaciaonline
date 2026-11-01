export const displayName = 'Seleção de Vínculo';
export const screenSize = 'desktop';

import AlertBanner from '@components/AlertBanner';
import Btn from '@components/Btn';
import Badge from '@components/Badge';
import Icon from '@global/Icon';

const vinculos = [
  {
    name: 'Souza & Associados Advocacia',
    role: t('Titular'),
    type: 'escritorio',
    active: true,
  },
  {
    name: 'Ferreira, Lima e Rodrigues Advogados',
    role: t('Membro da equipe'),
    type: 'escritorio',
    active: false,
  },
  {
    name: 'Rafael Mendonça Souza (pessoal)',
    role: t('Titular'),
    type: 'pessoal',
    active: false,
  },
];

export default function VinculationScreen() {
  return (
    <div className="bg-background font-body" style={{ minHeight: '600px' }}>
      <div className="border-b border-border px-8 py-4 flex items-center justify-between">
        <span className="text-base font-semibold font-headings text-foreground">{t('Central de Processos')}</span>
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-full bg-muted flex items-center justify-center">
            <Icon i="user" size={14} />
          </div>
          <span className="text-sm text-foreground">{t('Rafael Mendonça Souza')}</span>
          <a className="text-xs text-muted-foreground underline ml-1">{t('sair')}</a>
        </div>
      </div>

      <div className="flex items-start justify-center py-12 px-4">
        <div className="w-full max-w-lg flex flex-col gap-6">
          <div>
            <h1 className="text-2xl font-semibold font-headings text-foreground mb-1">{t('Selecionar vínculo')}</h1>
            <p className="text-sm text-muted-foreground">{t('Escolha em qual contexto profissional você quer trabalhar agora.')}</p>
          </div>

          <div className="border border-border flex flex-col">
            {vinculos.map((v, i) => (
              <div
                key={i}
                className={`flex items-center justify-between px-5 py-4 border-b border-border last:border-b-0 ${v.active ? 'bg-secondary' : 'bg-background'}`}
              >
                <div className="flex flex-col gap-0.5">
                  <div className="flex items-center gap-2">
                    <Icon i={v.type === 'pessoal' ? 'user' : 'building-2'} size={15} />
                    <span className="text-sm font-medium text-foreground">{v.name}</span>
                    {v.active && <Badge label={t('Atual')} variant="active" />}
                  </div>
                  <span className="text-xs text-muted-foreground ml-5">{v.role}</span>
                </div>
                {!v.active && (
                  <button className="text-sm font-medium text-accent underline flex-shrink-0">{t('Selecionar')}</button>
                )}
              </div>
            ))}

            {/* Unavailable vínculo example */}
            <div className="flex items-center justify-between px-5 py-4 bg-background opacity-50">
              <div className="flex flex-col gap-0.5">
                <div className="flex items-center gap-2">
                  <Icon i="building-2" size={15} />
                  <span className="text-sm font-medium text-foreground">{t('Costa & Silva Advocacia')}</span>
                  <Badge label={t('Indisponível')} variant="muted" />
                </div>
                <span className="text-xs text-muted-foreground ml-5">{t('Membro da equipe')}</span>
              </div>
            </div>
          </div>

          <AlertBanner variant="warning">
            {t('Um dos vínculos está indisponível. Entre em contato com o titular para verificar o status da sua credencial.')}
          </AlertBanner>

          {/* Session error state */}
          <AlertBanner variant="error">
            {t('Sua sessão não está mais válida. ')}<a className="underline">{t('Entre novamente')}</a>{t(' para continuar.')}
          </AlertBanner>
        </div>
      </div>
    </div>
  );
}
