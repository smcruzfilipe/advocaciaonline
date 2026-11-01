import Link from "next/link";
import { ApiError } from "@/lib/api";
import { AlertBanner, Btn } from "@/components/ui";

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
    <AlertBanner
      variant={status === 403 || status === 409 ? "warning" : "error"}
    >
      <div className="flex flex-col items-start gap-2 [&_a]:underline">
        <strong>{heading}</strong>
        <p>{error.message}</p>
        {status === 401 && <Link href="/login">Entrar na conta</Link>}
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
          <Btn variant="secondary" size="sm" type="button" onClick={onRetry}>
            Tentar novamente
          </Btn>
        )}
      </div>
    </AlertBanner>
  );
}
