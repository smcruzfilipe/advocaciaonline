import Icon from '@global/Icon';

export const displayName = 'Empty State';
export const shortDescription = 'Empty/no-data state with icon, title and description';

export default function EmptyState({
  icon = 'inbox',
  title = 'Nenhum dado encontrado',
  description = '',
  action = null,
}) {
  return (
    <div className="flex flex-col items-center justify-center py-16 gap-3 font-body text-center">
      <div className="text-muted-foreground">
        <Icon i={icon} size={36} />
      </div>
      <p className="text-base font-medium text-foreground">{title}</p>
      {description && <p className="text-sm text-muted-foreground max-w-xs">{description}</p>}
      {action}
    </div>
  );
}
