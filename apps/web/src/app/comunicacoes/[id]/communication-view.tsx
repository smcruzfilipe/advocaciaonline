"use client";

import Link from "next/link";
import {
  EntityReference,
  entityLabel,
  mediumLabel,
  ReadFeedback,
  useRead,
} from "../_components/consultation";
import { IdentityWarning } from "../_components/identity-warning";
import type { CommunicationDetail } from "../types";
import styles from "../consultation.module.css";

export function CommunicationView({ id }: { id: string }) {
  const { state, reload } = useRead<CommunicationDetail>(
    `/api/communications/${encodeURIComponent(id)}`,
  );

  return (
    <div className="page stack">
      <nav aria-label="Caminho da comunicação">
        <Link href="/comunicacoes" prefetch={false}>
          Voltar para comunicações
        </Link>
      </nav>
      <header className={styles.header}>
        <div>
          <h1>Detalhe da comunicação</h1>
          <p className="muted">
            Conteúdo da primeira versão persistida e vínculos autorizados.
          </p>
        </div>
        <button
          className="button-secondary"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading"
            ? "Atualizando…"
            : "Atualizar comunicação"}
        </button>
      </header>

      {state.status !== "ready" ? (
        <ReadFeedback state={state} retry={reload} label="a comunicação" />
      ) : (
        <>
          <IdentityWarning communication={state.data} />
          <section
            className="panel stack"
            aria-labelledby="communication-metadata"
          >
            <h2 id="communication-metadata">Identificação</h2>
            <dl className={styles.metadata}>
              <div>
                <dt>Tribunal de origem</dt>
                <dd>{state.data.court}</dd>
              </div>
              <div>
                <dt>Processo informado pela fonte</dt>
                <dd>
                  {state.data.process_number === undefined
                    ? "Não fornecido"
                    : state.data.process_number === ""
                      ? "Campo vazio na fonte"
                      : state.data.process_number}
                </dd>
              </div>
              <div>
                <dt>Fonte</dt>
                <dd>{state.data.source}</dd>
              </div>
              <div>
                <dt>Identidade da publicação</dt>
                <dd>
                  {state.data.identity_status === "pending"
                    ? "Pendente — possível duplicidade"
                    : "Completa"}
                </dd>
              </div>
              <div>
                <dt>Identificador interno</dt>
                <dd>
                  <code className={styles.identifier}>{state.data.id}</code>
                </dd>
              </div>
            </dl>
          </section>

          <section className="panel stack" aria-labelledby="source-content">
            <h2 id="source-content">Conteúdo fornecido pela fonte</h2>
            <p className="muted">
              A marcação eventualmente presente é exibida como texto, sem
              executar HTML. Campos ausentes não são completados com dados de
              monitoramentos.
            </p>
            {typeof state.data.payload.texto === "string" ? (
              state.data.payload.texto === "" ? (
                <p>O campo de texto foi fornecido vazio pela fonte.</p>
              ) : (
                <p className={styles.sourceText}>{state.data.payload.texto}</p>
              )
            ) : (
              <p>
                A fonte não forneceu o campo “texto” em formato textual. Os
                campos recebidos permanecem disponíveis abaixo.
              </p>
            )}
            <details className={styles.disclosure}>
              <summary>Todos os campos recebidos da fonte</summary>
              <pre className={styles.sourceJson}>
                {JSON.stringify(state.data.payload, null, 2)}
              </pre>
            </details>
          </section>

          <section
            className={styles.section}
            aria-labelledby="monitoring-links"
          >
            <h2 id="monitoring-links">Vínculos de monitoramento</h2>
            <p className="muted">
              Cada vínculo corresponde a um trabalho que encontrou esta
              comunicação. Somente vínculos autorizados são apresentados.
            </p>
            {state.data.links.length === 0 ? (
              <p className="panel" role="status">
                Nenhum vínculo disponível para consulta.
              </p>
            ) : (
              <ul className={styles.list}>
                {state.data.links.map((link) => (
                  <li className={styles.item} key={link.job_id}>
                    <h3>
                      {entityLabel(link.entity_type)} · {link.court}
                    </h3>
                    <dl className={styles.metadata}>
                      <div>
                        <dt>Monitoramento</dt>
                        <dd>
                          <EntityReference
                            type={link.entity_type}
                            id={link.entity_id}
                          />
                        </dd>
                      </div>
                      <div>
                        <dt>Tribunal</dt>
                        <dd>{link.court}</dd>
                      </div>
                      <div>
                        <dt>Meio</dt>
                        <dd>{mediumLabel(link.medium)}</dd>
                      </div>
                      <div>
                        <dt>Execução</dt>
                        <dd>
                          <code className={styles.identifier}>
                            {link.run_id}
                          </code>
                        </dd>
                      </div>
                      <div>
                        <dt>Trabalho</dt>
                        <dd>
                          <code className={styles.identifier}>
                            {link.job_id}
                          </code>
                        </dd>
                      </div>
                    </dl>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}
    </div>
  );
}
