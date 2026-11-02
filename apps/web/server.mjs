import { createServer } from "node:http";
import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import next from "next";
import { trustedProxyHeaders } from "./proxy-trust.mjs";

const port = Number(process.env.PORT || 3000);
const hostname = process.env.HOSTNAME || "0.0.0.0";
const app = next({ dev: false, hostname, port });
const handle = app.getRequestHandler();

await app.prepare();
createServer(async (request, response) => {
  const proxy = process.env.TRUSTED_PROXY_IP;
  let trustedProxy = proxy;
  if (proxy && !isIP(proxy)) {
    try {
      trustedProxy = (await lookup(proxy, { family: 4 })).address;
    } catch {
      trustedProxy = undefined;
    }
  }
  const proxyHeaders = trustedProxyHeaders(
    request.socket.remoteAddress,
    request.headers,
    trustedProxy,
    process.env.AUTH_INGRESS_SECRET,
  );
  const localHealthCheck =
    request.socket.remoteAddress === "127.0.0.1" &&
    request.method === "GET" &&
    request.url === "/login";
  if (!proxyHeaders && !localHealthCheck) {
    response.writeHead(403).end();
    return;
  }
  delete request.headers["x-advocacia-client-ip"];
  delete request.headers["x-advocacia-ingress-secret"];
  if (proxyHeaders) Object.assign(request.headers, proxyHeaders);
  handle(request, response);
}).listen(port, hostname);
