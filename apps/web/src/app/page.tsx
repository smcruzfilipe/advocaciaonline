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
    <section
      className="mx-auto max-w-sm px-4 py-20 flex flex-col gap-6"
      aria-busy="true"
    >
      <h1 className="text-2xl font-semibold font-headings">
        Central de Processos
      </h1>
      <p className="text-sm text-muted-foreground" role="status">
        Preparando seu acesso…
      </p>
    </section>
  );
}
