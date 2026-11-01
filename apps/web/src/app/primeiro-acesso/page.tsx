"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import { AuthenticatorSetup } from "@/components/authenticator-setup";
import { useSession } from "@/components/session-provider";
import { AlertBanner } from "@/components/ui";
import { ApiError, authRequest } from "@/lib/api";

type Inspection = {
  email: string;
  expires_at: string;
  requires_login: boolean;
};
type Setup = {
  challenge: string;
  otpauth_uri: string;
  expires_at: string;
};
type LoginChallenge =
  { next: "totp" } | { next: "totp_setup"; otpauth_uri: string };

const formStyle =
  "flex flex-col gap-4 border border-border p-5 text-sm [&_input]:w-full [&_input]:border [&_input]:border-border [&_input]:bg-input [&_input]:px-3 [&_input]:py-2";
const buttonStyle =
  "bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-50";
const secondaryStyle =
  "border border-border bg-background px-4 py-2 text-sm font-medium disabled:opacity-50";

export default function FirstAccessPage() {
  const router = useRouter();
  const {
    session,
    loading,
    error: sessionError,
    refresh,
    logout,
  } = useSession();
  const token = useRef<string | null>(null);
  const captured = useRef(false);
  const inspectionStarted = useRef(false);
  const submitting = useRef(false);
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [inspecting, setInspecting] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [code, setCode] = useState("");
  const [setup, setSetup] = useState<Setup | null>(null);
  const [loginChallenge, setLoginChallenge] = useState<LoginChallenge | null>(
    null,
  );
  const [loginConfirmed, setLoginConfirmed] = useState(false);
  const [completed, setCompleted] = useState(false);
  const [outcomeUnknown, setOutcomeUnknown] = useState(false);

  useLayoutEffect(() => {
    if (captured.current) return;
    captured.current = true;
    const fragment = new URLSearchParams(window.location.hash.slice(1));
    token.current = fragment.get("token");
    if (window.location.hash)
      window.history.replaceState(
        window.history.state,
        "",
        `${window.location.pathname}${window.location.search}`,
      );
  }, []);

  const inspect = useCallback(async () => {
    if (!token.current) {
      setError("Abra o link de primeiro acesso recebido para continuar.");
      setInspecting(false);
      return;
    }
    setInspecting(true);
    setError(null);
    try {
      setInspection(
        await authRequest<Inspection>("/api/auth/first-access/inspect", {
          token: token.current,
        }),
      );
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível concluir a solicitação.",
      );
    } finally {
      setInspecting(false);
    }
  }, []);

  useEffect(() => {
    if (loading || !session || inspectionStarted.current) return;
    inspectionStarted.current = true;
    void inspect();
  }, [inspect, loading, session]);

  async function run(operation: () => Promise<void>) {
    if (submitting.current) return;
    submitting.current = true;
    setWorking(true);
    setError(null);
    try {
      await operation();
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível concluir a solicitação.",
      );
    } finally {
      submitting.current = false;
      setWorking(false);
    }
  }

  async function continueAfterCompletion() {
    await refresh();
    router.replace("/onboarding");
  }

  function submitPassword(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!inspection || !token.current) return;
    void run(async () => {
      if (inspection.requires_login) {
        const result = await authRequest<LoginChallenge>("/api/auth/login", {
          email: inspection.email,
          password,
        });
        if (
          result.next !== "totp" &&
          (result.next !== "totp_setup" || !result.otpauth_uri)
        )
          throw new Error("O servidor retornou uma resposta inesperada.");
        setLoginChallenge(result);
      } else {
        if (password !== confirmation)
          throw new Error("As senhas informadas não coincidem.");
        const result = await authRequest<Setup>("/api/auth/first-access", {
          token: token.current,
          password,
          password_confirmation: confirmation,
        });
        if (!result.challenge || !result.otpauth_uri || !result.expires_at)
          throw new Error("Não foi possível preparar o autenticador.");
        setSetup(result);
      }
      setPassword("");
      setConfirmation("");
    });
  }

  function submitCode(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token.current) return;
    void run(async () => {
      if (setup) {
        try {
          await authRequest("/api/auth/first-access/confirm", {
            token: token.current,
            challenge: setup.challenge,
            code,
          });
        } catch (reason) {
          if (
            reason instanceof ApiError &&
            ["network_error", "backend_unavailable"].includes(reason.code)
          ) {
            setOutcomeUnknown(true);
            throw new Error(
              "Não foi possível confirmar o resultado. A conta pode ter sido criada; tente entrar normalmente antes de solicitar outro convite.",
            );
          }
          throw reason;
        }
        token.current = null;
        setSetup(null);
        setCode("");
        setCompleted(true);
        await continueAfterCompletion();
      } else if (loginChallenge) {
        await authRequest("/api/auth/totp", { code });
        setCode("");
        setLoginChallenge(null);
        setLoginConfirmed(true);
        await refresh();
        setLoginConfirmed(false);
      }
    });
  }

  function redeem() {
    if (!token.current) return;
    void run(async () => {
      try {
        await authRequest("/api/auth/first-access", { token: token.current });
      } catch (reason) {
        if (
          reason instanceof ApiError &&
          ["network_error", "backend_unavailable"].includes(reason.code)
        ) {
          setOutcomeUnknown(true);
          throw new Error(
            "Não foi possível confirmar o resultado. A liberação pode ter sido concluída; tente entrar normalmente antes de solicitar outro convite.",
          );
        }
        throw reason;
      }
      token.current = null;
      setCompleted(true);
      await continueAfterCompletion();
    });
  }

  const authenticator =
    setup ?? (loginChallenge?.next === "totp_setup" ? loginChallenge : null);
  return (
    <section
      className="mx-auto flex w-full max-w-md flex-col gap-6 px-4 py-16 sm:px-0"
      aria-busy={loading || inspecting || working}
    >
      <header>
        <h1 className="mb-2 font-headings text-2xl font-semibold text-foreground">
          Primeiro acesso
        </h1>
        <p className="text-sm text-muted-foreground">
          Conclua seu convite para cadastrar seu perfil profissional.
        </p>
      </header>
      {error && <AlertBanner variant="error">{error}</AlertBanner>}
      {!loading && !session && sessionError && (
        <>
          <AlertBanner variant="error">{sessionError}</AlertBanner>
          <button
            className={secondaryStyle}
            disabled={working}
            onClick={() =>
              void run(async () => {
                await refresh();
              })
            }
          >
            Consultar sessão novamente
          </button>
        </>
      )}
      {loading || (inspecting && session) ? (
        <p role="status">Consultando o convite e sua sessão…</p>
      ) : completed ? (
        <div className="flex flex-col gap-4 border border-border p-5 text-sm">
          <p role="status">
            Convite resgatado. Continue para seu perfil profissional.
          </p>
          <button
            className={buttonStyle}
            disabled={working}
            onClick={() => void run(continueAfterCompletion)}
          >
            Continuar
          </button>
        </div>
      ) : outcomeUnknown ? (
        <div className="flex flex-col gap-4 border border-border p-5 text-sm">
          <p>
            Não repita a confirmação automaticamente. Se já concluiu o acesso,
            entre com sua senha e autenticador.
          </p>
          <Link className={secondaryStyle + " text-center"} href="/login">
            Ir para o login
          </Link>
        </div>
      ) : inspection && session ? (
        <>
          <div className="flex flex-col gap-2 border border-border p-5 text-sm">
            <p>
              <strong>E-mail convidado:</strong>{" "}
              <span className="break-all">{inspection.email}</span>
            </p>
            <p>
              Convite válido até{" "}
              {new Date(inspection.expires_at).toLocaleString("pt-BR")}.
            </p>
          </div>
          {loginConfirmed ? (
            <div className="flex flex-col gap-4 border border-border p-5 text-sm">
              <p>
                Autenticação confirmada. Consulte sua sessão para resgatar o
                convite.
              </p>
              <button
                className={buttonStyle}
                disabled={working}
                onClick={() =>
                  void run(async () => {
                    await refresh();
                    setLoginConfirmed(false);
                  })
                }
              >
                Consultar sessão
              </button>
            </div>
          ) : session.authenticated ? (
            <div className="flex flex-col gap-4 border border-border p-5 text-sm">
              <p>
                {inspection.requires_login
                  ? "Resgate o convite com a conta do e-mail convidado. Suas credenciais não serão alteradas."
                  : "Para criar a conta convidada, saia da conta atual nesta tela."}
              </p>
              {inspection.requires_login && (
                <button
                  className={buttonStyle}
                  disabled={working}
                  onClick={redeem}
                >
                  Resgatar convite
                </button>
              )}
              <button
                className={secondaryStyle}
                disabled={working}
                onClick={() =>
                  void run(async () => {
                    await logout();
                    setLoginChallenge(null);
                  })
                }
              >
                Sair da conta atual
              </button>
            </div>
          ) : setup || loginChallenge ? (
            <form className={formStyle} onSubmit={submitCode}>
              {authenticator ? (
                <>
                  <AuthenticatorSetup otpauthUri={authenticator.otpauth_uri} />
                  {setup && (
                    <p>
                      Preparação válida até{" "}
                      {new Date(setup.expires_at).toLocaleString("pt-BR")}.
                    </p>
                  )}
                </>
              ) : (
                <p>Informe o código atual do aplicativo autenticador.</p>
              )}
              <label
                className="flex flex-col gap-1.5 font-medium"
                htmlFor="first-access-code"
              >
                Código do autenticador
                <input
                  id="first-access-code"
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
              <button className={buttonStyle} type="submit" disabled={working}>
                {working
                  ? "Validando…"
                  : setup
                    ? "Confirmar primeiro acesso"
                    : "Validar e entrar"}
              </button>
              <button
                className={secondaryStyle}
                type="button"
                disabled={working}
                onClick={() => {
                  setSetup(null);
                  setLoginChallenge(null);
                  setCode("");
                  setError(null);
                }}
              >
                Voltar
              </button>
            </form>
          ) : (
            <form className={formStyle} onSubmit={submitPassword}>
              <p>
                {inspection.requires_login
                  ? "Esta conta já existe. Entre com sua senha e autenticador para resgatar o convite."
                  : "Escolha uma senha. Sua conta só será criada após a confirmação do autenticador."}
              </p>
              <label
                className="flex flex-col gap-1.5 font-medium"
                htmlFor="first-access-password"
              >
                {inspection.requires_login ? "Senha" : "Nova senha"}
                <input
                  id="first-access-password"
                  name="password"
                  type="password"
                  autoComplete={
                    inspection.requires_login
                      ? "current-password"
                      : "new-password"
                  }
                  required
                  minLength={12}
                  maxLength={128}
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                />
              </label>
              {!inspection.requires_login && (
                <>
                  <p className="text-xs text-muted-foreground">
                    A senha deve ter de 12 a 128 caracteres.
                  </p>
                  <label
                    className="flex flex-col gap-1.5 font-medium"
                    htmlFor="first-access-confirmation"
                  >
                    Confirme a senha
                    <input
                      id="first-access-confirmation"
                      name="password_confirmation"
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
              <button className={buttonStyle} type="submit" disabled={working}>
                {working ? "Enviando…" : "Continuar"}
              </button>
            </form>
          )}
        </>
      ) : !inspecting && session ? (
        <button
          className={secondaryStyle}
          disabled={working}
          onClick={() => void inspect()}
        >
          Consultar convite novamente
        </button>
      ) : null}
    </section>
  );
}
