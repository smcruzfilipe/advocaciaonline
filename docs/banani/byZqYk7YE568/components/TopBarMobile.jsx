import Icon from '@global/Icon';

export const displayName = 'Top Bar Mobile';
export const shortDescription = 'Mobile navigation top bar with tab strip';

export default function TopBarMobile({
  activeTab = 'dashboard',
  userName = 'Dr. Rafael Souza',
}) {
  const navItems = [
    { label: t('Dashboard'), id: 'dashboard' },
    { label: t('Comunicações'), id: 'comunicacoes' },
    { label: t('Monitoramentos'), id: 'monitoramentos' },
    { label: t('Equipe'), id: 'equipe' },
  ];

  return (
    <header className="bg-background border-b border-border w-full font-body">
      <div className="flex items-center justify-between px-4 py-3">
        <span className="text-base font-semibold font-headings text-foreground">{t('Central de Processos')}</span>
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-full bg-muted flex items-center justify-center">
            <Icon i="user" size={14} />
          </div>
        </div>
      </div>
      <nav className="flex overflow-x-auto border-b border-border">
        {navItems.map((item) => (
          <a
            key={item.id}
            className={`flex-shrink-0 px-4 py-2 text-sm font-medium border-b-2 ${
              activeTab === item.id
                ? 'border-foreground text-foreground'
                : 'border-transparent text-muted-foreground'
            }`}
          >
            {item.label}
          </a>
        ))}
      </nav>
    </header>
  );
}
