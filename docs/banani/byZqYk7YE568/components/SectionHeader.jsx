export const displayName = 'Section Header';
export const shortDescription = 'Section title with optional subtitle and action';

export default function SectionHeader({
  title = 'Seção',
  subtitle = '',
  action = null,
}) {
  return (
    <div className="flex items-start justify-between gap-4 mb-4 font-body">
      <div>
        <h2 className="text-lg font-semibold text-foreground font-headings">{title}</h2>
        {subtitle && <p className="text-sm text-muted-foreground mt-0.5">{subtitle}</p>}
      </div>
      {action && <div className="flex-shrink-0">{action}</div>}
    </div>
  );
}
