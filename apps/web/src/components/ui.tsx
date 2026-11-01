import type { ButtonHTMLAttributes, ReactNode } from "react";
import {
  AlertCircle,
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  Building2,
  Calendar,
  Check,
  CheckCircle,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Clock,
  Copy,
  ExternalLink,
  Eye,
  FileText,
  FileX,
  Filter,
  Folder,
  History,
  Inbox,
  Info,
  Link,
  Loader2,
  Lock,
  Mail,
  Menu,
  MoreHorizontal,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Send,
  Settings,
  Shield,
  Trash2,
  User,
  UserPlus,
  Users,
  X,
  type LucideIcon,
} from "lucide-react";

const icons: Record<string, LucideIcon> = {
  "alert-circle": AlertCircle,
  "alert-triangle": AlertTriangle,
  "arrow-left": ArrowLeft,
  "arrow-right": ArrowRight,
  "building-2": Building2,
  calendar: Calendar,
  check: Check,
  "check-circle": CheckCircle,
  "chevron-down": ChevronDown,
  "chevron-left": ChevronLeft,
  "chevron-right": ChevronRight,
  "chevron-up": ChevronUp,
  clock: Clock,
  copy: Copy,
  "external-link": ExternalLink,
  eye: Eye,
  "file-text": FileText,
  folder: Folder,
  history: History,
  "file-x": FileX,
  link: Link,
  send: Send,
  filter: Filter,
  inbox: Inbox,
  info: Info,
  "loader-2": Loader2,
  lock: Lock,
  mail: Mail,
  menu: Menu,
  "more-horizontal": MoreHorizontal,
  pencil: Pencil,
  plus: Plus,
  "refresh-cw": RefreshCw,
  search: Search,
  settings: Settings,
  shield: Shield,
  "trash-2": Trash2,
  user: User,
  "user-plus": UserPlus,
  users: Users,
  x: X,
};

export function Icon({
  i,
  size = 16,
  className = "",
}: {
  i: string;
  size?: number;
  className?: string;
}) {
  const Component = icons[i];
  if (!Component) throw new Error(`Ícone não registrado: ${i}`);
  return <Component size={size} className={className} aria-hidden="true" />;
}

const buttonVariants = {
  primary: "bg-primary text-primary-foreground border border-primary",
  secondary: "bg-background text-foreground border border-border",
  ghost: "bg-transparent text-muted-foreground border border-transparent",
  danger: "bg-error text-primary-foreground border border-error",
  accent: "bg-accent text-accent-foreground border border-accent",
};
const buttonSizes = {
  sm: "px-3 py-1.5 text-xs",
  md: "px-4 py-2 text-sm",
  lg: "px-5 py-2.5 text-base",
};
export function Btn({
  children,
  variant = "primary",
  size = "md",
  icon,
  className = "",
  type = "button",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: keyof typeof buttonVariants;
  size?: keyof typeof buttonSizes;
  icon?: string;
}) {
  return (
    <button
      type={type}
      className={`inline-flex items-center gap-2 font-medium font-body ${buttonVariants[variant]} ${buttonSizes[size]} disabled:opacity-40 ${className}`}
      {...props}
    >
      {icon && <Icon i={icon} size={14} />}
      {children}
    </button>
  );
}

const alertStyles = {
  warning: "bg-warning-bg border-warning text-warning",
  error: "bg-error-bg border-error text-error",
  success: "bg-success-bg border-success text-success",
  info: "bg-info-bg border-info text-info",
};
const alertIcons = {
  warning: "alert-triangle",
  error: "alert-circle",
  success: "check-circle",
  info: "info",
};
export function AlertBanner({
  variant = "info",
  children,
}: {
  variant?: keyof typeof alertStyles;
  children: ReactNode;
}) {
  return (
    <div
      role={variant === "error" ? "alert" : "status"}
      className={`flex items-start gap-3 border px-4 py-3 text-sm font-body ${alertStyles[variant]}`}
    >
      <Icon
        i={alertIcons[variant]}
        size={16}
        className="mt-0.5 flex-shrink-0"
      />
      <div>{children}</div>
    </div>
  );
}

