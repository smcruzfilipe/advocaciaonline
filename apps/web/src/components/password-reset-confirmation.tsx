"use client";

import { useRef, useState, type FormEvent } from "react";
import { ApiError, authRequest } from "@/lib/api";

type Props = {
  token: string;
  onSuccess: () => void;
  onInvalid: () => void;
};

export function PasswordResetConfirmation({
  token,
  onSuccess,
  onInvalid,
}: Props) {
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submitting = useRef(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting.current) return;
    if (password !== confirmation) {
      setError("As senhas informadas não coincidem.");
      return;
    }
    if (password.length < 12 || password.length > 128) {
      setError("A senha deve ter de 12 a 128 caracteres.");
      return;
    }
    submitting.current = true;
    setWorking(true);
    setError(null);
    try {
      await authRequest<void>("/api/auth/password-reset/confirm", {
        token,
        password,
      });
      setPassword("");
      setConfirmation("");
      onSuccess();
    } catch (reason) {
      if (
        reason instanceof ApiError &&
        reason.code === "password_reset_invalid"
      ) {
        setPassword("");
        setConfirmation("");
        onInvalid();
        return;
      }
      setError(
        reason instanceof ApiError &&
          ["network_error", "backend_unavailable"].includes(reason.code)
          ? "Não foi possível confirmar a alteração. Tente entrar com a nova senha; se ela não funcionar e o link não for mais válido, solicite outro link."
          : reason instanceof Error
            ? reason.message
            : "Não foi possível alterar sua senha. Tente novamente.",
      );
    } finally {
      submitting.current = false;
      setWorking(false);
    }
  }

  return (
    <form className="stack" onSubmit={submit} aria-busy={working}>
      <p>Escolha uma nova senha para sua conta.</p>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <label className="field" htmlFor="reset-password">
        Nova senha
        <input
          id="reset-password"
          name="password"
          type="password"
          autoComplete="new-password"
          required
          minLength={12}
          maxLength={128}
          disabled={working}
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          aria-describedby="reset-password-help"
        />
      </label>
      <p id="reset-password-help" className="muted small">
        A senha deve ter de 12 a 128 caracteres.
      </p>
      <label className="field" htmlFor="reset-password-confirmation">
        Confirme a nova senha
        <input
          id="reset-password-confirmation"
          name="confirmation"
          type="password"
          autoComplete="new-password"
          required
          minLength={12}
          maxLength={128}
          disabled={working}
          value={confirmation}
          onChange={(event) => setConfirmation(event.target.value)}
        />
      </label>
      <button className="button" type="submit" disabled={working}>
        {working ? "Alterando senha…" : "Salvar nova senha"}
      </button>
    </form>
  );
}
