export const displayName = 'Processo Monitorado — Cadastro e Edição';
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
  { code: 'TJSP', label: t('TJSP — São Paulo'), selected: false },
  { code: 'TRF-3', label: t('TRF-3 — TRF da 3ª Região'), selected: false },
];

export default function ProcessoDetalheScreen() {
  return (
    <div className="bg-background font-body">
      <TopBar activeTab="monitoramentos" />

      <PageShell maxWidth="max-w-2xl">
        <div className="flex items-center gap-2 text-sm text-muted-foreground mb-6">
          <a className="underline text-accent">{t('Monitoramentos')}</a>
          <Icon i="chevron-right" size={13} />
          <span>{t('Processo monitorado')}</span>
        </div>

        <div className="flex items-start justify-between mb-4">
          <h1 className="text-xl font-semibold font-headings text-foreground">{t('Novo processo monitorado')}</h1>
        </div>

        <div className="flex flex-col gap-5">
          <div className="border border-border p-5 flex flex-col gap-5">
            <FormField
              label={t('Número do processo (CNJ)')}
              required={true}
              hint={t('Informe o número completo com zeros. Formato: NNNNNNN-DD.AAAA.J.TT.OOOO')}
              error={t('Número inválido. Verifique o formato CNJ e os zeros iniciais.')}
            >
              <TextInput value="0012345-67.2023.8.13.0024" hasError={true} />
            </FormField>

            <AlertBanner variant="warning">
              {t('Este processo já está cadastrado: 0012345-67.2023.8.13.0024. Verifique antes de salvar.')}
            </AlertBanner>

            <div>
              <FormField label={t('Tribunais')} hint={t('Sem seleção, o monitoramento abrange todos os tribunais disponíveis.')}>
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

            {/* Tribunal load error */}
            <AlertBanner variant="error">
              {t('Não foi possível carregar a lista de tribunais. ')}<a className="underline">{t('Tentar novamente')}</a>
            </AlertBanner>
          </div>

          <div className="flex items-center justify-between gap-3 border-t border-border pt-5">
            <div />
            <div className="flex gap-3">
              <Btn variant="secondary">{t('Cancelar')}</Btn>
              <Btn variant="primary">{t('Salvar processo')}</Btn>
            </div>
          </div>
        </div>
      </PageShell>
    </div>
  );
}
