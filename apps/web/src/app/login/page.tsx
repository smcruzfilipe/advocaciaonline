import { LoginScreen } from "@/components/login-screen";

const loginErrors: Record<string, string> = {
  google_login_failed:
    "Não foi possível entrar com o Google. Tente novamente com sua conta verificada.",
  backend_unavailable:
    "O serviço de acesso está indisponível. Tente novamente em instantes.",
  rate_limited:
    "Muitas tentativas de acesso. Aguarde 15 minutos antes de tentar novamente.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ erro?: string | string[] }>;
}) {
  const { erro } = await searchParams;
  const message =
    typeof erro === "string" && Object.hasOwn(loginErrors, erro)
      ? loginErrors[erro]
      : null;
  return <LoginScreen loginError={message} />;
}
