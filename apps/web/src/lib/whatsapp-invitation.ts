export function normalizeWhatsappPhone(value: string): string | null {
  const trimmed = value.trim();
  if (!/^\+?[\d\s().-]+$/.test(trimmed)) return null;
  const digits = trimmed.replace(/\D/g, "");
  return digits.length >= 8 && digits.length <= 15 ? digits : null;
}

export function whatsappInvitationUrl(
  phone: string,
  link: string,
  expiresAt: string,
): string {
  const url = new URL("https://api.whatsapp.com/send/");
  url.searchParams.set("phone", phone);
  url.searchParams.set(
    "text",
    `Você recebeu um convite para o primeiro acesso.\n\nAcesse: ${link}\nVálido até: ${expiresAt}.`,
  );
  url.searchParams.set("type", "phone_number");
  url.searchParams.set("app_absent", "0");
  return url.toString();
}
