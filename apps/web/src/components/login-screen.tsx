"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { destination, useSession } from "@/components/session-provider";
import { authRequest } from "@/lib/api";
import { AlertBanner } from "@/components/ui";

type Challenge =
  | { next: "totp" }
  | { next: "totp_setup"; secret: string; otpauth_uri: string };

export function LoginScreen() {
  const router = useRouter();
  const { session, loading, pendingInvitation, refresh } = useSession();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [code, setCode] = useState("");
  const [challenge, setChallenge] = useState<Challenge | null>(null);
  const [registered, setRegistered] = useState(false);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!loading && session?.authenticated)
      router.replace(destination(session, pendingInvitation));
  }, [loading, pendingInvitation, router, session]);

  async function submitCredentials(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (working) return;
    if (mode === "register" && password !== confirmation) {
      setError("As senhas informadas não coincidem.");
      return;
    }
    setWorking(true);
    setError(null);
    try {
      if (mode === "register") {
        await authRequest("/api/auth/register", { email, password });
        setPassword("");
        setConfirmation("");
        setRegistered(true);
      } else {
        const result = await authRequest<Challenge>("/api/auth/login", {
          email,
          password,
        });
        if (
          result.next !== "totp" &&
          (result.next !== "totp_setup" ||
            !result.secret ||
            !result.otpauth_uri)
        )
          throw new Error(
            "O servidor retornou uma resposta inesperada. Tente novamente.",
          );
        setChallenge(result);
        setPassword("");
      }
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível concluir a solicitação.",
      );
    } finally {
      setWorking(false);
    }
  }

  async function submitCode(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (working) return;
    setWorking(true);
    setError(null);
    try {
      await authRequest("/api/auth/totp", { code });
      setCode("");
      const current = await refresh();
      router.replace(destination(current, pendingInvitation));
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível validar o código.",
      );
    } finally {
      setWorking(false);
    }
  }

  function switchMode(next: "login" | "register") {
    setMode(next);
    setChallenge(null);
    setRegistered(false);
    setPassword("");
    setConfirmation("");
    setCode("");
    setError(null);
  }

  return (
    <section
      className="mx-auto flex w-full max-w-sm flex-col gap-6 px-4 py-20 sm:px-0"
      aria-busy={loading || working}
    >
      <header>
        <h1 className="mb-2 font-headings text-2xl font-semibold text-foreground">
          {challenge
            ? "Confirme seu acesso"
            : mode === "register"
              ? "Crie sua conta"
              : "Entrar"}
        </h1>
        <p className="text-sm text-muted-foreground">
          Acesse sua conta com e-mail, senha e autenticador para continuar.
        </p>
      </header>
      {pendingInvitation && (
        <div className="flex flex-col gap-2 border border-info bg-info-bg p-4 text-sm text-info">
          <strong>Você tem um convite de equipe.</strong>
          <p>Entre ou crie uma conta com o e-mail convidado para continuar.</p>
          <Link className="underline" href="/convite">
            Ver convite
          </Link>
        </div>
      )}
      {error && <AlertBanner variant="error">{error}</AlertBanner>}
      {loading || session?.authenticated ? (
        <p role="status">
          {loading ? "Consultando sua sessão…" : "Abrindo seu ambiente…"}
        </p>
      ) : registered ? (
        <div
          className="flex flex-col gap-4 border border-border p-6 text-sm"
          role="status"
        >
          <h2 className="font-semibold">Confira seu e-mail</h2>
          <p>
            Se o endereço puder ser cadastrado, você receberá um link de
            confirmação. Abra o link neste mesmo navegador e confirme seu e-mail
            antes de entrar.
          </p>
          <button
            className="bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-50"
            type="button"
            onClick={() => switchMode("login")}
          >
            Ir para o login
          </button>
        </div>
      ) : challenge ? (
        <form
          className="flex flex-col gap-4 border border-border p-6 text-sm [&_input]:w-full [&_input]:border [&_input]:border-border [&_input]:bg-input [&_input]:px-3 [&_input]:py-2"
          onSubmit={submitCode}
        >
          {challenge.next === "totp_setup" ? (
            <div className="flex flex-col gap-3 border border-info bg-info-bg p-4 text-info">
              <h2 className="font-semibold">Configure seu autenticador</h2>
              <p>
                Adicione uma conta no aplicativo autenticador usando a chave
                abaixo. Em seguida, informe o código de seis dígitos gerado pelo
                aplicativo.
              </p>
              <p>
                <strong>Chave de configuração:</strong>{" "}
                <span className="break-all font-mono">{challenge.secret}</span>
              </p>
              <p>Guarde esta chave em local seguro e não a compartilhe.</p>
            </div>
          ) : (
            <p>Informe o código atual do seu aplicativo autenticador.</p>
          )}
          <label
            className="flex flex-col gap-1.5 text-sm font-medium"
            htmlFor="totp-code"
          >
            Código do autenticador
            <input
              id="totp-code"
              name="code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              minLength={6}
              maxLength={6}
              required
              value={code}
              onChange={(event) => setCode(event.target.value)}
            />
          </label>
          <button
            className="bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-50"
            type="submit"
            disabled={working}
          >
            {working ? "Validando…" : "Validar e entrar"}
          </button>
          <button
            className="border border-border bg-background px-4 py-2 text-sm font-medium disabled:opacity-50"
            type="button"
            disabled={working}
            onClick={() => switchMode("login")}
          >
            Voltar ao login
          </button>
          <p className="text-xs text-muted-foreground">
            Se o desafio expirar ou você atualizar a página, entre novamente com
            seu e-mail e senha.
          </p>
        </form>
      ) : (
        <form
          className="flex flex-col gap-4 border border-border p-6 [&_input]:w-full [&_input]:border [&_input]:border-border [&_input]:bg-input [&_input]:px-3 [&_input]:py-2 [&_input]:text-sm"
          onSubmit={submitCredentials}
        >
          <label
            className="flex flex-col gap-1.5 text-sm font-medium"
            htmlFor="access-email"
          >
            E-mail
            <input
              id="access-email"
              name="email"
              type="email"
              autoComplete="email"
              required
              maxLength={254}
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>
          <label
            className="flex flex-col gap-1.5 text-sm font-medium"
            htmlFor="access-password"
          >
            Senha
            <input
              id="access-password"
              name="password"
              type="password"
              autoComplete={
                mode === "register" ? "new-password" : "current-password"
              }
              required
              minLength={12}
              maxLength={128}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              aria-describedby={
                mode === "register" ? "password-help" : undefined
              }
            />
          </label>
          {mode === "register" && (
            <>
              <p id="password-help" className="text-xs text-muted-foreground">
                A senha deve ter de 12 a 128 caracteres.
              </p>
              <label
                className="flex flex-col gap-1.5 text-sm font-medium"
                htmlFor="confirm-password"
              >
                Confirme a senha
                <input
                  id="confirm-password"
                  name="confirmation"
                  type="password"
                  autoComplete="new-password"
                  required
                  minLength={12}
                  maxLength={128}
                  value={confirmation}
                  onChange={(event) => setConfirmation(event.target.value)}
                />
              </label>
            </>
          )}
          <button
            className="bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-50"
            type="submit"
            disabled={working}
          >
            {working
              ? "Enviando…"
              : mode === "register"
                ? "Criar conta"
                : "Continuar"}
          </button>
          {mode === "login" && (
            <Link
              className="text-center text-xs text-accent underline"
              href="/reset-password"
            >
              Esqueci minha senha
            </Link>
          )}
          <button
            className="border border-border bg-background px-4 py-2 text-sm font-medium disabled:opacity-50"
            type="button"
            disabled={working}
            onClick={() => switchMode(mode === "login" ? "register" : "login")}
          >
            {mode === "login" ? "Criar conta" : "Já tenho conta"}
          </button>
        </form>
      )}
      <div className="flex flex-col gap-1 text-center text-xs text-muted-foreground">
        <h2 className="font-medium">Primeiro acesso?</h2>
        <p>
          Confirme seu e-mail e configure o autenticador. Depois você poderá
          cadastrar seu perfil profissional ou aceitar um convite válido.
        </p>
      </div>
    </section>
  );
}
