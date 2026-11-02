import Icon from '@global/Icon';

export const displayName = 'Alert Banner';
export const shortDescription = 'Inline alert for warnings, errors, success, info';

const styles = {
  warning: 'bg-warning-bg border-warning text-warning',
  error: 'bg-error-bg border-error text-error',
  success: 'bg-success-bg border-success text-success',
  info: 'bg-info-bg border-info text-info',
};

const icons = {
  warning: 'alert-triangle',
  error: 'alert-circle',
  success: 'check-circle',
  info: 'info',
};

export default function AlertBanner({ variant = 'info', children = 'Mensagem informativa.' }) {
  return (
    <div className={`flex items-start gap-3 border px-4 py-3 text-sm font-body ${styles[variant] || styles.info}`}>
      <Icon i={icons[variant] || 'info'} size={16} className="mt-0.5 flex-shrink-0" />
      <div>{children}</div>
    </div>
  );
}
