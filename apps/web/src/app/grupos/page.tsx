"use client";

import Link from "next/link";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import { api, ApiError } from "@/lib/api";
import { ErrorNotice, PolicyNotice } from "../equipe/admin-ui";
import { operationLabel, type AuthorizationGroup } from "./types";
import { Badge, PageShell, EmptyState } from "@/components/ui";

export default function GroupsPage() {
  const [groups, setGroups] = useState<AuthorizationGroup[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<unknown>(null);
  const [created, setCreated] = useState<AuthorizationGroup | null>(null);

  const load = useCallback(
    () =>
      api<{ groups: AuthorizationGroup[] }>("/api/authorization/groups")
        .then(
          (result) => {
            setGroups(result.groups);
            setError(null);
          },
          (caught: unknown) => {
            setError(caught);
            setGroups(null);
          },
        )
        .finally(() => setLoading(false)),
    [],
  );

  useEffect(() => {
    void load();
  }, [load]);

  function reload() {
    setLoading(true);
    return load();
  }

  async function create(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setFormError(null);
    setCreated(null);
    try {
      if (!name.trim()) throw new Error("Informe um nome de grupo válido.");
      const group = await api<AuthorizationGroup>("/api/authorization/groups", {
        method: "POST",
        body: { name },
      });
      setGroups((current) =>
        [...(current ?? []), group].sort((a, b) =>
          a.name.localeCompare(b.name, "pt-BR"),
        ),
      );
      setCreated(group);
      setName("");
    } catch (caught) {
      setFormError(caught);
    } finally {
      setSaving(false);
    }
  }

  return (
    <PageShell maxWidth="max-w-4xl">
      <header className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold font-headings text-foreground">
            Grupos e permissões
          </h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Regras por operação e tribunal, aplicadas à equipe pelo servidor.
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Link
            className="border border-border px-3 py-2 text-sm"
            href="/equipe"
          >
            Equipe e credenciais
          </Link>
          <a
            className="bg-primary text-primary-foreground px-3 py-2 text-sm"
            href="#new-group-heading"
          >
            Novo grupo
          </a>
          <button
            className="border border-border px-3 py-2 text-sm disabled:opacity-50"
            type="button"
            disabled={loading || saving}
            onClick={() => {
              void reload();
            }}
          >
            Atualizar grupos
          </button>
        </div>
      </header>
      <PolicyNotice />
      {loading && <p role="status">Carregando grupos…</p>}
      {error != null && (
        <ErrorNotice
          error={error}
          onRetry={
            !loading && !saving
              ? () => {
                  void reload();
                }
              : undefined
          }
        />
      )}
      {groups !== null && (
        <>
          <section
            className="mb-6 flex flex-col gap-6"
            aria-labelledby="groups-heading"
            aria-busy={loading}
          >
            <h2 id="groups-heading" className="sr-only">
              Grupos do ambiente
            </h2>
            {groups.length === 0 ? (
              <EmptyState
                icon="users"
                title="Nenhum grupo criado"
                description="Crie grupos para organizar permissões de equipe. Sem grupos, membros têm apenas leituras padrão."
              />
            ) : (
              <ul className="flex flex-col gap-6">
                {groups.map((group) => (
                  <li className="border border-border" key={group.id}>
                    <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-3.5 border-b border-border bg-secondary">
                      <div className="flex items-center gap-3">
                        <h3 className="text-sm font-semibold text-foreground">
                          <Link href={`/grupos/${group.id}`}>{group.name}</Link>
                        </h3>
                        <span className="text-xs text-muted-foreground">
                          {group.membership_ids.length} membro(s)
                        </span>
                      </div>
                      <Link
                        className="border border-border px-3 py-1.5 bg-background text-sm"
                        href={`/grupos/${group.id}`}
                      >
                        Gerenciar grupo
                      </Link>
                    </div>
                    {group.rules.length === 0 ? (
                      <p className="px-5 py-4 text-sm text-muted-foreground">
                        Sem regras. Associar uma pessoa a um grupo sem
                        concessões não preserva as leituras padrão de quem não
                        tem grupos.
                      </p>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full text-left text-sm">
                          <thead className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
                            <tr>
                              <th className="px-5 py-2.5">Operação</th>
                              <th className="px-5 py-2.5">Permissão</th>
                              <th className="px-5 py-2.5">Tribunal / escopo</th>
                            </tr>
                          </thead>
                          <tbody>
                            {group.rules.map((rule, index) => (
                              <tr
                                key={rule.id}
                                className={`border-t border-border ${index % 2 ? "bg-table-row-alt" : "bg-background"}`}
                              >
                                <td className="px-5 py-3">
                                  {operationLabel(rule.operation)}
                                </td>
                                <td className="px-5 py-3">
                                  <Badge
                                    label={
                                      rule.effect === "allow"
                                        ? "Permitida"
                                        : "Negada"
                                    }
                                    variant={
                                      rule.effect === "allow"
                                        ? "active"
                                        : "error"
                                    }
                                  />
                                </td>
                                <td className="px-5 py-3 text-muted-foreground">
                                  {rule.court ??
                                    (rule.operation === "consultar_comunicacoes"
                                      ? "Todos os tribunais"
                                      : "Ambiente do advogado")}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                    <div className="border-t border-border px-5 py-3.5 flex flex-wrap justify-between gap-3 text-xs">
                      <span className="text-muted-foreground">
                        {group.rules.length} regra(s) ·{" "}
                        {group.membership_ids.length} vínculo(s) associado(s)
                      </span>
                      <Link
                        href={`/grupos/${group.id}`}
                        className="text-accent underline"
                      >
                        Editar regras e membros
                      </Link>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section
            className="border border-border p-5 flex flex-col gap-4"
            aria-labelledby="new-group-heading"
          >
            <h2
              id="new-group-heading"
              className="text-base font-semibold font-headings"
              tabIndex={-1}
            >
              Criar grupo
            </h2>
            {created && (
              <div
                className="border border-success bg-success-bg p-3 text-sm"
                role="status"
              >
                Grupo “{created.name}” criado, ainda sem regras e sem membros.{" "}
                <Link href={`/grupos/${created.id}`}>
                  Definir regras e associações
                </Link>
                .
              </div>
            )}
            {formError != null && (
              <ErrorNotice error={formError} id="create-group-error" />
            )}
            <form
              className="flex flex-col gap-4"
              onSubmit={create}
              aria-busy={saving}
              aria-describedby={
                formError != null ? "create-group-error" : undefined
              }
            >
              <div className="flex flex-col gap-1.5 text-sm">
                <label htmlFor="group-name">Nome do grupo (obrigatório)</label>
                <input
                  className="border border-border bg-input px-3 py-2 text-sm w-full"
                  id="group-name"
                  required
                  maxLength={120}
                  value={name}
                  disabled={saving || loading}
                  onChange={(event) => setName(event.target.value)}
                  aria-invalid={
                    formError instanceof ApiError &&
                    [409, 422].includes(formError.status)
                  }
                  aria-describedby={`group-name-help${formError != null ? " create-group-error" : ""}`}
                />
                <p
                  id="group-name-help"
                  className="text-xs text-muted-foreground"
                >
                  Até 120 caracteres. Não pode repetir outro nome do mesmo
                  ambiente, mesmo com diferença de maiúsculas.
                </p>
              </div>
              <div>
                <button
                  type="submit"
                  className="bg-primary text-primary-foreground px-4 py-2 text-sm disabled:opacity-50"
                  disabled={saving || loading}
                >
                  {saving ? "Criando grupo…" : "Criar grupo"}
                </button>
              </div>
            </form>
          </section>
        </>
      )}
    </PageShell>
  );
}
