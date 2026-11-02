import { isIP } from "node:net";

export function trustedProxyHeaders(peer, headers, trustedProxy, secret) {
  const address = peer?.startsWith("::ffff:") ? peer.slice(7) : peer;
  const forwarded = headers["x-forwarded-for"];
  const client =
    typeof forwarded === "string" ? forwarded.split(",").at(-1).trim() : "";
  if (
    !isIP(trustedProxy ?? "") ||
    address !== trustedProxy ||
    !isIP(client) ||
    Buffer.byteLength(secret ?? "") < 32
  )
    return null;
  return {
    "x-advocacia-client-ip": client,
    "x-advocacia-ingress-secret": secret,
  };
}
