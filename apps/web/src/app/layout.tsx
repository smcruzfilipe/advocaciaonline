import type { Metadata } from "next";
import type { ReactNode } from "react";
import { ApplicationShell } from "@/components/application-shell";
import { SessionProvider } from "@/components/session-provider";
import "@fontsource/ibm-plex-sans/latin-400.css";
import "@fontsource/ibm-plex-sans/latin-500.css";
import "@fontsource/ibm-plex-sans/latin-600.css";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Central de Processos",
    template: "%s · Central de Processos",
  },
  description: "Monitoramentos e comunicações jurídicas da sua equipe.",
  referrer: "no-referrer",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="pt-BR">
      <body>
        <a
          className="fixed left-4 -top-20 z-50 bg-primary px-4 py-3 text-primary-foreground focus:top-4"
          href="#conteudo"
        >
          Ir para o conteúdo
        </a>
        <SessionProvider>
          <ApplicationShell>{children}</ApplicationShell>
        </SessionProvider>
      </body>
    </html>
  );
}
