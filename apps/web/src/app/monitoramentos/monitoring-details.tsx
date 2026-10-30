import { courtDescription, monitoringName } from "./monitoring";
import type { Monitoring } from "./monitoring";
import styles from "./monitoramentos.module.css";

export function MonitoringDetails({ record }: { record: Monitoring }) {
  return (
    <dl className={styles.details}>
      <div>
        <dt>{"name" in record ? "Nome da parte" : "Número CNJ"}</dt>
        <dd className={styles.identifier}>{monitoringName(record)}</dd>
      </div>
      <div>
        <dt>Situação</dt>
        <dd>
          <span className={styles.status}>
            {record.active ? "Ativo" : "Desativado"}
          </span>
        </dd>
      </div>
      <div>
        <dt>Tribunais</dt>
        <dd>{courtDescription(record.courts)}</dd>
      </div>
      <div>
        <dt>Identificador do monitoramento</dt>
        <dd className={styles.identifier}>{record.id}</dd>
      </div>
    </dl>
  );
}
