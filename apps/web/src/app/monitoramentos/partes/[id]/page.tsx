import { MonitoringDetail } from "../../monitoring-detail";

export default async function PartePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <MonitoringDetail key={id} kind="party" recordId={id} />;
}
