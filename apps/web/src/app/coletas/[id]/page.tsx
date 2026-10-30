import { CollectionRunView } from "./run-view";

export default async function CollectionRunPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <CollectionRunView id={id} />;
}
