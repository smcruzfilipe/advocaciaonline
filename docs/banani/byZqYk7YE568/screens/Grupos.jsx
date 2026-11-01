export const displayName = 'Grupos e Permissões';
export const screenSize = 'desktop';

import TopBar from '@components/TopBar';
import PageShell from '@components/PageShell';
import SectionHeader from '@components/SectionHeader';
import Badge from '@components/Badge';
import Btn from '@components/Btn';
import AlertBanner from '@components/AlertBanner';
import Icon from '@global/Icon';

const groups = [
  {
    name: t('Leitores'),
    memberCount: 3,
    rules: [
      { op: t('Ler comunicações'), allowed: true, tribunal: t('Todos') },
      { op: t('Ver dashboard'), allowed: true, tribunal: t('Todos') },
    ],
  },
  {
    name: t('Triagem'),
    memberCount: 1,
    rules: [
      { op: t('Ler comunicações'), allowed: true, tribunal: t('TJMG, TJSP') },
      { op: t('Ver dashboard'), allowed: false, tribunal: t('Todos') },
    ],
  },
];

export default function GruposScreen() {
  return (
    <div className="bg-background font-body">
      <TopBar activeTab="equipe" />

      <PageShell maxWidth="max-w-4xl">
        <div className="mb-6 flex items-start justify-between">
          <div>
            <h1 className="text-xl font-semibold font-headings text-foreground">{t('Grupos e permissões')}</h1>
            <p className="text-sm text-muted-foreground mt-0.5">{t('Organize permissões da equipe em grupos reutilizáveis.')}</p>
          </div>
          <Btn variant="primary" icon="plus">{t('Novo grupo')}</Btn>
        </div>

        {/* Explanation */}
        <div className="border border-border bg-input p-4 mb-6">
          <p className="text-xs text-muted-foreground leading-relaxed">
            <span className="font-medium text-foreground">{t('Como as permissões funcionam: ')}</span>
            {t('Permissões de grupos se somam. Uma negação explícita prevalece sobre permissões do mesmo escopo. Sem grupos, a equipe tem leituras padrão, mas não recebe escrita automaticamente. Remover a última associação de um membro não revoga a credencial. A permissão de dashboard é separada da leitura de comunicações e não amplia os tribunais acessíveis.')}
          </p>
        </div>

        {/* Groups */}
        <div className="flex flex-col gap-6">
          {groups.map((g, gi) => (
            <div key={gi} className="border border-border">
              {/* Group header */}
              <div className="flex items-center justify-between px-5 py-3.5 border-b border-border bg-secondary">
                <div className="flex items-center gap-3">
                  <span className="text-sm font-semibold text-foreground">{g.name}</span>
                  <span className="text-xs text-muted-foreground">{g.memberCount} {t('membro(s)')}</span>
                </div>
                <div className="flex gap-2">
                  <Btn variant="secondary" size="sm" icon="pencil">{t('Editar')}</Btn>
                  <Btn variant="ghost" size="sm" icon="trash-2">{t('Remover')}</Btn>
                </div>
              </div>

              {/* Rules table */}
              <div>
                <div className="grid grid-cols-3 gap-0 border-b border-border bg-background">
                  <div className="px-5 py-2.5 text-xs font-medium text-muted-foreground uppercase tracking-wide">{t('Operação')}</div>
                  <div className="px-5 py-2.5 text-xs font-medium text-muted-foreground uppercase tracking-wide">{t('Permissão')}</div>
                  <div className="px-5 py-2.5 text-xs font-medium text-muted-foreground uppercase tracking-wide">{t('Tribunal')}</div>
                </div>
                {g.rules.map((r, ri) => (
                  <div key={ri} className={`grid grid-cols-3 gap-0 border-b border-border last:border-b-0 ${ri % 2 === 1 ? 'bg-table-row-alt' : 'bg-background'}`}>
                    <div className="px-5 py-3 text-sm text-foreground">{r.op}</div>
                    <div className="px-5 py-3">
                      <Badge label={r.allowed ? t('Permitida') : t('Negada')} variant={r.allowed ? 'active' : 'error'} />
                    </div>
                    <div className="px-5 py-3 text-sm text-muted-foreground">{r.tribunal}</div>
                  </div>
                ))}
                <div className="px-5 py-2.5 flex justify-end gap-2 border-t border-border bg-background">
                  <button className="text-xs text-accent underline">{t('Adicionar regra')}</button>
                </div>
              </div>

              {/* Members */}
              <div className="border-t border-border px-5 py-3.5 bg-background flex items-center justify-between gap-4">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-xs text-muted-foreground">{t('Membros:')}</span>
                  {gi === 0 && (
                    <>
                      <Badge label="Ana Paula Ferreira" variant="muted" />
                      <Badge label="Carlos Lima" variant="muted" />
                      <Badge label="Fernanda Oliveira" variant="muted" />
                    </>
                  )}
                  {gi === 1 && (
                    <Badge label="Ana Paula Ferreira" variant="muted" />
                  )}
                </div>
                <div className="flex gap-2">
                  <button className="text-xs text-accent underline">{t('Adicionar membro')}</button>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Empty state */}
        <div className="mt-6 border border-border p-10 flex flex-col items-center gap-3 text-center">
          <Icon i="users" size={30} className="text-muted-foreground" />
          <p className="text-sm font-medium text-foreground">{t('Nenhum grupo criado')}</p>
          <p className="text-xs text-muted-foreground max-w-xs">{t('Crie grupos para organizar permissões de equipe. Sem grupos, membros têm apenas leituras padrão.')}</p>
        </div>
      </PageShell>
    </div>
  );
}
