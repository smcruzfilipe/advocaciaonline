import { CommunicationView } from "./communication-view";

export default async function CommunicationPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <CommunicationView id={id} />;
}
