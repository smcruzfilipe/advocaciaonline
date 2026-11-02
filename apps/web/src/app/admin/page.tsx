import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { publicOrigin, railsFetch } from "@/app/api/transport";

export const dynamic = "force-dynamic";

export default async function AdministrationPage() {
  let session: { authenticated?: boolean; platform_admin?: boolean };
  try {
    const request = new Request(new URL("/api/session", publicOrigin()), {
      headers: { Cookie: (await cookies()).toString() },
    });
    const response = await railsFetch(request, "/api/session");
    if (!response.ok) throw new Error("Session unavailable");
    session = await response.json();
  } catch {
    return (
      <section className="mx-auto flex max-w-sm flex-col gap-4 px-4 py-12">
        <h1 className="font-headings text-2xl font-semibold">
          Acesso indisponível
        </h1>
        <p role="alert">Não foi possível validar seu acesso administrativo.</p>
        <a href="/admin" className="text-accent underline">
          Tentar novamente
        </a>
      </section>
    );
  }
  if (session.authenticated !== true) redirect("/login#");
  if (session.platform_admin !== true)
    return (
      <section className="mx-auto flex max-w-sm flex-col gap-4 px-4 py-12">
        <h1 className="font-headings text-2xl font-semibold">
          Acesso não permitido
        </h1>
        <p>Esta conta não tem permissão de administração da plataforma.</p>
        <Link href="/" className="text-accent underline">
          Voltar ao meu ambiente
        </Link>
      </section>
    );
  return (
    <section className="mx-auto flex max-w-5xl flex-col gap-6 px-4 py-8 md:px-8">
      <header>
        <h1 className="font-headings text-2xl font-semibold">
          Administração da plataforma
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Acesso administrativo confirmado no servidor.
        </p>
      </header>
      <div className="border border-border p-5 text-sm">
        <h2 className="font-semibold">Conta administrativa</h2>
        <p className="mt-2">
          Você entrou com senha e autenticador. Esta permissão é independente de
          um perfil profissional ou vínculo com equipe.
        </p>
      </div>
      <Link
        href="/admin/convites"
        className="self-start text-sm font-medium text-accent underline"
      >
        Gerenciar convites de primeiro acesso
      </Link>
    </section>
  );
}
