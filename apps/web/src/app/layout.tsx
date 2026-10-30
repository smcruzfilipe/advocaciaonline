import type { Metadata } from "next";
import type { ReactNode } from "react";
import { ApplicationShell } from "@/components/application-shell";
import { SessionProvider } from "@/components/session-provider";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Advocacia Online", template: "%s · Advocacia Online" },
  description: "Monitoramentos e comunicações jurídicas da sua equipe.",
  referrer: "no-referrer",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="pt-BR">
      <body>
        <a className="skip-link" href="#conteudo">
          Ir para o conteúdo
        </a>
        <SessionProvider>
          <ApplicationShell>{children}</ApplicationShell>
        </SessionProvider>
      </body>
    </html>
  );
}
