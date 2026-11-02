import Image, { type StaticImageData } from "next/image";
import symbolCJF from "@/assets/courts/CJF.png";
import symbolCNJ from "@/assets/courts/CNJ.svg";
import symbolPJeCor from "@/assets/courts/PJeCor.jpg";
import symbolSEEU from "@/assets/courts/SEEU.png";
import symbolSTF from "@/assets/courts/STF.png";
import symbolSTJ from "@/assets/courts/STJ.svg";
import symbolSTM from "@/assets/courts/STM.png";
import symbolTJAC from "@/assets/courts/TJAC.svg";
import symbolTJAL from "@/assets/courts/TJAL.png";
import symbolTJAM from "@/assets/courts/TJAM.png";
import symbolTJAP from "@/assets/courts/TJAP.png";
import symbolTJBA from "@/assets/courts/TJBA.png";
import symbolTJCE from "@/assets/courts/TJCE.png";
import symbolTJDFT from "@/assets/courts/TJDFT.png";
import symbolTJES from "@/assets/courts/TJES.png";
import symbolTJGO from "@/assets/courts/TJGO.png";
import symbolTJMA from "@/assets/courts/TJMA.png";
import symbolTJMG from "@/assets/courts/TJMG.svg";
import symbolTJMMG from "@/assets/courts/TJMMG.png";
import symbolTJMRS from "@/assets/courts/TJMRS.png";
import symbolTJMS from "@/assets/courts/TJMS.svg";
import symbolTJMSP from "@/assets/courts/TJMSP.png";
import symbolTJMT from "@/assets/courts/TJMT.webp";
import symbolTJPA from "@/assets/courts/TJPA.png";
import symbolTJPB from "@/assets/courts/TJPB.png";
import symbolTJPE from "@/assets/courts/TJPE.png";
import symbolTJPI from "@/assets/courts/TJPI.png";
import symbolTJPR from "@/assets/courts/TJPR.png";
import symbolTJRJ from "@/assets/courts/TJRJ.png";
import symbolTJRN from "@/assets/courts/TJRN.svg";
import symbolTJRO from "@/assets/courts/TJRO.png";
import symbolTJRR from "@/assets/courts/TJRR.png";
import symbolTJRS from "@/assets/courts/TJRS.png";
import symbolTJSC from "@/assets/courts/TJSC.png";
import symbolTJSE from "@/assets/courts/TJSE.png";
import symbolTJSP from "@/assets/courts/TJSP.png";
import symbolTJTO from "@/assets/courts/TJTO.png";
import symbolTREAC from "@/assets/courts/TRE-AC.svg";
import symbolTREAL from "@/assets/courts/TRE-AL.svg";
import symbolTREAM from "@/assets/courts/TRE-AM.svg";
import symbolTREAP from "@/assets/courts/TRE-AP.svg";
import symbolTREBA from "@/assets/courts/TRE-BA.svg";
import symbolTRECE from "@/assets/courts/TRE-CE.svg";
import symbolTREDF from "@/assets/courts/TRE-DF.svg";
import symbolTREES from "@/assets/courts/TRE-ES.svg";
import symbolTREGO from "@/assets/courts/TRE-GO.svg";
import symbolTREMA from "@/assets/courts/TRE-MA.svg";
import symbolTREMG from "@/assets/courts/TRE-MG.svg";
import symbolTREMS from "@/assets/courts/TRE-MS.svg";
import symbolTREMT from "@/assets/courts/TRE-MT.svg";
import symbolTREPA from "@/assets/courts/TRE-PA.svg";
import symbolTREPE from "@/assets/courts/TRE-PE.svg";
import symbolTREPI from "@/assets/courts/TRE-PI.svg";
import symbolTREPR from "@/assets/courts/TRE-PR.svg";
import symbolTRERJ from "@/assets/courts/TRE-RJ.svg";
import symbolTRERN from "@/assets/courts/TRE-RN.svg";
import symbolTRERO from "@/assets/courts/TRE-RO.svg";
import symbolTRERS from "@/assets/courts/TRE-RS.svg";
import symbolTRESC from "@/assets/courts/TRE-SC.svg";
import symbolTRESE from "@/assets/courts/TRE-SE.svg";
import symbolTRESP from "@/assets/courts/TRE-SP.svg";
import symbolTRETO from "@/assets/courts/TRE-TO.svg";
import symbolTRF1 from "@/assets/courts/TRF1.png";
import symbolTRF2 from "@/assets/courts/TRF2.svg";
import symbolTRF3 from "@/assets/courts/TRF3.png";
import symbolTRF4 from "@/assets/courts/TRF4.png";
import symbolTRF5 from "@/assets/courts/TRF5.svg";
import symbolTRF6 from "@/assets/courts/TRF6.png";
import symbolTRT1 from "@/assets/courts/TRT1.png";
import symbolTRT10 from "@/assets/courts/TRT10.png";
import symbolTRT11 from "@/assets/courts/TRT11.png";
import symbolTRT12 from "@/assets/courts/TRT12.png";
import symbolTRT13 from "@/assets/courts/TRT13.png";
import symbolTRT14 from "@/assets/courts/TRT14.png";
import symbolTRT15 from "@/assets/courts/TRT15.png";
import symbolTRT16 from "@/assets/courts/TRT16.png";
import symbolTRT17 from "@/assets/courts/TRT17.png";
import symbolTRT18 from "@/assets/courts/TRT18.png";
import symbolTRT19 from "@/assets/courts/TRT19.png";
import symbolTRT2 from "@/assets/courts/TRT2.png";
import symbolTRT20 from "@/assets/courts/TRT20.png";
import symbolTRT21 from "@/assets/courts/TRT21.png";
import symbolTRT22 from "@/assets/courts/TRT22.png";
import symbolTRT23 from "@/assets/courts/TRT23.png";
import symbolTRT24 from "@/assets/courts/TRT24.png";
import symbolTRT3 from "@/assets/courts/TRT3.svg";
import symbolTRT4 from "@/assets/courts/TRT4.png";
import symbolTRT5 from "@/assets/courts/TRT5.png";
import symbolTRT6 from "@/assets/courts/TRT6.png";
import symbolTRT7 from "@/assets/courts/TRT7.png";
import symbolTRT8 from "@/assets/courts/TRT8.png";
import symbolTRT9 from "@/assets/courts/TRT9.png";
import symbolTSE from "@/assets/courts/TSE.svg";
import symbolTST from "@/assets/courts/TST.png";

