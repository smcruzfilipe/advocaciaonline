import Icon from '@global/Icon';

export const displayName = 'Form Field';
export const shortDescription = 'Labeled form field with optional error state';

export default function FormField({
  label = 'Campo',
  hint = '',
  error = '',
  required = false,
  children = null,
}) {
  return (
    <div className="flex flex-col gap-1 font-body">
      <label className="text-sm font-medium text-foreground">
        {label}
        {required && <span className="text-error ml-1">*</span>}
      </label>
      {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      {children}
      {error && (
        <p className="text-xs text-error flex items-center gap-1 mt-0.5">
          <Icon i="alert-circle" size={12} />
          {error}
        </p>
      )}
    </div>
  );
}
