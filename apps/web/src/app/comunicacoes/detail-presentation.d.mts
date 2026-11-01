export function processLabel(payload: unknown, fallback?: string): string;
export function sourceField(payload: unknown, key: string): string;
export function publicationDate(payload: unknown): string;
export function processLink(payload: unknown): string | null;
export function publicationContent(
  payload: unknown,
): { text: string; href?: string }[];
