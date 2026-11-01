"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { AuthenticatorSetup } from "@/components/authenticator-setup";
import { destination, useSession } from "@/components/session-provider";
import { authRequest } from "@/lib/api";
import { AlertBanner } from "@/components/ui";

type Challenge = { next: "totp" } | { next: "totp_setup"; otpauth_uri: string };

type RecoverySetup = { challenge: string; otpauth_uri: string };

export function LoginScreen() {
  const router = useRouter();
  const {
    session,
    loading,
    pendingInvitation,
    invitationMismatch,
    invitationFingerprint,
    refresh,
  } = useSession();
  const [mode, setMode] = useState<"login" | "register" | "recovery">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [code, setCode] = useState("");
  const [challenge, setChallenge] = useState<Challenge | null>(null);
  const [registered, setRegistered] = useState(false);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [recoveryCode, setRecoveryCode] = useState("");
  const [recoverySetup, setRecoverySetup] = useState<RecoverySetup | null>(
    null,
  );
  const [recoveryCodes, setRecoveryCodes] = useState<string[] | null>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const setup =
    recoverySetup ?? (challenge?.next === "totp_setup" ? challenge : null);

  useEffect(() => {
    heading.current?.focus();
  }, [mode, challenge, recoverySetup, recoveryCodes]);

  useEffect(() => {
    if (!recoveryCodes && !loading && session?.authenticated)
      router.replace(destination(session, pendingInvitation));
  }, [loading, pendingInvitation, recoveryCodes, router, session]);

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
      if (mode === "recovery") {
        const result = await authRequest<RecoverySetup>(
          "/api/admin/auth/recovery",
          {
            email,
            password,
            recovery_code: recoveryCode,
          },
        );
        if (!result.challenge || !result.otpauth_uri)
          throw new Error("Não foi possível preparar o novo autenticador.");
        setRecoverySetup(result);
        setPassword("");
        setRecoveryCode("");
        setCode("");
      } else if (mode === "register") {
        if (!pendingInvitation || invitationMismatch || !invitationFingerprint)
          throw new Error("Abra novamente o link de convite nesta aba.");
        await authRequest(
          "/api/auth/team-register",
          {
            email,
            password,
            password_confirmation: confirmation,
          },
          invitationFingerprint,
        );
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
          (result.next !== "totp_setup" || !result.otpauth_uri)
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
      if (recoverySetup) {
        const result = await authRequest<{ recovery_codes: string[] }>(
          "/api/admin/auth/recovery/confirm",
          { token: recoverySetup.challenge, code },
        );
        if (
          !Array.isArray(result.recovery_codes) ||
          !result.recovery_codes.every((value) => typeof value === "string")
        )
          throw new Error(
            "Não foi possível obter os novos códigos de recuperação.",
          );
        setRecoverySetup(null);
        setRecoveryCodes(result.recovery_codes);
      } else {
        await authRequest("/api/auth/totp", { code });
        const current = await refresh();
        window.location.assign(destination(current, pendingInvitation));
      }
      setCode("");
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

  function switchMode(next: "login" | "register" | "recovery") {
    setMode(next);
    setChallenge(null);
    setRegistered(false);
    setPassword("");
    setConfirmation("");
    setCode("");
    setError(null);
    setRecoveryCode("");
    setRecoverySetup(null);
    setRecoveryCodes(null);
  }

  return (
    <section
      className="mx-auto flex w-full max-w-sm flex-col gap-6 px-4 py-20 sm:px-0"
      aria-busy={loading || working}
    >
      <header>
        <h1
          ref={heading}
          tabIndex={-1}
          className="mb-2 font-headings text-2xl font-semibold text-foreground"
        >
          {recoveryCodes
            ? "Guarde seus novos códigos"
            : recoverySetup
              ? "Confirme o novo autenticador"
              : challenge
                ? "Confirme seu acesso"
                : mode === "recovery"
                  ? "Recuperar autenticador administrativo"
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
      {!recoveryCodes && (loading || session?.authenticated) ? (
        <p role="status">
          {loading ? "Consultando sua sessão…" : "Abrindo seu ambiente…"}
        </p>
      ) : recoveryCodes ? (
        <div className="flex flex-col gap-4 border border-border p-6 text-sm">
          <p role="status">
            Autenticador substituído. Nenhuma sessão foi criada.
          </p>
          <p>
            Guarde estes códigos fora da plataforma. Cada um pode ser usado uma
            única vez; os anteriores foram invalidados.
          </p>
          <ul
            className="flex flex-col gap-2 break-all font-mono"
            aria-label="Novos códigos de recuperação"
          >
            {recoveryCodes.map((value) => (
              <li key={value}>{value}</li>
            ))}
          </ul>
          <p>
            Ao continuar, os códigos deixam de ser exibidos. Entre novamente com
            senha e o novo autenticador.
          </p>
          <button
            type="button"
            className="bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
            onClick={() => switchMode("login")}
          >
            Guardei os códigos. Voltar ao login
          </button>
        </div>
      ) : registered ? (
        <div
          className="flex flex-col gap-4 border border-border p-6 text-sm"
          role="status"
        >
          <h2 className="font-semibold">Confira seu e-mail</h2>
          <p>
            Se o convite estiver disponível, enviaremos instruções para
            confirmação do e-mail. Confirme sua caixa antes de entrar para
            aceitar o convite de equipe.
          </p>
          <button
            className="bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-50"
            type="button"
            onClick={() => switchMode("login")}
          >
            Ir para o login
          </button>
        </div>
      ) : challenge || recoverySetup ? (
        <form
          className="flex flex-col gap-4 border border-border p-6 text-sm [&_input]:w-full [&_input]:border [&_input]:border-border [&_input]:bg-input [&_input]:px-3 [&_input]:py-2"
          onSubmit={submitCode}
        >
          {setup ? (
            <AuthenticatorSetup otpauthUri={setup.otpauth_uri} />
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
            {working
              ? "Validando…"
              : recoverySetup
                ? "Confirmar novo autenticador"
                : "Validar e entrar"}
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
            {recoverySetup
              ? "A preparação expira em dez minutos. Se expirar ou você sair desta tela, reinicie com outro código de recuperação. Confirmar não cria sessão."
              : "Se o desafio expirar ou você atualizar a página, entre novamente com seu e-mail e senha."}
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
          {mode === "recovery" && (
            <>
              <p className="text-sm text-muted-foreground">
                Somente para a conta administrativa. Senha e um código de uso
                único permitem cadastrar um novo autenticador, sem entrar na
                conta. Sem autenticador e sem códigos, não há recuperação por
                e-mail ou suporte.
              </p>
              <label
                className="flex flex-col gap-1.5 text-sm font-medium"
                htmlFor="recovery-code"
              >
                Código de recuperação
                <input
                  id="recovery-code"
                  name="recovery_code"
                  type="password"
                  autoComplete="off"
                  minLength={43}
                  maxLength={43}
                  required
                  value={recoveryCode}
                  onChange={(event) => setRecoveryCode(event.target.value)}
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
                : mode === "recovery"
                  ? "Preparar novo autenticador"
                  : "Continuar"}
          </button>
          {mode === "login" && (
            <>
              <Link
                className="text-center text-xs text-accent underline"
                href="/reset-password"
              >
                Esqueci minha senha
              </Link>
              <button
                type="button"
                className="text-center text-xs text-accent underline disabled:opacity-50"
                disabled={working}
                onClick={() => switchMode("recovery")}
              >
                Perdi meu autenticador administrativo
              </button>
            </>
          )}
          {(mode === "recovery" ||
            (pendingInvitation && !invitationMismatch)) && (
            <button
              className="border border-border bg-background px-4 py-2 text-sm font-medium disabled:opacity-50"
              type="button"
              disabled={working}
              onClick={() =>
                switchMode(mode === "login" ? "register" : "login")
              }
            >
              {mode === "recovery"
                ? "Voltar ao login"
                : mode === "login"
                  ? "Criar conta para convite de equipe"
                  : "Já tenho conta"}
            </button>
          )}
        </form>
      )}
      <div className="flex flex-col gap-1 text-center text-xs text-muted-foreground">
        <h2 className="font-medium">Primeiro acesso?</h2>
        <p>
          O cadastro está disponível apenas por convite. Entre em contato com o
          responsável pela plataforma para solicitar acesso.
        </p>
      </div>
    </section>
  );
}
