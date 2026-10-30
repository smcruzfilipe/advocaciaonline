"use client";

import { useParams } from "next/navigation";
import GroupDetail from "../group-detail";

export default function GroupPage() {
  const { id } = useParams<{ id: string }>();
  return <GroupDetail key={id} id={id} />;
}
