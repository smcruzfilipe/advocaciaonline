export const displayName = 'Tela de Login';
export const screenSize = 'desktop';

import Btn from '@components/Btn';
import AlertBanner from '@components/AlertBanner';

export default function LoginScreen() {
  return (
    <div className="bg-background min-h-full flex flex-col font-body" style={{ minHeight: '600px' }}>
      {/* Header */}
      <div className="border-b border-border px-8 py-4">
        <span className="text-base font-semibold font-headings text-foreground">{t('Central de Processos')}</span>
      </div>

      {/* Content */}
      <div className="flex-1 flex items-center justify-center py-20">
        <div className="w-full max-w-sm flex flex-col gap-6">
          <div>
            <h1 className="text-2xl font-semibold font-headings text-foreground mb-2">{t('Entrar')}</h1>
            <p className="text-sm text-muted-foreground">{t('Acesse sua conta com o Google para continuar.')}</p>
          </div>

          {/* Login button */}
          <div className="border border-border p-6 flex flex-col gap-4">
            <button className="w-full flex items-center justify-center gap-3 border border-border bg-background px-4 py-3 text-sm font-medium text-foreground">
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M17.64 9.205c0-.639-.057-1.252-.164-1.841H9v3.481h4.844a4.14 4.14 0 01-1.796 2.716v2.259h2.908c1.702-1.567 2.684-3.875 2.684-6.615z" fill="#4285F4"/>
                <path d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 009 18z" fill="#34A853"/>
                <path d="M3.964 10.71A5.41 5.41 0 013.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.996 8.996 0 000 9c0 1.452.348 2.827.957 4.042l3.007-2.332z" fill="#FBBC05"/>
                <path d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 00.957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z" fill="#EA4335"/>
              </svg>
              {t('Continuar com Google')}
            </button>
          </div>

          {/* Error state */}
          <AlertBanner variant="error">
            <span>{t('Não foi possível entrar. Verifique se o acesso ao Google está disponível e ')}<a className="underline">{t('tente novamente')}</a>{t('.')}</span>
          </AlertBanner>

          <p className="text-xs text-muted-foreground text-center">{t('Ao continuar, você concorda com os termos de uso da plataforma.')}</p>
        </div>
      </div>
    </div>
  );
}
