import { MonitoringDetail } from "../../monitoring-detail";

export default async function ProcessoPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <MonitoringDetail key={id} kind="process" recordId={id} />;
}
