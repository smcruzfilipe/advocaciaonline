"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { destination, useSession } from "@/components/session-provider";

export function LoginScreen({ loginError }: { loginError: string | null }) {
  const router = useRouter();
  const { session, loading, pendingInvitation } = useSession();
  const [leaving, setLeaving] = useState(false);

  useEffect(() => {
    if (!loading && session?.authenticated)
      router.replace(destination(session, pendingInvitation));
  }, [loading, pendingInvitation, router, session]);

  return (
    <section className="page access-page stack" aria-busy={loading || leaving}>
      <div className="stack">
        <span className="eyebrow">Acesso seguro</span>
        <h1>Entre na sua conta</h1>
        <p className="muted">
          Acesse seus monitoramentos, comunicações e equipe com sua conta
          Google.
        </p>
      </div>
      {loginError && (
        <p className="error" role="alert">
          {loginError}
        </p>
      )}
      {pendingInvitation && (
        <div className="notice stack">
          <strong>Você tem um convite de equipe.</strong>
          <p>Entre com a conta Google do e-mail convidado para continuar.</p>
          <Link href="/convite">Ver convite</Link>
        </div>
      )}
      {loading || session?.authenticated ? (
        <p role="status">
          {loading ? "Consultando sua sessão…" : "Abrindo seu ambiente…"}
        </p>
      ) : (
        <a
          className="button google-login"
          href="/auth/google"
          onClick={() => setLeaving(true)}
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            width="20"
            height="20"
            fill="currentColor"
          >
            <path d="M21.6 12.2c0-.7-.1-1.4-.2-2.2H12v4.1h5.4a4.6 4.6 0 0 1-2 3v2.5h3.3c1.9-1.8 2.9-4.3 2.9-7.4ZM12 22c2.7 0 5-1 6.7-2.5L15.4 17c-.9.6-2 .9-3.4.9a6 6 0 0 1-5.6-4.1H3v2.6A10 10 0 0 0 12 22ZM6.4 13.8a6 6 0 0 1 0-3.6V7.6H3a10 10 0 0 0 0 8.8l3.4-2.6ZM12 6.1c1.5 0 2.8.5 3.9 1.5l2.9-2.9A9.6 9.6 0 0 0 12 2a10 10 0 0 0-9 5.6l3.4 2.6A6 6 0 0 1 12 6.1Z" />
          </svg>
          {leaving ? "Abrindo Google…" : "Continuar com o Google"}
        </a>
      )}
      <p className="muted small">
        Não há senha local. O login não concede acesso a uma equipe sem um
        convite válido.
      </p>
      <div className="access-note">
        <h2>Primeiro acesso?</h2>
        <p>
          Após entrar, cadastre seu perfil profissional com nome e OAB. Se
          recebeu um convite de equipe, use o link enviado por e-mail.
        </p>
      </div>
    </section>
  );
}
