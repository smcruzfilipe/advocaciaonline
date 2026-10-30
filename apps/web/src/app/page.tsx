"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { destination, useSession } from "@/components/session-provider";

export default function HomePage() {
  const router = useRouter();
  const { session, loading, pendingInvitation } = useSession();
  useEffect(() => {
    if (!loading && session)
      router.replace(destination(session, pendingInvitation));
  }, [loading, pendingInvitation, router, session]);
  return (
    <section className="page access-page stack" aria-busy="true">
      <h1>Seu ambiente jurídico</h1>
      <p role="status">Preparando seu acesso…</p>
    </section>
  );
}
