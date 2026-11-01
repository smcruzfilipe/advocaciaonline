import Icon from '@global/Icon';

export const displayName = 'Top Bar';
export const shortDescription = 'Navigation top bar with tabs and user context';

const navItems = [
  { label: t('Dashboard'), id: 'dashboard' },
  { label: t('Comunicações'), id: 'comunicacoes' },
  { label: t('Monitoramentos'), id: 'monitoramentos' },
  { label: t('Equipe e grupos'), id: 'equipe' },
];

export default function TopBar({
  activeTab = 'dashboard',
  userName = 'Dr. Rafael Souza',
  vinculation = 'Souza & Associados Advocacia',
  showVinculationSwitch = true,
}) {
  return (
    <header className="bg-background border-b border-border w-full font-body">
      {/* Top row */}
      <div className="flex items-center justify-between px-8 py-3 border-b border-border">
        <div className="flex items-center gap-3">
          <span className="text-base font-headings font-semibold tracking-tight text-foreground">{t('Central de Processos')}</span>
        </div>
        <div className="flex items-center gap-4">
          {showVinculationSwitch && (
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Icon i="building-2" size={14} />
              <span>{vinculation}</span>
              <a className="text-accent underline text-xs ml-1">{t('trocar')}</a>
            </div>
          )}
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-full bg-muted flex items-center justify-center">
              <Icon i="user" size={14} />
            </div>
            <span className="text-sm text-foreground">{userName}</span>
            <a className="text-xs text-muted-foreground underline ml-1">{t('sair')}</a>
          </div>
        </div>
      </div>
      {/* Nav tabs */}
      <nav className="flex items-center gap-0 px-8">
        {navItems.map((item) => (
          <a
            key={item.id}
            className={`px-4 py-3 text-sm font-medium border-b-2 transition-none ${
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
