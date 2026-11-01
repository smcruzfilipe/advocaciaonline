"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { authRequest } from "@/lib/api";

let verification: Promise<void> | undefined;

function verifyFragment(): Promise<void> {
  const fragment = new URLSearchParams(window.location.hash.slice(1));
  const token = fragment.get("token");
  if (!token)
    return (
      verification ??
      Promise.reject(
        new Error(
          "Link de confirmação ausente. Abra o link recebido por e-mail.",
        ),
      )
    );
  window.history.replaceState(
    window.history.state,
    "",
    `${window.location.pathname}${window.location.search}`,
  );
  verification = authRequest<{ verified: boolean }>("/api/auth/verify-email", {
    token,
  }).then((result) => {
    if (!result.verified)
      throw new Error(
        "Não foi possível confirmar o e-mail. Solicite um novo link de cadastro.",
      );
  });
  return verification;
}

export default function VerifyEmailPage() {
  const [status, setStatus] = useState<"pending" | "success" | "error">(
    "pending",
  );
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    void verifyFragment()
      .then(() => {
        if (active) setStatus("success");
      })
      .catch((reason: unknown) => {
        if (active) {
          setError(
            reason instanceof Error
              ? reason.message
              : "Não foi possível confirmar o e-mail.",
          );
          setStatus("error");
        }
      });
    return () => {
      active = false;
    };
  }, []);

  return (
    <section
      className="page access-page stack"
      aria-busy={status === "pending"}
    >
      <header className="stack">
        <span className="eyebrow">Acesso seguro</span>
        <h1>Confirmação de e-mail</h1>
      </header>
      {status === "pending" ? (
        <p role="status">Confirmando seu e-mail…</p>
      ) : status === "success" ? (
        <div className="notice stack" role="status">
          <p>
            E-mail confirmado. Entre com sua senha para configurar o
            autenticador e concluir o acesso. Se recebeu um convite, volte à aba
            em que o abriu ou reabra o link do convite antes de entrar.
          </p>
          <Link className="button" href="/login">
            Ir para o login
          </Link>
        </div>
      ) : (
        <div className="stack">
          <p className="error" role="alert">
            {error}
          </p>
          <p>
            O link pode ter expirado ou já ter sido usado. Abra-o no mesmo
            navegador usado no cadastro; se necessário, solicite novamente o
            cadastro neste navegador.
          </p>
          <Link className="button" href="/login">
            Ir para o acesso
          </Link>
        </div>
      )}
    </section>
  );
}
