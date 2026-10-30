export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: unknown;

  constructor(
    status: number,
    message: string,
    code: string,
    details?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

type ApiOptions = {
  method?: string;
  body?: unknown;
  invitationFingerprint?: string;
};
type DisplayedSession = {
  authenticated: boolean;
  csrf_token?: string;
  membership_id?: string | null;
};

let displayedSession: DisplayedSession | null = null;

export function setDisplayedSession(session: DisplayedSession | null): void {
  displayedSession = session;
}

export async function withSessionLock<T>(
  operation: () => Promise<T>,
  mode: "exclusive" | "shared" = "exclusive",
): Promise<T> {
  if (typeof navigator === "undefined" || !navigator.locks) {
    throw new ApiError(
      0,
      "Este navegador não permite proteger dados entre abas. Use um navegador atualizado.",
      "browser_not_supported",
    );
  }
  return navigator.locks.request(
    "advocacia:session-write",
    { mode },
    operation,
  );
}

function notifyAuthentication(error: ApiError): void {
  if (error.status === 401 && typeof window !== "undefined") {
    window.dispatchEvent(new Event("advocacia:unauthorized"));
  }
}

async function request<T>(path: string, options: RequestInit): Promise<T> {
  let response: Response;
  try {
    response = await fetch(path, {
      ...options,
      credentials: "same-origin",
      cache: "no-store",
      redirect: "error",
    });
  } catch {
    throw new ApiError(
      0,
      ["GET", "HEAD", "OPTIONS"].includes(options.method ?? "GET")
        ? "Não foi possível conectar ao servidor. Verifique sua conexão e tente novamente."
        : "Não foi possível confirmar o resultado. Atualize a lista e verifique se a operação já foi concluída antes de tentar novamente.",
      "network_error",
    );
  }
  if (response.status === 204 || response.status === 205) return undefined as T;
  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    const error = new ApiError(
      response.status,
      "O servidor retornou uma resposta inesperada. Tente novamente.",
      "invalid_response",
    );
    notifyAuthentication(error);
    throw error;
  }
  if (!response.ok) {
    const value =
      payload && typeof payload === "object" && "error" in payload
        ? payload.error
        : null;
    const error = new ApiError(
      response.status,
      value &&
        typeof value === "object" &&
        "message" in value &&
        typeof value.message === "string"
        ? value.message
        : "Não foi possível concluir esta operação.",
      value &&
        typeof value === "object" &&
        "code" in value &&
        typeof value.code === "string"
        ? value.code
        : "request_failed",
      value && typeof value === "object" && "details" in value
        ? value.details
        : undefined,
    );
    notifyAuthentication(error);
    throw error;
  }
  return payload as T;
}

async function confirmedSession(
  expected: DisplayedSession,
  headers: Headers,
): Promise<string> {
  const session = await request<DisplayedSession>("/api/session", {
    method: "GET",
    headers,
  });
  if (!session.authenticated || !session.csrf_token) {
    const error = new ApiError(
      401,
      "Sua sessão terminou. Entre com sua conta Google para continuar.",
      "authentication_required",
    );
    notifyAuthentication(error);
    throw error;
  }
  if (
    session.csrf_token !== expected.csrf_token ||
    (session.membership_id ?? null) !== (expected.membership_id ?? null)
  ) {
    if (typeof window !== "undefined")
      window.dispatchEvent(new Event("advocacia:context-changed"));
    throw new ApiError(
      409,
      "Seu vínculo ou sua conta mudou em outra aba. Confira o ambiente antes de tentar novamente.",
      "session_context_changed",
    );
  }
  return session.csrf_token;
}

export async function api<T>(
  path: string,
  options: ApiOptions = {},
): Promise<T> {
  if (
    (!path.startsWith("/api/") &&
      !["/convite/aceitar", "/convite/preservar"].includes(path)) ||
    path.includes("\\") ||
    path.startsWith("//")
  ) {
    throw new ApiError(
      400,
      "Endereço de solicitação inválido.",
      "invalid_path",
    );
  }
  const method = (options.method ?? "GET").toUpperCase();
  const headers = new Headers({ Accept: "application/json" });
  const reading = ["GET", "HEAD", "OPTIONS"].includes(method);
  if (reading && path === "/api/session")
    return request<T>(path, { method, headers });
  const expected = displayedSession;
  if (!expected?.authenticated || !expected.csrf_token) {
    const error = new ApiError(
      401,
      "Sua sessão terminou. Entre com sua conta Google para continuar.",
      "authentication_required",
    );
    notifyAuthentication(error);
    throw error;
  }
  // Reads share the lock; membership changes and writes take it exclusively.
  return withSessionLock(
    async () => {
      const csrfToken = await confirmedSession(expected, headers);
      if (reading) {
        const result = await request<T>(path, { method, headers });
        // OAuth callback navigations cannot take a browser lock. Recheck before
        // exposing a response that may have raced with a new login.
        await confirmedSession(expected, headers);
        return result;
      }
      headers.set("X-CSRF-Token", csrfToken);
      headers.set("Content-Type", "application/json");
      if (path === "/convite/aceitar") {
        if (
          !options.invitationFingerprint ||
          !/^[0-9a-f]{64}$/.test(options.invitationFingerprint)
        )
          throw new ApiError(
            409,
            "Abra novamente o link de convite recebido.",
            "invitation_context_changed",
          );
        headers.set("X-Invitation-Fingerprint", options.invitationFingerprint);
      }
      return request<T>(path, {
        method,
        headers,
        body:
          options.body === undefined ? undefined : JSON.stringify(options.body),
      });
    },
    reading ? "shared" : "exclusive",
  );
}
