export const displayName = 'Dashboard';
export const screenSize = 'desktop';

import TopBar from '@components/TopBar';
import MetricCard from '@components/MetricCard';
import AlertBanner from '@components/AlertBanner';
import PageShell from '@components/PageShell';
import SectionHeader from '@components/SectionHeader';
import Icon from '@global/Icon';

const periods = [
  { label: t('Hoje'), key: 'hoje' },
  { label: t('Esta semana'), key: 'semana' },
  { label: t('Últimos 7 dias'), key: '7dias' },
];

const tribunalAlerts = [
  { name: t('TJSP — Tribunal de Justiça de São Paulo'), since: t('Falha desde 09/07/2025, 03h12 (Brasília)') },
  { name: t('TRF-3 — Tribunal Regional Federal da 3ª Região'), since: t('Falha desde 09/07/2025, 06h44 (Brasília)') },
];

export default function DashboardScreen() {
  return (
    <div className="bg-background font-body">
      <TopBar activeTab="dashboard" />

      <PageShell maxWidth="max-w-5xl">
        {/* Page title */}
        <div className="mb-6">
          <h1 className="text-xl font-semibold font-headings text-foreground">{t('Dashboard')}</h1>
          <p className="text-sm text-muted-foreground mt-0.5">{t('Atualizado às 10h31 de 09/07/2025 — fuso de Brasília (UTC−3)')}</p>
        </div>

        {/* Tribunal failure alerts */}
        {tribunalAlerts.length > 0 && (
          <div className="flex flex-col gap-2 mb-8">
            <p className="text-sm font-medium text-foreground mb-1">{t('Alertas de coleta')}</p>
            {tribunalAlerts.map((a, i) => (
              <AlertBanner key={i} variant="error">
                <span className="font-medium">{a.name}</span>
                {t(' — coleta com falha. ')}<span className="font-mono text-xs">{a.since}</span>
                {t(' Os números exibidos abaixo podem estar incompletos para este tribunal.')}
              </AlertBanner>
            ))}
          </div>
        )}

        {/* Periods */}
        {periods.map((period) => (
          <div key={period.key} className="mb-8">
            <SectionHeader title={period.label} />
            <div className="grid grid-cols-2 gap-4">
              {period.key === 'hoje' && (
                <>
                  <MetricCard
                    label={t('Comunicações novas')}
                    value="14"
                    period={t('publicações coletadas')}
                    state="value"
                  />
                  <MetricCard
                    label={t('Processos distintos associados')}
                    value="9"
                    period={t('processos com ao menos 1 comunicação')}
                    state="value"
                  />
                </>
              )}
              {period.key === 'semana' && (
                <>
                  <MetricCard
                    label={t('Comunicações novas')}
                    value="—"
                    period={t('coleta em andamento')}
                    state="loading"
                    note={t('Resultado parcial disponível — coleta ainda não finalizada.')}
                  />
                  <MetricCard
                    label={t('Processos distintos associados')}
                    value="—"
                    period={t('coleta em andamento')}
                    state="loading"
                  />
                </>
              )}
              {period.key === '7dias' && (
                <>
                  <MetricCard
                    label={t('Comunicações novas')}
                    value="*"
                    period={t('acesso restrito')}
                    state="restricted"
                    note={t('Sem permissão para visualizar este período.')}
                  />
                  <MetricCard
                    label={t('Processos distintos associados')}
                    value="0"
                    period={t('nenhum processo associado no período')}
                    state="value"
                  />
                </>
              )}
            </div>
          </div>
        ))}

        {/* No work state note */}
        <div className="border border-border bg-input p-4">
          <p className="text-sm text-muted-foreground">
            <Icon i="info" size={14} className="inline mr-1.5 text-info" />
            {t('Nenhum monitoramento ativo cadastrado. Configure monitoramentos para começar a receber comunicações.')}
          </p>
        </div>
      </PageShell>
    </div>
  );
}
