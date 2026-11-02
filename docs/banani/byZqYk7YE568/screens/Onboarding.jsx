export const displayName = 'Cadastro Inicial do Advogado';
export const screenSize = 'desktop';

import FormField from '@components/FormField';
import TextInput from '@components/TextInput';
import Btn from '@components/Btn';
import AlertBanner from '@components/AlertBanner';
import Icon from '@global/Icon';

const UFs = ['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'];

export default function OnboardingScreen() {
  const secondaryOABs = [
    { numero: '87.432', uf: 'SP' },
    { numero: '', uf: '' },
  ];

  return (
    <div className="bg-background font-body" style={{ minHeight: '600px' }}>
      {/* Header */}
      <div className="border-b border-border px-8 py-4">
        <span className="text-base font-semibold font-headings text-foreground">{t('Central de Processos')}</span>
      </div>

      <div className="flex items-start justify-center py-12 px-4">
        <div className="w-full max-w-xl flex flex-col gap-6">
          <div>
            <h1 className="text-2xl font-semibold font-headings text-foreground mb-1">{t('Complete seu perfil')}</h1>
            <p className="text-sm text-muted-foreground">{t('Informe seus dados profissionais para começar a usar a plataforma.')}</p>
          </div>

          <div className="border border-border p-6 flex flex-col gap-5">
            <FormField label={t('Nome completo')} required={true}>
              <TextInput value="Rafael Mendonça Souza" />
            </FormField>

            <div className="border-t border-border pt-5">
              <p className="text-sm font-medium text-foreground mb-3">{t('OAB principal')}</p>
              <div className="flex gap-3">
                <div className="flex-1">
                  <FormField label={t('Número')} required={true}>
                    <TextInput value="123.456" />
                  </FormField>
                </div>
                <div className="w-24">
                  <FormField label={t('Estado')} required={true}>
                    <div className="border border-border px-3 py-2 text-sm bg-input text-foreground flex justify-between items-center">
                      <span>MG</span>
                      <Icon i="chevron-down" size={13} />
                    </div>
                  </FormField>
                </div>
              </div>
            </div>

            <div className="border-t border-border pt-5">
              <div className="flex items-center justify-between mb-3">
                <p className="text-sm font-medium text-foreground">{t('OABs secundárias')}</p>
                <button className="text-xs text-accent flex items-center gap-1 underline">
                  <Icon i="plus" size={13} />
                  {t('Adicionar')}
                </button>
              </div>
              <div className="flex flex-col gap-3">
                {secondaryOABs.map((oab, i) => (
                  <div key={i} className="flex gap-3 items-end">
                    <div className="flex-1">
                      <FormField label={i === 0 ? t('Número') : ''}>
                        <TextInput value={oab.numero} placeholder="Ex.: 87.432" hasError={i === 1} />
                      </FormField>
                      {i === 1 && <p className="text-xs text-error mt-0.5 flex items-center gap-1"><Icon i="alert-circle" size={12} />{t('Número obrigatório ao adicionar OAB')}</p>}
                    </div>
                    <div className="w-24">
                      <FormField label={i === 0 ? t('Estado') : ''}>
                        <div className={`border px-3 py-2 text-sm bg-input flex justify-between items-center ${i === 1 ? 'border-error' : 'border-border'} text-foreground`}>
                          <span>{oab.uf || <span className="text-muted-foreground">UF</span>}</span>
                          <Icon i="chevron-down" size={13} />
                        </div>
                      </FormField>
                    </div>
                    <button className="mb-0.5 text-muted-foreground flex-shrink-0 pb-2">
                      <Icon i="x" size={16} />
                    </button>
                  </div>
                ))}
              </div>
            </div>

            <div className="border-t border-border pt-5">
              <FormField label={t('Nome do escritório')} hint={t('Opcional. Identificação do seu escritório na plataforma.')}>
                <TextInput value="Souza & Associados Advocacia" />
              </FormField>
            </div>
          </div>

          <div className="flex justify-end gap-3">
            <Btn variant="primary">{t('Salvar perfil')}</Btn>
          </div>

          {/* Saving state indicator (shown during save) */}
          <AlertBanner variant="info">{t('Salvando suas informações…')}</AlertBanner>
        </div>
      </div>
    </div>
  );
}
