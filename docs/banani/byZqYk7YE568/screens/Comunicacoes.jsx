export const displayName = 'Comunicações';
export const screenSize = 'desktop';

import TopBar from '@components/TopBar';
import PageShell from '@components/PageShell';
import SectionHeader from '@components/SectionHeader';
import CommunicationRow from '@components/CommunicationRow';
import AlertBanner from '@components/AlertBanner';
import EmptyState from '@components/EmptyState';

const groups = [
  {
    tribunal: t('TJMG — Tribunal de Justiça de Minas Gerais'),
    items: [
      {
        processo: '0012345-67.2023.8.13.0024',
        resumo: t('Intimação para manifestação no prazo de 15 dias, nos termos do art. 351 do CPC. Processo n.º 0012345-67.2023.8.13.0024 — 2ª Vara Cível da Comarca de Belo Horizonte.'),
        data: '09/07/2025',
        duplicidade: false,
      },
      {
        processo: '0012345-67.2023.8.13.0024',
        resumo: t('Despacho de juntada de petição e encaminhamento para vista ao Ministério Público. Processo n.º 0012345-67.2023.8.13.0024 — 2ª Vara Cível da Comarca de Belo Horizonte.'),
        data: '09/07/2025',
        duplicidade: true,
      },
      {
        processo: '',
        resumo: t('Publicação de pauta de audiência para o dia 25/08/2025 às 14h00. Parte interessada: Rafael Mendonça Souza — OAB/MG 123.456. Número do processo não identificado na publicação.'),
        data: '08/07/2025',
        duplicidade: false,
      },
    ],
  },
  {
    tribunal: t('TRT-3 — Tribunal Regional do Trabalho da 3ª Região'),
    items: [
      {
        processo: '0001122-33.2024.5.03.0001',
        resumo: t('Mandado de citação expedido. Réu: Comércio Estrela Ltda. Autor representado por Rafael Mendonça Souza — OAB/MG 123.456. Prazo de resposta: 20 dias úteis.'),
        data: '07/07/2025',
        duplicidade: false,
      },
    ],
  },
];

export default function ComunicacoesScreen() {
  return (
    <div className="bg-background font-body">
      <TopBar activeTab="comunicacoes" />

      <PageShell maxWidth="max-w-4xl">
        <div className="mb-6">
          <h1 className="text-xl font-semibold font-headings text-foreground">{t('Comunicações')}</h1>
          <p className="text-sm text-muted-foreground mt-0.5">{t('Publicações judiciais coletadas para seus monitoramentos. Agrupadas por tribunal.')}</p>
        </div>

        <AlertBanner variant="info">
          {t('A lista abaixo não representa necessariamente o total de publicações — a coleta pode estar em andamento para alguns tribunais.')}
        </AlertBanner>

        <div className="mt-6 flex flex-col gap-8">
          {groups.map((group, gi) => (
            <div key={gi}>
              <div className="bg-secondary border border-border px-5 py-2.5">
                <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide">{group.tribunal}</p>
              </div>
              <div className="border border-t-0 border-border flex flex-col">
                {group.items.map((item, ii) => (
                  <CommunicationRow
                    key={ii}
                    processo={item.processo}
                    resumo={item.resumo}
                    data={item.data}
                    duplicidade={item.duplicidade}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>

        {/* Empty state (shown when no items) */}
        <div className="mt-8 border border-border">
          <EmptyState
            icon="mail"
            title={t('Nenhuma comunicação encontrada')}
            description={t('Não há publicações coletadas para o período selecionado. Isso não indica que a coleta foi concluída.')}
          />
        </div>

        {/* Error state */}
        <div className="mt-4">
          <AlertBanner variant="error">
            {t('Não foi possível carregar as comunicações. ')}<a className="underline">{t('Tentar novamente')}</a>
          </AlertBanner>
        </div>

        {/* Restricted state */}
        <div className="mt-4">
          <AlertBanner variant="warning">
            {t('Você não tem permissão para visualizar comunicações deste contexto.')}
          </AlertBanner>
        </div>
      </PageShell>
    </div>
  );
}
