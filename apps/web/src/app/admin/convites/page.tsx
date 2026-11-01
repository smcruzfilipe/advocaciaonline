import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { publicOrigin, railsFetch } from "@/app/api/transport";
import { PlatformAdminInvitations } from "@/components/platform-admin-invitations";

export const dynamic = "force-dynamic";

export default async function AdminInvitationsPage() {
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
        <Link href="/admin/convites" className="text-accent underline">
          Tentar novamente
        </Link>
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
  return <PlatformAdminInvitations />;
}
