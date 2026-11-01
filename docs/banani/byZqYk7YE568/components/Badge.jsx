export const displayName = 'Status Badge';
export const shortDescription = 'Small status/label badge';

const variants = {
  success: 'bg-success-bg text-success border border-success',
  warning: 'bg-warning-bg text-warning border border-warning',
  error: 'bg-error-bg text-error border border-error',
  info: 'bg-info-bg text-info border border-info',
  muted: 'bg-muted text-muted-foreground border border-border',
  active: 'bg-success-bg text-success border border-success',
  inactive: 'bg-muted text-muted-foreground border border-border',
};

export default function Badge({ label = 'Ativo', variant = 'muted' }) {
  return (
    <span className={`inline-flex items-center px-2 py-0.5 text-xs font-medium ${variants[variant] || variants.muted}`}>
      {label}
    </span>
  );
}
