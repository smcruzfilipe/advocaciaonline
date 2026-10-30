import Link from "next/link";
import { ApiError } from "@/lib/api";

export function RequestError({
  error,
  onRetry,
  title,
}: {
  error: Error;
  onRetry?: () => void;
  title?: string;
}) {
  const apiError = error instanceof ApiError ? error : undefined;
  const status = apiError?.status;
  const onboarding = apiError?.code === "onboarding_required";
  const heading =
    status === 401
      ? "Entre para continuar"
      : onboarding
        ? "Perfil profissional necessário"
        : status === 403
          ? "Operação não autorizada"
          : status === 404
            ? "Monitoramento não encontrado"
            : status === 409
              ? "Monitoramento já cadastrado"
              : status === 422
                ? "Confira os dados informados"
                : (title ?? "Não foi possível carregar os dados");

  return (
    <div className="error stack" role="alert">
      <strong>{heading}</strong>
      <p>{error.message}</p>
      {status === 401 && <Link href="/login">Entrar com Google</Link>}
      {onboarding && (
        <Link href="/onboarding">Cadastrar perfil profissional</Link>
      )}
      {status === 403 && (
        <Link href="/vinculos">Consultar ou trocar vínculo</Link>
      )}
      {status === 409 && (
        <Link href="/monitoramentos">
          Consultar monitoramentos existentes, inclusive desativados
        </Link>
      )}
      {onRetry && (
        <button className="button-secondary" type="button" onClick={onRetry}>
          Tentar novamente
        </button>
      )}
    </div>
  );
}
