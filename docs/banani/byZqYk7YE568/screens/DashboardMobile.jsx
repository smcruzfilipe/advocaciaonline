export const displayName = 'Dashboard — Mobile';
export const screenSize = 'mobile';

import TopBarMobile from '@components/TopBarMobile';
import MetricCard from '@components/MetricCard';
import AlertBanner from '@components/AlertBanner';
import Icon from '@global/Icon';

export default function DashboardMobileScreen() {
  return (
    <div className="bg-background font-body">
      <TopBarMobile activeTab="dashboard" />

      <div className="px-4 py-5 flex flex-col gap-5">
        {/* Context */}
        <div className="flex items-center gap-2 text-xs text-muted-foreground border-b border-border pb-3">
          <Icon i="building-2" size={13} />
          <span>{t('Souza & Associados')}</span>
          <a className="text-accent underline ml-auto">{t('trocar')}</a>
        </div>

        <p className="text-xs text-muted-foreground">{t('Atualizado às 10h31 de 09/07/2025 — Brasília (UTC−3)')}</p>

        {/* Alert */}
        <AlertBanner variant="error">
          <span className="font-medium">{t('TJSP')}</span>{t(' — coleta com falha desde 09/07, 03h12.')}
        </AlertBanner>

        {/* Hoje */}
        <div>
          <p className="text-xs font-medium text-foreground mb-2 uppercase tracking-wide">{t('Hoje')}</p>
          <div className="grid grid-cols-2 gap-3">
            <MetricCard label={t('Comunicações novas')} value="14" period={t('publicações')} />
            <MetricCard label={t('Processos distintos')} value="9" period={t('processos')} />
          </div>
        </div>

        {/* Semana */}
        <div>
          <p className="text-xs font-medium text-foreground mb-2 uppercase tracking-wide">{t('Esta semana')}</p>
          <div className="grid grid-cols-2 gap-3">
            <MetricCard label={t('Comunicações novas')} value="—" period={t('em andamento')} state="loading" />
            <MetricCard label={t('Processos distintos')} value="—" period={t('em andamento')} state="loading" />
          </div>
        </div>

        {/* 7 days */}
        <div>
          <p className="text-xs font-medium text-foreground mb-2 uppercase tracking-wide">{t('Últimos 7 dias')}</p>
          <div className="grid grid-cols-2 gap-3">
            <MetricCard label={t('Comunicações novas')} value="*" period={t('acesso restrito')} state="restricted" />
            <MetricCard label={t('Processos distintos')} value="0" period={t('sem processos')} />
          </div>
        </div>
      </div>
    </div>
  );
}
