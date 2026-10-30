"use client";

import Link from "next/link";
import { ApiError } from "@/lib/api";

export function errorMessage(error: unknown) {
  return error instanceof Error
    ? error.message
    : "Não foi possível concluir a solicitação. Tente novamente.";
}

export function isDeliveryError(error: unknown) {
  return (
    error instanceof ApiError &&
    ["invitation_delivery_failed", "invitation_configuration_error"].includes(
      error.code ?? "",
    )
  );
}

export function ErrorNotice({
  error,
  onRetry,
  id,
}: {
  error: unknown;
  onRetry?: () => void;
  id?: string;
}) {
  const status = error instanceof ApiError ? error.status : undefined;
  const delivery = isDeliveryError(error);
  return (
    <div className="error stack" role="alert" id={id}>
      <strong>
        {delivery
          ? "Convite registrado; entrega não confirmada"
          : status === 401
            ? "Sessão ou vínculo indisponível"
            : status === 403
              ? "Operação não autorizada"
              : status === 404
                ? "Registro não encontrado"
                : status === 409
                  ? "Conflito com o estado atual"
                  : status === 422
                    ? "Revise os dados informados"
                    : "Não foi possível concluir"}
      </strong>
      <p>{errorMessage(error)}</p>
      {status === 401 && (
        <p>
          <Link href="/login">Entrar novamente</Link> ou{" "}
          <Link href="/vinculos">selecionar um vínculo válido</Link>.
        </p>
      )}
      {status === 403 && (
        <p>
          A administração de equipe e grupos é exclusiva do advogado titular. A
          autorização é verificada pelo servidor em cada operação.
        </p>
      )}
      {onRetry && status !== 401 && status !== 403 && (
        <div>
          <button className="button-secondary" type="button" onClick={onRetry}>
            Tentar novamente
          </button>
        </div>
      )}
    </div>
  );
}

export function PolicyNotice() {
  return (
    <aside className="notice stack" aria-label="Como as permissões funcionam">
      <p>
        <strong>
          Concessões se somam; negação explícita prevalece no mesmo escopo.
        </strong>{" "}
        Com grupos, uma operação exige concessão aplicável. A dashboard não
        amplia os tribunais permitidos para comunicações.
      </p>
      <p>
        Sem grupos, a equipe tem as leituras padrão de monitoramentos,
        comunicações e dashboard, sem escrita automática. Remover o último grupo
        não revoga a credencial e volta a aplicar essas leituras.
      </p>
      <p>
        A administração de equipe e grupos, assim como a consulta do Escrevente,
        continua exclusiva do titular; grupos não delegam esse acesso.
      </p>
    </aside>
  );
}
