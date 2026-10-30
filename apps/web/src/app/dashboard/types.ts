import type { MetricValue } from "./presentation.mjs";

export type DashboardPeriod = {
  start: string;
  end: string;
  communications: MetricValue;
  processes: MetricValue;
};

export type DashboardSnapshot = {
  timezone: string;
  as_of: string;
  state:
    | "succeeded"
    | "partial"
    | "running"
    | "failed"
    | "no_work"
    | "unavailable"
    | "masked";
  periods: Record<"today" | "week" | "last_seven_days", DashboardPeriod>;
  courts: { court: string; state: string }[];
  warnings: { court: string; code: string }[];
};
