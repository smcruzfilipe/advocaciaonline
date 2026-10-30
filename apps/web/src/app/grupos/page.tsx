"use client";

import Link from "next/link";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import { api, ApiError } from "@/lib/api";
import { ErrorNotice, PolicyNotice } from "../equipe/admin-ui";
import type { AuthorizationGroup } from "./types";
import styles from "../equipe/admin.module.css";

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
    <div className="page stack">
      <header className={styles.header}>
        <div className="stack">
          <h1>Grupos e permissões</h1>
          <p className="muted">
            Regras por operação e tribunal, aplicadas à equipe pelo servidor.
          </p>
        </div>
        <div className="row">
          <Link className="button-secondary" href="/equipe">
            Equipe e credenciais
          </Link>
          <button
            className="button-secondary"
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
            className="panel stack"
            aria-labelledby="groups-heading"
            aria-busy={loading}
          >
            <h2 id="groups-heading">Grupos do ambiente</h2>
            {groups.length === 0 ? (
              <p>
                Nenhum grupo criado. Crie um grupo para definir concessões e
                negações da equipe.
              </p>
            ) : (
              <ul className={styles.list}>
                {groups.map((group) => (
                  <li className={`${styles.item} stack`} key={group.id}>
                    <div className={styles.header}>
                      <h3>
                        <Link href={`/grupos/${group.id}`}>{group.name}</Link>
                      </h3>
                      <Link
                        className="button-secondary"
                        href={`/grupos/${group.id}`}
                      >
                        Gerenciar grupo
                      </Link>
                    </div>
                    <p className="muted">
                      {group.rules.length}{" "}
                      {group.rules.length === 1 ? "regra" : "regras"} ·{" "}
                      {group.membership_ids.length}{" "}
                      {group.membership_ids.length === 1
                        ? "vínculo associado"
                        : "vínculos associados"}
                    </p>
                    {group.rules.length === 0 && (
                      <p>
                        Sem regras. Associar uma pessoa a um grupo sem
                        concessões não preserva as leituras padrão de quem não
                        tem grupos.
                      </p>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section className="panel stack" aria-labelledby="new-group-heading">
            <h2 id="new-group-heading">Criar grupo</h2>
            {created && (
              <div className="notice" role="status">
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
              className={styles.form}
              onSubmit={create}
              aria-busy={saving}
              aria-describedby={
                formError != null ? "create-group-error" : undefined
              }
            >
              <div className="field">
                <label htmlFor="group-name">Nome do grupo (obrigatório)</label>
                <input
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
                <p id="group-name-help" className="muted">
                  Até 120 caracteres. Não pode repetir outro nome do mesmo
                  ambiente, mesmo com diferença de maiúsculas.
                </p>
              </div>
              <div>
                <button
                  type="submit"
                  className="button"
                  disabled={saving || loading}
                >
                  {saving ? "Criando grupo…" : "Criar grupo"}
                </button>
              </div>
            </form>
          </section>
        </>
      )}
    </div>
  );
}
