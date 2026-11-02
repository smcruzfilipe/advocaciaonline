export const displayName = 'Parte Monitorada — Cadastro e Edição';
export const screenSize = 'desktop';

import TopBar from '@components/TopBar';
import PageShell from '@components/PageShell';
import FormField from '@components/FormField';
import TextInput from '@components/TextInput';
import AlertBanner from '@components/AlertBanner';
import Btn from '@components/Btn';
import Badge from '@components/Badge';
import Icon from '@global/Icon';

const tribunais = [
  { code: 'TJMG', label: t('TJMG — Minas Gerais'), selected: true },
  { code: 'TJSP', label: t('TJSP — São Paulo'), selected: true },
  { code: 'TJRJ', label: t('TJRJ — Rio de Janeiro'), selected: false },
  { code: 'TRT-3', label: t('TRT-3 — TRT da 3ª Região'), selected: false },
  { code: 'TRF-3', label: t('TRF-3 — TRF da 3ª Região'), selected: false },
];

export default function ParteDetalheScreen() {
  return (
    <div className="bg-background font-body">
      <TopBar activeTab="monitoramentos" />

      <PageShell maxWidth="max-w-2xl">
        {/* Breadcrumb */}
        <div className="flex items-center gap-2 text-sm text-muted-foreground mb-6">
          <a className="underline text-accent">{t('Monitoramentos')}</a>
          <Icon i="chevron-right" size={13} />
          <span>{t('Parte monitorada')}</span>
        </div>

        <div className="flex items-start justify-between mb-4">
          <h1 className="text-xl font-semibold font-headings text-foreground">{t('Editar parte monitorada')}</h1>
          <Badge label={t('Ativa')} variant="active" />
        </div>

        <div className="flex flex-col gap-5">
          <AlertBanner variant="warning">
            {t('Já existe uma parte com nome similar: "PETROBRAS S.A.". Verifique antes de salvar para evitar monitoramentos duplicados. O sistema não identifica homônimos automaticamente.')}
          </AlertBanner>

          <div className="border border-border p-5 flex flex-col gap-5">
            <FormField label={t('Nome da parte')} required={true} error="">
              <TextInput value="PETROBRAS — Petróleo Brasileiro S.A." />
            </FormField>

            <div>
              <FormField label={t('Tribunais')} hint={t('Sem seleção específica, o monitoramento abrange todos os tribunais disponíveis. Uma seleção explícita não pode ficar vazia.')}>
                <div className="flex flex-col gap-2 mt-2">
                  {tribunais.map((t_item) => (
                    <div key={t_item.code} className={`flex items-center gap-3 px-3 py-2.5 border ${t_item.selected ? 'border-foreground bg-secondary' : 'border-border bg-background'}`}>
                      <div className={`w-4 h-4 border flex items-center justify-center flex-shrink-0 ${t_item.selected ? 'border-foreground bg-foreground' : 'border-border'}`}>
                        {t_item.selected && <Icon i="check" size={10} className="text-primary-foreground" />}
                      </div>
                      <span className="text-sm text-foreground">{t_item.label}</span>
                    </div>
                  ))}
                </div>
              </FormField>
            </div>
          </div>

          {/* Save error */}
          <AlertBanner variant="error">
            {t('Erro ao salvar. Verifique sua conexão e tente novamente. Os dados preenchidos foram mantidos.')}
          </AlertBanner>

          {/* No permission */}
          <AlertBanner variant="warning">
            {t('Você não tem permissão para editar ou desativar partes monitoradas.')}
          </AlertBanner>

          <div className="flex items-center justify-between gap-3 border-t border-border pt-5">
            <button className="text-sm text-error underline">{t('Desativar parte')}</button>
            <div className="flex gap-3">
              <Btn variant="secondary">{t('Cancelar')}</Btn>
              <Btn variant="primary">{t('Salvar alterações')}</Btn>
            </div>
          </div>
        </div>
      </PageShell>
    </div>
  );
}
