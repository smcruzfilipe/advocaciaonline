export function processLabel(
  payload: unknown,
  fallback?: string | null,
  identification?: string | null,
): string;
export function sourceField(payload: unknown, key: string): string;
export function publicationDate(payload: unknown): string;
export function movementDate(payload: unknown): string;
export function stfLinks(payload: unknown): { text: string; href?: string }[];
export function stfCollectionLink(payload: unknown): string | null;
export function stfIncident(payload: unknown): string;
export function processLink(payload: unknown): string | null;
export function publicationContent(
  payload: unknown,
): { text: string; href?: string }[];
