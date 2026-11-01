"use client";

import { useRef, useState, type FormEvent } from "react";
import { ApiError, authRequest } from "@/lib/api";

export function PasswordResetRequest() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submitting = useRef(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting.current) return;
    submitting.current = true;
    setWorking(true);
    setError(null);
    try {
      await authRequest("/api/auth/password-reset", { email });
      setEmail("");
      setSent(true);
    } catch (reason) {
      setError(
        reason instanceof ApiError &&
          ["network_error", "backend_unavailable"].includes(reason.code)
          ? "Não foi possível confirmar a solicitação. Confira seu e-mail; se não receber o link, tente novamente em instantes."
          : reason instanceof Error
            ? reason.message
            : "Não foi possível solicitar o link. Tente novamente.",
      );
    } finally {
      submitting.current = false;
      setWorking(false);
    }
  }

  if (sent) {
    return (
      <div className="panel stack">
        <div className="stack" role="status">
          <h2>Confira seu e-mail</h2>
          <p>
            Se houver uma conta confirmada para este endereço, você receberá um
            link para redefinir sua senha. Confira também a pasta de spam.
          </p>
          <p>
            O link expira em 30 minutos e só pode ser usado uma vez. Uma nova
            solicitação invalida o link anterior.
          </p>
        </div>
        <button
          className="button-secondary"
          type="button"
          onClick={() => setSent(false)}
        >
          Solicitar outro link
        </button>
      </div>
    );
  }

  return (
    <form className="stack" onSubmit={submit} aria-busy={working}>
      <p>
        Informe o e-mail da sua conta para solicitar um link de redefinição.
      </p>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <label className="field" htmlFor="reset-email">
        E-mail
        <input
          id="reset-email"
          name="email"
          type="email"
          autoComplete="email"
          required
          maxLength={254}
          disabled={working}
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />
      </label>
      <button className="button" type="submit" disabled={working}>
        {working ? "Solicitando…" : "Enviar link de redefinição"}
      </button>
    </form>
  );
}
