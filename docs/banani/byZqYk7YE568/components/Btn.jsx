import Icon from '@global/Icon';

export const displayName = 'Button';
export const shortDescription = 'Primary, secondary, ghost, and danger buttons';

const variants = {
  primary: 'bg-primary text-primary-foreground border border-primary',
  secondary: 'bg-background text-foreground border border-border',
  ghost: 'bg-transparent text-muted-foreground border border-transparent',
  danger: 'bg-error text-primary-foreground border border-error',
  accent: 'bg-accent text-accent-foreground border border-accent',
};

const sizes = {
  sm: 'px-3 py-1.5 text-xs',
  md: 'px-4 py-2 text-sm',
  lg: 'px-5 py-2.5 text-base',
};

export default function Btn({
  children = 'Botão',
  variant = 'primary',
  size = 'md',
  icon = '',
  disabled = false,
}) {
  return (
    <button
      className={`inline-flex items-center gap-2 font-medium font-body ${variants[variant] || variants.primary} ${sizes[size] || sizes.md} ${disabled ? 'opacity-40' : ''}`}
    >
      {icon && <Icon i={icon} size={14} />}
      {children}
    </button>
  );
}