const symbols: Partial<
  Record<string, { image: StaticImageData; dark: boolean }>
> = {
  CJF: { image: symbolCJF, dark: false },
  CNJ: { image: symbolCNJ, dark: false },
  PJeCor: { image: symbolPJeCor, dark: false },
  SEEU: { image: symbolSEEU, dark: false },
  STF: { image: symbolSTF, dark: false },
  STJ: { image: symbolSTJ, dark: false },
  STM: { image: symbolSTM, dark: false },
  TJAC: { image: symbolTJAC, dark: false },
  TJAL: { image: symbolTJAL, dark: true },
  TJAM: { image: symbolTJAM, dark: false },
  TJAP: { image: symbolTJAP, dark: false },
  TJBA: { image: symbolTJBA, dark: false },
  TJCE: { image: symbolTJCE, dark: false },
  TJDFT: { image: symbolTJDFT, dark: false },
  TJES: { image: symbolTJES, dark: false },
  TJGO: { image: symbolTJGO, dark: false },
  TJMA: { image: symbolTJMA, dark: false },
  TJMG: { image: symbolTJMG, dark: true },
  TJMMG: { image: symbolTJMMG, dark: true },
  TJMRS: { image: symbolTJMRS, dark: false },
  TJMS: { image: symbolTJMS, dark: false },
  TJMSP: { image: symbolTJMSP, dark: false },
  TJMT: { image: symbolTJMT, dark: false },
  TJPA: { image: symbolTJPA, dark: false },
  TJPB: { image: symbolTJPB, dark: false },
  TJPE: { image: symbolTJPE, dark: false },
  TJPI: { image: symbolTJPI, dark: true },
  TJPR: { image: symbolTJPR, dark: true },
  TJRJ: { image: symbolTJRJ, dark: true },
  TJRN: { image: symbolTJRN, dark: false },
  TJRO: { image: symbolTJRO, dark: false },
  TJRR: { image: symbolTJRR, dark: true },
  TJRS: { image: symbolTJRS, dark: false },
  TJSC: { image: symbolTJSC, dark: false },
  TJSE: { image: symbolTJSE, dark: false },
  TJSP: { image: symbolTJSP, dark: false },
  TJTO: { image: symbolTJTO, dark: true },
  "TRE-AC": { image: symbolTREAC, dark: false },
  "TRE-AL": { image: symbolTREAL, dark: false },
  "TRE-AM": { image: symbolTREAM, dark: false },
  "TRE-AP": { image: symbolTREAP, dark: false },
  "TRE-BA": { image: symbolTREBA, dark: false },
  "TRE-CE": { image: symbolTRECE, dark: false },
  "TRE-DF": { image: symbolTREDF, dark: false },
  "TRE-ES": { image: symbolTREES, dark: false },
  "TRE-GO": { image: symbolTREGO, dark: false },
  "TRE-MA": { image: symbolTREMA, dark: false },
  "TRE-MG": { image: symbolTREMG, dark: false },
  "TRE-MS": { image: symbolTREMS, dark: false },
  "TRE-MT": { image: symbolTREMT, dark: false },
  "TRE-PA": { image: symbolTREPA, dark: false },
  "TRE-PE": { image: symbolTREPE, dark: false },
  "TRE-PI": { image: symbolTREPI, dark: false },
  "TRE-PR": { image: symbolTREPR, dark: false },
  "TRE-RJ": { image: symbolTRERJ, dark: false },
  "TRE-RN": { image: symbolTRERN, dark: false },
  "TRE-RO": { image: symbolTRERO, dark: false },
  "TRE-RS": { image: symbolTRERS, dark: false },
  "TRE-SC": { image: symbolTRESC, dark: false },
  "TRE-SE": { image: symbolTRESE, dark: false },
  "TRE-SP": { image: symbolTRESP, dark: false },
  "TRE-TO": { image: symbolTRETO, dark: false },
  TRF1: { image: symbolTRF1, dark: false },
  TRF2: { image: symbolTRF2, dark: false },
  TRF3: { image: symbolTRF3, dark: true },
  TRF4: { image: symbolTRF4, dark: true },
  TRF5: { image: symbolTRF5, dark: false },
  TRF6: { image: symbolTRF6, dark: true },
  TRT1: { image: symbolTRT1, dark: false },
  TRT10: { image: symbolTRT10, dark: false },
  TRT11: { image: symbolTRT11, dark: false },
  TRT12: { image: symbolTRT12, dark: false },
  TRT13: { image: symbolTRT13, dark: false },
  TRT14: { image: symbolTRT14, dark: false },
  TRT15: { image: symbolTRT15, dark: false },
  TRT16: { image: symbolTRT16, dark: false },
  TRT17: { image: symbolTRT17, dark: false },
  TRT18: { image: symbolTRT18, dark: false },
  TRT19: { image: symbolTRT19, dark: false },
  TRT2: { image: symbolTRT2, dark: false },
  TRT20: { image: symbolTRT20, dark: false },
  TRT21: { image: symbolTRT21, dark: false },
  TRT22: { image: symbolTRT22, dark: false },
  TRT23: { image: symbolTRT23, dark: false },
  TRT24: { image: symbolTRT24, dark: false },
  TRT3: { image: symbolTRT3, dark: false },
  TRT4: { image: symbolTRT4, dark: false },
  TRT5: { image: symbolTRT5, dark: false },
  TRT6: { image: symbolTRT6, dark: false },
  TRT7: { image: symbolTRT7, dark: false },
  TRT8: { image: symbolTRT8, dark: false },
  TRT9: { image: symbolTRT9, dark: false },
  TSE: { image: symbolTSE, dark: false },
  TST: { image: symbolTST, dark: false },
};

export function CourtSymbol({ court }: { court: string }) {
  const symbol = symbols[court];
  if (!symbol) return null;
  return (
    <Image
      src={symbol.image}
      alt=""
      sizes="112px"
      className={`h-12 w-28 shrink-0 object-contain ${symbol.dark ? "brightness-0" : ""} ${court === "STF" ? "bg-neutral-900 p-1" : ""}`}
    />
  );
}
