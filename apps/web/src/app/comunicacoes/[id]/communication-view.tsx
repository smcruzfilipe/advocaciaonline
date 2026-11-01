"use client";

import Link from "next/link";
import { Badge, Btn, EmptyState, Icon, PageShell } from "@/components/ui";
import {
  EntityReference,
  entityLabel,
  mediumLabel,
  ReadFeedback,
  useRead,
} from "../_components/consultation";
import { IdentityWarning } from "../_components/identity-warning";
import type { CommunicationDetail } from "../types";
import {
  processLabel,
  processLink,
  publicationDate,
  publicationContent,
  sourceField,
} from "../detail-presentation.mjs";
import styles from "../consultation.module.css";

export function CommunicationView({ id }: { id: string }) {
  const { state, reload } = useRead<CommunicationDetail>(
    `/api/communications/${encodeURIComponent(id)}`,
  );
  const publicationLink =
    state.status === "ready" ? processLink(state.data.payload) : undefined;
  return (
    <PageShell maxWidth="max-w-3xl">
      <nav
        aria-label="Caminho da comunicação"
        className="mb-6 flex items-center gap-2 text-sm text-muted-foreground"
      >
        <Link
          className="text-accent underline"
          href="/comunicacoes"
          prefetch={false}
        >
          Comunicações
        </Link>
        <Icon i="chevron-right" size={13} />
        <span>Detalhe</span>
      </nav>
      <header className="mb-6 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold font-headings text-foreground">
            Detalhe da comunicação
          </h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Conteúdo da primeira versão persistida e vínculos autorizados.
          </p>
        </div>
        <Btn
          variant="secondary"
          size="sm"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading"
            ? "Atualizando…"
            : "Atualizar comunicação"}
        </Btn>
      </header>
      {state.status !== "ready" ? (
        <ReadFeedback state={state} retry={reload} label="a comunicação" />
      ) : (
        <div className="flex flex-col gap-6">
          <IdentityWarning communication={state.data} />
          <section
            className="flex flex-col gap-3 border border-border p-5"
            aria-labelledby="communication-metadata"
          >
            <div className="flex flex-wrap items-start justify-between gap-3">
              <h2 id="communication-metadata" className="text-sm font-medium">
                Identificação
              </h2>
              <Badge
                label={
                  state.data.identity_status === "pending"
                    ? "Pendente — possível duplicidade"
                    : "Identidade completa"
                }
                variant={
                  state.data.identity_status === "pending" ? "warning" : "muted"
                }
              />
            </div>
            <dl className={styles.metadata}>
              <div>
                <dt>Tribunal de origem</dt>
                <dd>{state.data.court}</dd>
              </div>
              <div>
                <dt>Processo informado pela fonte</dt>
                <dd className="font-mono">
                  {processLabel(state.data.payload, state.data.process_number)}
                </dd>
              </div>
              <div>
                <dt>Órgão</dt>
                <dd>{sourceField(state.data.payload, "nomeOrgao")}</dd>
              </div>
              <div>
                <dt>Classe</dt>
                <dd>{sourceField(state.data.payload, "nomeClasse")}</dd>
              </div>
              <div>
                <dt>Tipo de comunicação</dt>
                <dd>{sourceField(state.data.payload, "tipoComunicacao")}</dd>
              </div>
              <div>
                <dt>Data de disponibilização</dt>
                <dd>{publicationDate(state.data.payload)}</dd>
              </div>
              <div>
                <dt>Link</dt>
                <dd>
                  {publicationLink ? (
                    <a
                      className="text-accent underline break-words"
                      href={publicationLink}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      Consultar processo
                    </a>
                  ) : (
                    "Não fornecido"
                  )}
                </dd>
              </div>
            </dl>
          </section>
          <section
            className="flex flex-col gap-2"
            aria-labelledby="source-content"
          >
            <h2
              id="source-content"
              className="text-sm font-medium text-foreground"
            >
              Conteúdo da publicação
            </h2>
            <div className="border border-border bg-input p-5 text-sm leading-relaxed">
              {typeof state.data.payload.texto === "string" ? (
                state.data.payload.texto.trim() === "" ? (
                  <p>O campo de texto foi fornecido vazio pela fonte.</p>
                ) : (
                  <p className="whitespace-pre-wrap break-words">
                    {publicationContent(state.data.payload).map(
                      (part, index) =>
                        part.href ? (
                          <a
                            key={index}
                            className="text-accent underline break-words"
                            href={part.href}
                            target="_blank"
                            rel="noopener noreferrer"
                          >
                            {part.text}
                          </a>
                        ) : (
                          part.text
                        ),
                    )}
                  </p>
                )
              ) : (
                <p>A fonte não forneceu o campo “texto” em formato textual.</p>
              )}
            </div>
          </section>
          <section
            className="flex flex-col gap-3"
            aria-labelledby="monitoring-links"
          >
            <h2 id="monitoring-links" className="text-sm font-medium">
              Monitoramentos associados
            </h2>
            <p className="text-xs text-muted-foreground">
              Cada vínculo corresponde a um trabalho que encontrou esta
              comunicação. Somente vínculos autorizados são apresentados.
            </p>
            {state.data.links.length === 0 ? (
              <div className="border border-border">
                <EmptyState
                  icon="link"
                  title="Nenhum vínculo disponível para consulta"
                />
              </div>
            ) : (
              <ul className={styles.list}>
                {state.data.links.map((link) => (
                  <li className={styles.item} key={link.job_id}>
                    <h3 className="text-sm font-medium">
                      {entityLabel(link.entity_type)} · {link.court}
                    </h3>
                    <dl className={styles.metadata}>
                      <div>
                        <dt>Monitoramento</dt>
                        <dd>
                          <EntityReference
                            type={link.entity_type}
                            id={link.entity_id}
                            showIdentifier={false}
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
                    </dl>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      )}
    </PageShell>
  );
}