const badgeStyles: Record<string, string> = {
  success: "bg-success-bg text-success border border-success",
  active: "bg-success-bg text-success border border-success",
  warning: "bg-warning-bg text-warning border border-warning",
  error: "bg-error-bg text-error border border-error",
  info: "bg-info-bg text-info border border-info",
  muted: "bg-muted text-muted-foreground border border-border",
  inactive: "bg-muted text-muted-foreground border border-border",
};
export function Badge({
  label,
  variant = "muted",
}: {
  label: ReactNode;
  variant?: string;
}) {
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 text-xs font-medium ${badgeStyles[variant] ?? badgeStyles.muted}`}
    >
      {label}
    </span>
  );
}
export function FormField({
  label,
  hint,
  error,
  required,
  children,
  htmlFor,
}: {
  label: ReactNode;
  hint?: ReactNode;
  error?: ReactNode;
  required?: boolean;
  children: ReactNode;
  htmlFor?: string;
}) {
  return (
    <div className="flex flex-col gap-1 font-body">
      <label htmlFor={htmlFor} className="text-sm font-medium text-foreground">
        {label}
        {required && <span className="text-error ml-1">*</span>}
      </label>
      {hint && (
        <p
          id={htmlFor ? `${htmlFor}-hint` : undefined}
          className="text-xs text-muted-foreground"
        >
          {hint}
        </p>
      )}
      {children}
      {error && (
        <p
          id={htmlFor ? `${htmlFor}-error` : undefined}
          className="text-xs text-error flex items-center gap-1 mt-0.5"
        >
          <Icon i="alert-circle" size={12} />
          {error}
        </p>
      )}
    </div>
  );
}
export function PageShell({
  children,
  maxWidth = "max-w-5xl",
}: {
  children: ReactNode;
  maxWidth?: string;
}) {
  return (
    <div
      className={`w-full ${maxWidth} mx-auto px-4 py-5 md:px-8 md:py-8 font-body`}
    >
      {children}
    </div>
  );
}
export function SectionHeader({
  title,
  subtitle,
  action,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="flex items-start justify-between gap-4 mb-4 font-body">
      <div>
        <h2 className="text-lg font-semibold text-foreground font-headings">
          {title}
        </h2>
        {subtitle && (
          <p className="text-sm text-muted-foreground mt-0.5">{subtitle}</p>
        )}
      </div>
      {action && <div className="flex-shrink-0">{action}</div>}
    </div>
  );
}
export function EmptyState({
  icon = "inbox",
  title,
  description,
  action,
}: {
  icon?: string;
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-16 gap-3 font-body text-center">
      <div className="text-muted-foreground">
        <Icon i={icon} size={36} />
      </div>
      <p className="text-base font-medium text-foreground">{title}</p>
      {description && (
        <p className="text-sm text-muted-foreground max-w-xs">{description}</p>
      )}
      {action}
    </div>
  );
}
const metricStyles: Record<string, string> = {
  value: "text-foreground",
  loading: "text-muted-foreground",
  error: "text-error",
  restricted: "text-muted-foreground",
  partial: "text-warning",
};
export function MetricCard({
  label,
  value,
  period,
  state = "value",
  note,
}: {
  label: ReactNode;
  value: ReactNode;
  period: ReactNode;
  state?: string;
  note?: ReactNode;
}) {
  return (
    <div className="border border-border bg-background p-5 flex flex-col gap-2 font-body">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p
        className={`text-3xl font-semibold font-headings ${metricStyles[state] ?? metricStyles.value}`}
      >
        {state === "restricted" ? "*" : state === "loading" ? "—" : value}
      </p>
      <p className="text-xs text-muted-foreground">{period}</p>
      {note && (
        <p className="text-xs text-muted-foreground border-t border-border pt-2 mt-1">
          {note}
        </p>
      )}
    </div>
  );
}
