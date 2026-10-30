export type SourceValue =
  | string
  | number
  | boolean
  | null
  | SourceValue[]
  | { [key: string]: SourceValue };

export type Communication = {
  id: string;
  source: string;
  court: string;
  identity_status: "complete" | "pending";
  warning: string | null;
  process_number?: string;
};

export type CommunicationList = {
  courts: { court: string; communications: Communication[] }[];
};

export type MonitoringLink = {
  job_id: string;
  run_id: string;
  entity_type: string;
  entity_id: string;
  court: string;
  medium: string;
};

export type CommunicationDetail = Communication & {
  payload: { [key: string]: SourceValue };
  links: MonitoringLink[];
};
