"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { asError } from "./monitoring";

export function useRemote<T>(path: string) {
  const [response, setResponse] = useState<{
    path: string;
    revision: number;
    data?: T;
    error?: Error;
  }>();
  const [revision, setRevision] = useState(0);
  const reload = useCallback(() => setRevision((value) => value + 1), []);

  useEffect(() => {
    let current = true;
    api<T>(path)
      .then((data) => {
        if (current) setResponse({ path, revision, data });
      })
      .catch((reason: unknown) => {
        if (current) setResponse({ path, revision, error: asError(reason) });
      });
    return () => {
      current = false;
    };
  }, [path, revision]);

  const latest =
    response?.path === path && response.revision === revision
      ? response
      : undefined;
  return {
    data: latest?.data,
    error: latest?.error,
    loading: latest === undefined,
    reload,
  };
}
