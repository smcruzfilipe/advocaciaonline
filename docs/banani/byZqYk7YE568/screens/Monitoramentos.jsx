export const displayName = 'Monitoramentos';
export const screenSize = 'desktop';

import TopBar from '@components/TopBar';
import PageShell from '@components/PageShell';
import SectionHeader from '@components/SectionHeader';
import MonitoringRow from '@components/MonitoringRow';
import Btn from '@components/Btn';
import AlertBanner from '@components/AlertBanner';
import Badge from '@components/Badge';

const partesMonitoradas = [
  { name: t('PETROBRAS — Petróleo Brasileiro S.A.'), tribunals: t('TJSP, TJRJ, TRF-2'), status: 'ativo' },
  { name: t('Maria Aparecida da Silva'), tribunals: t('Todos os tribunais'), status: 'ativo' },
  { name: t('Construtora Horizonte Ltda.'), tribunals: t('TJMG, TRT-3'), status: 'inativo' },
];

const processosMonitorados = [
  { name: '0012345-67.2023.8.13.0024', tribunals: t('TJMG'), status: 'ativo' },
  { name: '0007891-23.2022.5.03.0001', tribunals: t('TRT-3'), status: 'ativo' },
  { name: '1234567-89.2021.4.03.6100', tribunals: t('TRF-3'), status: 'inativo' },
];

export default function MonitoramentosScreen() {
  return (
    <div className="bg-background font-body">
      <TopBar activeTab="monitoramentos" />

      <PageShell maxWidth="max-w-4xl">
        <div className="mb-6">
          <h1 className="text-xl font-semibold font-headings text-foreground">{t('Monitoramentos')}</h1>
          <p className="text-sm text-muted-foreground mt-0.5">{t('Gerencie os dados usados para rastrear publicações: dados do advogado, partes e processos.')}</p>
        </div>

        {/* Advogado */}
        <div className="mb-8">
          <SectionHeader title={t('Dados do advogado')} subtitle={t('Informações do seu perfil usadas no monitoramento automático.')} />
          <div className="border border-border p-5 flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">{t('Rafael Mendonça Souza')}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{t('OAB/MG 123.456 (principal) · OAB/SP 87.432 (secundária)')}</p>
              </div>
              <Badge label={t('Monitoramento ativo')} variant="active" />
            </div>
            <p className="text-xs text-muted-foreground border-t border-border pt-3">
              {t('Os dados exibidos acima fazem parte do seu perfil. Para alterá-los, edite seu perfil nas configurações da conta.')}
            </p>
          </div>
        </div>

        {/* Partes monitoradas */}
        <div className="mb-8">
          <SectionHeader
            title={t('Partes monitoradas')}
            subtitle={t('Nomes de pessoas ou empresas a acompanhar nas publicações.')}
            action={<Btn variant="primary" size="sm" icon="plus">{t('Nova parte')}</Btn>}
          />
          <div className="border border-border flex flex-col">
            {partesMonitoradas.map((p, i) => (
              <MonitoringRow key={i} name={p.name} tribunals={p.tribunals} status={p.status} />
            ))}
          </div>
        </div>

        {/* Processos monitorados */}
        <div className="mb-8">
          <SectionHeader
            title={t('Processos monitorados')}
            subtitle={t('Números CNJ de processos a acompanhar.')}
            action={<Btn variant="primary" size="sm" icon="plus">{t('Novo processo')}</Btn>}
          />
          <div className="border border-border flex flex-col">
            {processosMonitorados.map((p, i) => (
              <MonitoringRow key={i} name={p.name} tribunals={p.tribunals} status={p.status} />
            ))}
          </div>
        </div>

        {/* Error state */}
        <AlertBanner variant="error">
          {t('Não foi possível carregar os monitoramentos. ')}<a className="underline">{t('Tentar novamente')}</a>
        </AlertBanner>
      </PageShell>
    </div>
  );
}
