const MAX_INVITATION_BODY_BYTES = 1024;
const INVITATION_BODY_TIMEOUT_MS = 5_000;

export async function readInvitationBody(request: Request): Promise<unknown> {
  if (!request.body) throw new Error("Missing invitation body");
  const reader = request.body.getReader();
  const deadline = Promise.withResolvers<never>();
  const timer = setTimeout(
    () => deadline.reject(new Error("Invitation body timed out")),
    INVITATION_BODY_TIMEOUT_MS,
  );
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await Promise.race([
        reader.read(),
        deadline.promise,
      ]);
      if (done) break;
      size += value.byteLength;
      if (size > MAX_INVITATION_BODY_BYTES)
        throw new Error("Invitation body too large");
      chunks.push(value);
    }
    const body = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      body.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(body));
  } finally {
    clearTimeout(timer);
    void reader.cancel().catch(() => undefined);
  }
}
