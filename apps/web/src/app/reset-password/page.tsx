"use client";

import { useEffect, useState } from "react";
import { PasswordResetConfirmation } from "@/components/password-reset-confirmation";
import { PasswordResetRequest } from "@/components/password-reset-request";
import { AlertBanner } from "@/components/ui";

type ResetState =
  | {
      view: "loading" | "request" | "invalid" | "success";
      generation: number;
    }
  | { view: "confirm"; token: string; generation: number };

export default function ResetPasswordPage() {
  const [state, setState] = useState<ResetState>({
    view: "loading",
    generation: 0,
  });

  useEffect(() => {
    function captureFragment() {
      if (!window.location.hash) {
        // Strict Mode repeats this effect after the first capture erased the URL.
        setState((current) =>
          current.view === "loading"
            ? { view: "request", generation: current.generation }
            : current,
        );
        return;
      }
      const fragment = new URLSearchParams(window.location.hash.slice(1));
      const token = fragment.get("token");
      window.history.replaceState(
        window.history.state,
        "",
        `${window.location.pathname}${window.location.search}`,
      );
      setState((current) => {
        const generation = current.generation + 1;
        if (token === null) return { view: "request", generation };
        if (!/^[A-Za-z0-9_-]{43}$/.test(token))
          return { view: "invalid", generation };
        return { view: "confirm", token, generation };
      });
    }

    window.addEventListener("hashchange", captureFragment);
    captureFragment();
    return () => window.removeEventListener("hashchange", captureFragment);
  }, []);

  function finish(view: "success" | "invalid", generation: number) {
    // Ignore an older submission if another email link was opened meanwhile.
    setState((current) =>
      current.generation === generation ? { view, generation } : current,
    );
  }

  return (
    <section
      className="mx-auto flex w-full max-w-sm flex-col gap-6 px-4 py-20 text-sm"
      aria-busy={state.view === "loading"}
    >
      <header>
        <h1 className="mb-2 font-headings text-2xl font-semibold text-foreground">
          {state.view === "confirm"
            ? "Escolha sua nova senha"
            : "Redefinir senha"}
        </h1>
        <p className="text-sm text-muted-foreground">
          A redefinição altera apenas sua senha. O autenticador continua
          obrigatório para entrar na conta.
        </p>
      </header>
      {state.view === "loading" ? (
        <p role="status">Abrindo redefinição de senha…</p>
      ) : state.view === "request" ? (
        <PasswordResetRequest key={state.generation} />
      ) : state.view === "confirm" ? (
        <PasswordResetConfirmation
          key={state.generation}
          token={state.token}
          onSuccess={() => finish("success", state.generation)}
          onInvalid={() => finish("invalid", state.generation)}
        />
      ) : state.view === "success" ? (
        <div
          className="flex flex-col gap-4 border border-border p-6"
          role="status"
        >
          <h2 className="font-semibold">Senha alterada</h2>
          <p>
            Entre com sua nova senha e o código do seu autenticador. As sessões
            anteriores foram encerradas; seu autenticador não foi alterado.
          </p>
        </div>
      ) : (
        <AlertBanner variant="error">
          Este link é inválido, expirou ou já foi utilizado. Solicite um novo
          link para redefinir sua senha.
        </AlertBanner>
      )}
      {(state.view === "invalid" || state.view === "confirm") && (
        <button
          className="border border-border bg-background px-4 py-2 text-sm font-medium"
          type="button"
          onClick={() =>
            setState((current) => ({
              view: "request",
              generation: current.generation + 1,
            }))
          }
        >
          Solicitar novo link
        </button>
      )}
      {/* Reload the session after a reset instead of reusing a revoked identity. */}
      <a className="text-center text-xs text-accent underline" href="/login">
        Ir para o login
      </a>
    </section>
  );
}
