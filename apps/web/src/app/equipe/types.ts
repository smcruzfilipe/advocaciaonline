export type TeamCredential = {
  id: string;
  invited_email: string;
  accepted_at: string | null;
  validity_days: number | null;
  credential_started_at: string;
  expires_at: string | null;
  revoked_at: string | null;
};

export function credentialState(credential: TeamCredential) {
  if (credential.revoked_at) return "Revogada";
  if (credential.expires_at && Date.parse(credential.expires_at) <= Date.now())
    return "Expirada";
  return credential.accepted_at ? "Ativa" : "Aguardando aceite";
}

export function validityLabel(days: number | null) {
  return days === null
    ? "Sem expiração"
    : `${days} ${days === 1 ? "dia" : "dias"} de 24 horas`;
}

export function formatInstant(value: string) {
  return (
    new Intl.DateTimeFormat("pt-BR", {
      dateStyle: "short",
      timeStyle: "short",
      timeZone: "UTC",
    }).format(new Date(value)) + " UTC"
  );
}
