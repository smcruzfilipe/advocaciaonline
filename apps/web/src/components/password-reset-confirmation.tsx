"use client";

import { useRef, useState, type FormEvent } from "react";
import { ApiError, authRequest } from "@/lib/api";
import { AlertBanner } from "@/components/ui";

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
    <form
      className="flex flex-col gap-4 border border-border p-6 text-sm"
      onSubmit={submit}
      aria-busy={working}
    >
      <p>Escolha uma nova senha para sua conta.</p>
      {error && <AlertBanner variant="error">{error}</AlertBanner>}
      <label
        className="flex flex-col gap-1.5 text-sm font-medium"
        htmlFor="reset-password"
      >
        Nova senha
        <input
          className="w-full border border-border bg-input px-3 py-2 text-sm"
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
      <p id="reset-password-help" className="text-xs text-muted-foreground">
        A senha deve ter de 12 a 128 caracteres.
      </p>
      <label
        className="flex flex-col gap-1.5 text-sm font-medium"
        htmlFor="reset-password-confirmation"
      >
        Confirme a nova senha
        <input
          className="w-full border border-border bg-input px-3 py-2 text-sm"
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
      <button
        className="bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-50"
        type="submit"
        disabled={working}
      >
        {working ? "Alterando senha…" : "Salvar nova senha"}
      </button>
    </form>
  );
}
