export const displayName = 'Detalhe da Comunicação';
export const screenSize = 'desktop';

import TopBar from '@components/TopBar';
import PageShell from '@components/PageShell';
import AlertBanner from '@components/AlertBanner';
import Badge from '@components/Badge';
import Btn from '@components/Btn';
import Icon from '@global/Icon';

export default function ComunicacaoDetalheScreen() {
  return (
    <div className="bg-background font-body">
      <TopBar activeTab="comunicacoes" />

      <PageShell maxWidth="max-w-3xl">
        {/* Breadcrumb */}
        <div className="flex items-center gap-2 text-sm text-muted-foreground mb-6">
          <a className="underline text-accent">{t('Comunicações')}</a>
          <Icon i="chevron-right" size={13} />
          <span>{t('Detalhe')}</span>
        </div>

        <div className="flex flex-col gap-6">
          {/* Alert: duplicidade */}
          <AlertBanner variant="warning">
            <span className="font-medium">{t('Possível duplicidade — ')}</span>
            {t('Esta comunicação está pendente de verificação. Pode ter sido coletada mais de uma vez.')}
          </AlertBanner>

          {/* Meta */}
          <div className="border border-border p-5 flex flex-col gap-3">
            <div className="flex items-start justify-between gap-4">
              <div className="flex flex-col gap-1">
                <p className="text-xs text-muted-foreground uppercase tracking-wide">{t('Tribunal')}</p>
                <p className="text-sm font-medium text-foreground">{t('TJMG — Tribunal de Justiça de Minas Gerais')}</p>
              </div>
              <Badge label={t('Pendente')} variant="warning" />
            </div>

            <div>
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Processo')}</p>
              <p className="text-sm font-mono text-foreground">{'0012345-67.2023.8.13.0024'}</p>
            </div>

            <div>
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1">{t('Data de coleta')}</p>
              <p className="text-sm text-foreground">{t('09/07/2025')}</p>
            </div>

            {/* Monitoramentos associados */}
            <div>
              <p className="text-xs text-muted-foreground uppercase tracking-wide mb-1.5">{t('Monitoramentos associados')}</p>
              <div className="flex flex-col gap-1">
                <div className="flex items-center gap-2">
                  <Badge label={t('Advogado')} variant="info" />
                  <span className="text-sm text-foreground">{t('Rafael Mendonça Souza — OAB/MG 123.456')}</span>
                </div>
                <div className="flex items-center gap-2">
                  <Badge label={t('Processo')} variant="muted" />
                  <span className="text-sm font-mono text-foreground">{'0012345-67.2023.8.13.0024'}</span>
                </div>
              </div>
            </div>
          </div>

          {/* Content */}
          <div className="flex flex-col gap-2">
            <p className="text-sm font-medium text-foreground">{t('Conteúdo da publicação')}</p>
            <div className="border border-border p-5 bg-input">
              <p className="text-sm text-foreground leading-relaxed whitespace-pre-wrap">
                {t('Intimação para manifestação no prazo de 15 (quinze) dias, nos termos do artigo 351 do Código de Processo Civil.\n\nProcesso n.º 0012345-67.2023.8.13.0024 — 2ª Vara Cível da Comarca de Belo Horizonte.\n\nDr. Rafael Mendonça Souza — OAB/MG 123.456.\n\nIntime-se a parte autora para que, no prazo de 15 (quinze) dias, se manifeste sobre a contestação apresentada, indicando as provas que pretende produzir. Após, encaminhe-se ao Ministério Público para vista, nos termos da legislação aplicável.\n\nBelo Horizonte, 08 de julho de 2025.')}
              </p>
            </div>
          </div>

          {/* Not found state */}
          <div className="border border-border p-8 flex flex-col items-center gap-3 text-center">
            <Icon i="file-x" size={32} className="text-muted-foreground" />
            <p className="text-base font-medium text-foreground">{t('Comunicação não encontrada')}</p>
            <p className="text-sm text-muted-foreground max-w-xs">{t('Esta comunicação pode estar indisponível ou não existir. Nenhuma informação adicional pode ser exibida.')}</p>
            <a className="text-sm text-accent underline">{t('Voltar para Comunicações')}</a>
          </div>
        </div>
      </PageShell>
    </div>
  );
}
