export const displayName = 'Text Input';
export const shortDescription = 'Styled div mimicking a text input';

export default function TextInput({
  value = '',
  placeholder = '',
  hasError = false,
  disabled = false,
}) {
  return (
    <div
      className={`border px-3 py-2 text-sm font-body bg-input text-foreground
        ${hasError ? 'border-error' : 'border-border'}
        ${disabled ? 'opacity-50' : ''}
      `}
    >
      {value || <span className="text-muted-foreground">{placeholder}</span>}
    </div>
  );
}
