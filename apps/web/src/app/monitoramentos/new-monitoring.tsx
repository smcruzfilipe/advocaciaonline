"use client";

import Link from "next/link";
import { useState } from "react";
import { isCompleteMonitoring, monitoringConfig } from "./monitoring";
import type { MonitoringKind, MonitoringWriteResult } from "./monitoring";
import { MonitoringDetails } from "./monitoring-details";
import { MonitoringForm } from "./monitoring-form";
import styles from "./monitoramentos.module.css";

export function NewMonitoring({ kind }: { kind: MonitoringKind }) {
  const config = monitoringConfig[kind];
  const [saved, setSaved] = useState<{ result: MonitoringWriteResult }>();
  return (
    <div className={`page ${styles.page}`}>
      <nav aria-label="Caminho da página">
        <Link href="/monitoramentos">Monitoramentos</Link> / {config.newTitle}
      </nav>
      <header className={styles.header}>
        <div>
          <h1>{config.newTitle}</h1>
          <p className="muted">
            O cadastro pertence ao vínculo selecionado na sua sessão, definido
            pelo servidor.
          </p>
        </div>
      </header>
      {saved ? (
        <section
          className="panel stack"
          aria-labelledby="monitoring-created-title"
        >
          <h2 id="monitoring-created-title" role="status">
            Monitoramento cadastrado
          </h2>
          <p>
            O servidor confirmou o cadastro. A permissão de consultar o detalhe
            é avaliada separadamente.
          </p>
          {isCompleteMonitoring(saved.result) && (
            <MonitoringDetails record={saved.result} />
          )}
          <div className={styles.actions}>
            {saved.result?.id && (
              <Link
                className="button"
                href={`${config.path}/${encodeURIComponent(saved.result.id)}`}
              >
                Abrir cadastro
              </Link>
            )}
            <button
              className="button-secondary"
              type="button"
              onClick={() => setSaved(undefined)}
            >
              {kind === "party"
                ? "Cadastrar outra parte"
                : "Cadastrar outro processo"}
            </button>
            <Link href="/monitoramentos">Voltar aos monitoramentos</Link>
          </div>
        </section>
      ) : (
        <section
          className="panel stack"
          aria-label="Dados do novo monitoramento"
        >
          <p className={styles.help}>
            Um alvo desativado continua cadastrado. Se houver duplicidade, edite
            ou reative o existente em vez de criar outro.
          </p>
          <MonitoringForm
            kind={kind}
            onSaved={(result) => setSaved({ result })}
          />
        </section>
      )}
    </div>
  );
}
