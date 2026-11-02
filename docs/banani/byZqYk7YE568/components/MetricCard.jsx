export const displayName = 'Metric Card';
export const shortDescription = 'Dashboard metric card with value, label and period';

const stateStyles = {
  value: 'text-foreground',
  loading: 'text-muted-foreground',
  error: 'text-error',
  restricted: 'text-muted-foreground',
  partial: 'text-warning',
};

export default function MetricCard({
  label = 'Métrica',
  value = '0',
  period = 'hoje',
  state = 'value', // 'value' | 'loading' | 'error' | 'restricted' | 'partial'
  note = '',
}) {
  const displayValue = state === 'restricted' ? '*' : state === 'loading' ? '—' : value;
  const valueClass = stateStyles[state] || stateStyles.value;

  return (
    <div className="border border-border bg-background p-5 flex flex-col gap-2 font-body">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className={`text-3xl font-semibold font-headings ${valueClass}`}>{displayValue}</p>
      <p className="text-xs text-muted-foreground">{period}</p>
      {note && <p className="text-xs text-muted-foreground border-t border-border pt-2 mt-1">{note}</p>}
    </div>
  );
}
