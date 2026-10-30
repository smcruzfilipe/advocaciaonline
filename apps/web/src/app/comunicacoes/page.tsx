"use client";

import Link from "next/link";
import { ReadFeedback, useRead } from "./_components/consultation";
import { IdentityWarning } from "./_components/identity-warning";
import type { CommunicationList } from "./types";
import styles from "./consultation.module.css";

export default function CommunicationsPage() {
  const { state, reload } = useRead<CommunicationList>("/api/communications");

  return (
    <div className="page stack">
      <header className={styles.header}>
        <div>
          <h1>Comunicações</h1>
          <p className="muted">
            Publicações independentes, organizadas por tribunal e limitadas ao
            seu acesso.
          </p>
        </div>
        <button
          className="button-secondary"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading"
            ? "Atualizando…"
            : "Atualizar comunicações"}
        </button>
      </header>

      {state.status !== "ready" ? (
        <ReadFeedback state={state} retry={reload} label="comunicações" />
      ) : (
        <>
          <p className="notice">
            Esta lista reúne o que já foi persistido. A presença ou ausência de
            comunicações não confirma que a coleta foi concluída.{" "}
            <Link href="/dashboard" prefetch={false}>
              Consultar estado da coleta
            </Link>
            .
          </p>
          {state.data.courts.length === 0 ? (
            <section className="panel stack" role="status">
              <h2>Nenhuma comunicação disponível</h2>
              <p>
                Não há comunicações persistidas que seu vínculo possa consultar
                neste contexto. Isso não significa coleta concluída nem zero
                publicações na fonte.
              </p>
            </section>
          ) : (
            state.data.courts.map((group) => (
              <section
                key={group.court}
                aria-label={`Comunicações de ${group.court}`}
              >
                <h2 className={styles.courtHeading}>{group.court}</h2>
                <ul className={styles.list}>
                  {group.communications.map((communication) => (
                    <li className={styles.item} key={communication.id}>
                      <div className={styles.header}>
                        <h3>
                          {communication.process_number === undefined
                            ? "Número de processo não fornecido pela fonte"
                            : communication.process_number === ""
                              ? "Número de processo vazio na fonte"
                              : communication.process_number}
                        </h3>
                        <span className={styles.badge}>
                          {communication.identity_status === "pending"
                            ? "Identidade pendente"
                            : "Identidade completa"}
                        </span>
                      </div>
                      <p className="muted">Fonte: {communication.source}</p>
                      <IdentityWarning communication={communication} />
                      <div className="row">
                        <Link
                          href={`/comunicacoes/${encodeURIComponent(communication.id)}`}
                          prefetch={false}
                        >
                          Abrir comunicação
                          <span className={styles.visuallyHidden}>
                            {" "}
                            {communication.id}
                          </span>
                        </Link>
                        <code className={styles.identifier}>
                          {communication.id}
                        </code>
                      </div>
                    </li>
                  ))}
                  {group.communications.length === 0 && (
                    <li className={styles.item}>
                      Nenhuma comunicação disponível neste tribunal.
                    </li>
                  )}
                </ul>
              </section>
            ))
          )}
        </>
      )}
    </div>
  );
}
