export type MetricValue = number | '*' | null;
export function statePresentation(state: string): { label: string; description: string };
export function metricPresentation(value: MetricValue, masked?: boolean): { value: string; note: string };
