"use client";

import QRCode from "qrcode";
import { useEffect, useRef, useState } from "react";

type Props = { otpauthUri: string };

export function AuthenticatorSetup({ otpauthUri }: Props) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [result, setResult] = useState<{
    uri: string;
    status: "ready" | "error";
  } | null>(null);
  const status = result?.uri === otpauthUri ? result.status : "loading";

  useEffect(() => {
    const element = canvas.current;
    if (!element) return;
    let active = true;

    void QRCode.toCanvas(element, otpauthUri, {
      width: 512,
      margin: 4,
      errorCorrectionLevel: "M",
    }).then(
      () => {
        if (!active) return;
        element.style.removeProperty("width");
        element.style.removeProperty("height");
        setResult({ uri: otpauthUri, status: "ready" });
      },
      () => {
        if (active) setResult({ uri: otpauthUri, status: "error" });
      },
    );

    return () => {
      active = false;
      element.width = element.width;
    };
  }, [otpauthUri]);

  return (
    <div className="flex min-w-0 flex-col gap-3 border border-info bg-info-bg p-4 text-info">
      <h2 className="font-semibold">Configure seu autenticador</h2>
      <p>
        Escaneie o QR code com seu aplicativo autenticador e informe abaixo o
        código de seis dígitos gerado pelo aplicativo.
      </p>
      {status === "loading" && <p role="status">Gerando QR code…</p>}
      {status === "error" && (
        <p role="alert">
          Não foi possível gerar o QR code. Volte à etapa anterior e tente
          novamente.
        </p>
      )}
      <canvas
        ref={canvas}
        role="img"
        aria-label="QR code para configurar o aplicativo autenticador"
        className={
          status === "ready" ? "h-auto w-full max-w-60 bg-white" : "hidden"
        }
      />
    </div>
  );
}
