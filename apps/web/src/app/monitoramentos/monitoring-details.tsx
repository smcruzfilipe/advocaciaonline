import { courtDescription, monitoringName } from "./monitoring";
import type { Monitoring } from "./monitoring";
import { Badge } from "@/components/ui";

export function MonitoringDetails({ record }: { record: Monitoring }) {
  return (
    <dl className="grid gap-4 sm:grid-cols-2 text-sm [&_dt]:text-xs [&_dt]:text-muted-foreground [&_dd]:mt-0.5 [&_dd]:break-words">
      <div>
        <dt>{"name" in record ? "Nome da parte" : "Número CNJ"}</dt>
        <dd className="tabular-nums">{monitoringName(record)}</dd>
      </div>
      <div>
        <dt>Situação</dt>
        <dd>
          <Badge
            label={record.active ? "Ativo" : "Inativo"}
            variant={record.active ? "active" : "inactive"}
          />
        </dd>
      </div>
      <div>
        <dt>Tribunais</dt>
        <dd>{courtDescription(record.courts)}</dd>
      </div>
      <div>
        <dt>Identificador do monitoramento</dt>
        <dd className="break-all tabular-nums">{record.id}</dd>
      </div>
    </dl>
  );
}
